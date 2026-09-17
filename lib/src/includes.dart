import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'document.dart';
import 'exceptions.dart';
import 'include_assembly.dart';
import 'include_path_utils.dart';
import 'include_traversal.dart';
import 'options.dart';
import 'parser.dart';
import 'path_utils.dart' as path_utils;

/// Extensions for parsing configuration files with includes.
///
/// These extensions provide methods for parsing configuration files
/// with automatic include processing. The includes are processed recursively
/// with cycle detection and support for optional includes.
///
/// Include processing follows Ghostty semantics:
/// - Include directives are processed at the end of the current file
/// - Later entries in the current file do not override entries from included files
/// - Optional includes are prefixed with `?` and are silently ignored if missing
/// - Relative paths are resolved relative to the including file's directory
/// - Absolute paths are used as-is
/// - Circular includes are detected and cause an exception
extension FlatConfigIncludes on FlatDocument {
  /// Parses a configuration file with automatic include processing.
  ///
  /// This method parses a configuration file and automatically processes any
  /// include directives found within it. The include key is configurable via
  /// [FlatIncludeOptions.includeKey] (defaults to `config-file` for Ghostty compatibility).
  /// The includes are processed recursively with cycle detection and support
  /// for optional includes.
  ///
  /// Include processing follows Ghostty semantics:
  /// - Include directives are processed at the end of the current file
  /// - Later entries in the current file do not override entries from included files
  /// - If multiple included files define the same key, the later include wins
  /// - Defensive guard: includes have a maximum recursion depth (default 64)
  /// - Optional includes are prefixed with `?` and are silently ignored if missing
  /// - Relative paths are resolved relative to the including file's directory
  /// - Absolute paths are used as-is
  /// - Circular includes are detected and cause an exception
  ///
  /// Example:
  /// ```dart
  /// // Default behavior (Ghostty compatible)
  /// final doc = await FlatConfigIncludes.parseWithIncludes(File('main.conf'));
  ///
  /// // Custom include key
  /// final doc = await FlatConfigIncludes.parseWithIncludes(
  ///   File('main.conf'),
  ///   options: const FlatIncludeOptions(includeKey: 'include'),
  /// );
  /// ```
  ///
  /// Throws [CircularIncludeException] if a circular include is detected.
  /// Throws [MissingIncludeException] if a required include file is missing.
  static Future<FlatDocument> parseWithIncludes(
    File file, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async => parseWithIncludesRecursive(
    file,
    traversal: IncludeTraversal(
      options: options,
      includeOptions: includeOptions,
      readOptions: readOptions,
    ),
  );

  /// Synchronous variant of [parseWithIncludes].
  ///
  /// Parses a configuration file with automatic include processing, using
  /// synchronous filesystem APIs.
  static FlatDocument parseWithIncludesSync(
    File file, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) => parseWithIncludesRecursiveSync(
    file,
    traversal: IncludeTraversal(
      options: options,
      includeOptions: includeOptions,
      readOptions: readOptions,
    ),
  );

  /// Resolves a canonical path for a file, handling symbolic links.
  ///
  /// Where [file] really is, following symbolic links.
  ///
  /// Identity and resolution both start here and then part ways: an identity
  /// folds case where the filesystem does, while a directory a child is
  /// resolved against must stay exactly as the filesystem spells it.
  static Future<String> _realPath(File file) async {
    try {
      return await file.resolveSymbolicLinks();
    } catch (_) {
      return file.absolute.path;
    }
  }

  /// Synchronous counterpart to [_realPath].
  static String _realPathSync(File file) {
    try {
      return file.resolveSymbolicLinksSync();
    } catch (_) {
      return file.absolute.path;
    }
  }

  /// Resolves a child file path relative to a base directory.
  ///
  /// This method properly handles both absolute and relative paths using
  /// the path package for cross-platform compatibility.
  static File _resolveChild(Directory base, String includePath) {
    final abs = p.isAbsolute(includePath)
        ? includePath
        : p.normalize(p.join(base.path, includePath));
    return File(abs);
  }

  /// Processes a list of include paths and returns the combined entries.
  ///
  /// This method handles path resolution, optional includes, quoted paths,
  /// and recursive parsing of included files.
  @visibleForTesting
  static Future<List<List<FlatEntry>>> processIncludes(
    List<String> includePaths,
    Directory baseDir,
    String canonicalPath, {
    required IncludeTraversal traversal,
    int depth = 0,
  }) async {
    final groups = <List<FlatEntry>>[];
    for (final include in includePaths) {
      final processed = processIncludePath(
        include,
        decodeEscapes: traversal.options.decodeEscapesInQuoted,
      );
      if (processed.isEmpty) {
        groups.add(const []);
        continue;
      }

      traversal.chargeInclude(processed.path);

      final includedFile = _resolveChild(baseDir, processed.path);

      final FlatDocument subDoc;
      try {
        subDoc = await parseWithIncludesRecursive(
          includedFile,
          traversal: traversal,
          includedFrom: canonicalPath,
          depth: depth + 1,
        );
      } on PathNotFoundException {
        // The file this directive names is not there, so the `?` marker
        // decides. A miss further down has already been settled by the
        // directive that named it and does not arrive as this exception.
        groups.add(_missingOrThrow(processed, canonicalPath));
        continue;
      }

      traversal.chargeEntries(subDoc.length, canonicalPath);
      groups.add(subDoc.entries);
    }

    return groups;
  }

  /// Synchronous include processing.
  @visibleForTesting
  static List<List<FlatEntry>> processIncludesSync(
    List<String> includePaths,
    Directory baseDir,
    String canonicalPath, {
    required IncludeTraversal traversal,
    int depth = 0,
  }) {
    final groups = <List<FlatEntry>>[];
    for (final include in includePaths) {
      final processed = processIncludePath(
        include,
        decodeEscapes: traversal.options.decodeEscapesInQuoted,
      );
      if (processed.isEmpty) {
        groups.add(const []);
        continue;
      }

      traversal.chargeInclude(processed.path);

      final includedFile = _resolveChild(baseDir, processed.path);

      final FlatDocument subDoc;
      try {
        subDoc = parseWithIncludesRecursiveSync(
          includedFile,
          traversal: traversal,
          includedFrom: canonicalPath,
          depth: depth + 1,
        );
      } on PathNotFoundException {
        groups.add(_missingOrThrow(processed, canonicalPath));
        continue;
      }

      traversal.chargeEntries(subDoc.length, canonicalPath);
      groups.add(subDoc.entries);
    }

    return groups;
  }

  /// An unresolved include contributes nothing when optional, and throws
  /// otherwise.
  static List<FlatEntry> _missingOrThrow(
    ProcessedIncludePath processed,
    String includingPath,
  ) {
    if (processed.isOptional) {
      return const [];
    }

    throw MissingIncludeException(includingPath, processed.path);
  }

  /// Internal recursive method for parsing with includes.
  ///
  /// This method handles the recursive processing of includes with cycle detection
  /// and proper path resolution.
  @visibleForTesting
  static Future<FlatDocument> parseWithIncludesRecursive(
    File file, {
    required IncludeTraversal traversal,
    String? includedFrom,
    int depth = 0,
  }) async {
    final realPath = await _realPath(file);
    final canonicalPath = normalizeCanonicalPath(realPath);
    final done = traversal.begin(
      canonicalPath,
      reportedAs: file.path,
      includedFrom: includedFrom,
      depth: depth,
    );
    if (done != null) {
      return done;
    }

    // Read rather than ask. An existence check answers for a moment that has
    // passed by the time of the read, and turns every other failure — no
    // permission, a directory in the way — into "no such include", which an
    // optional directive then skips without a word.
    final FlatDocument doc;
    try {
      doc = await parseByteStream(
        file.openRead(),
        options: traversal.options,
        readOptions: traversal.readOptions,
      );
    } on PathNotFoundException {
      // Only this unit is missing. At the root that is the caller's file and
      // nothing can make it optional; deeper, the directive that named it
      // decides, so the failure belongs to whoever is holding it.
      if (depth == 0) {
        throw MissingIncludeException(file.path, file.path);
      }

      rethrow;
    }

    final groups = await processIncludes(
      collectIncludes(doc, traversal.includeOptions).includeTargets,
      File(realPath).parent,
      canonicalPath,
      traversal: traversal,
      depth: depth,
    );

    return _assemble(doc, canonicalPath, groups, traversal);
  }

  /// Internal synchronous recursive method for parsing with includes.
  @visibleForTesting
  static FlatDocument parseWithIncludesRecursiveSync(
    File file, {
    required IncludeTraversal traversal,
    String? includedFrom,
    int depth = 0,
  }) {
    final realPath = _realPathSync(file);
    final canonicalPath = normalizeCanonicalPath(realPath);
    final done = traversal.begin(
      canonicalPath,
      reportedAs: file.path,
      includedFrom: includedFrom,
      depth: depth,
    );
    if (done != null) {
      return done;
    }

    final FlatDocument doc;
    try {
      doc = FlatDocument.parse(
        file.readAsStringSync(encoding: traversal.readOptions.encoding),
        options: traversal.options,
        lineSplitter: traversal.readOptions.lineSplitter,
      );
    } on PathNotFoundException {
      if (depth == 0) {
        throw MissingIncludeException(file.path, file.path);
      }

      rethrow;
    }

    final groups = processIncludesSync(
      collectIncludes(doc, traversal.includeOptions).includeTargets,
      File(realPath).parent,
      canonicalPath,
      traversal: traversal,
      depth: depth,
    );

    return _assemble(doc, canonicalPath, groups, traversal);
  }

  static FlatDocument _assemble(
    FlatDocument doc,
    String canonicalPath,
    List<List<FlatEntry>> groups,
    IncludeTraversal traversal,
  ) => traversal.finish(
    canonicalPath,
    assembleIncludedDocument(doc, traversal.includeOptions, groups),
  );

  /// Normalizes a canonical path for case-insensitive filesystems.
  ///
  /// This method ensures that the path is normalized and converted to lowercase
  /// on case-insensitive filesystems (Windows and macOS/APFS) to ensure consistent canonical paths.
  @visibleForTesting
  static String normalizeCanonicalPath(String path) =>
      path_utils.normalizeCanonicalPath(path);
}
