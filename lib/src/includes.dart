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
  /// This method attempts to resolve symbolic links to get the canonical path.
  /// If symbolic link resolution fails, it falls back to the absolute path.
  static Future<String> _canonical(File file) async {
    try {
      final resolved = await file.resolveSymbolicLinks();
      // Normalize case on Windows (case-insensitive FS) for stable canonical keys
      return normalizeCanonicalPath(resolved);
    } catch (_) {
      final abs = file.absolute.path;
      // Normalize case on Windows (case-insensitive FS) for stable canonical keys
      return normalizeCanonicalPath(abs);
    }
  }

  /// Synchronous canonical path resolution.
  static String _canonicalSync(File file) {
    try {
      final resolved = file.resolveSymbolicLinksSync();
      return normalizeCanonicalPath(resolved);
    } catch (_) {
      final abs = file.absolute.path;
      return normalizeCanonicalPath(abs);
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
    File baseFile,
    String canonicalPath, {
    required IncludeTraversal traversal,
    int depth = 0,
  }) async {
    final groups = <List<FlatEntry>>[];
    for (final include in includePaths) {
      final processed = processIncludePath(include);
      if (processed.isEmpty) {
        groups.add(const []);
        continue;
      }

      final includedFile = _resolveChild(baseFile.parent, processed.path);
      if (!await includedFile.exists()) {
        groups.add(_missingOrThrow(processed, canonicalPath));
        continue;
      }

      final subDoc = await parseWithIncludesRecursive(
        includedFile,
        traversal: traversal,
        includedFrom: canonicalPath,
        depth: depth + 1,
      );
      groups.add(subDoc.entries);
    }

    return groups;
  }

  /// Synchronous include processing.
  @visibleForTesting
  static List<List<FlatEntry>> processIncludesSync(
    List<String> includePaths,
    File baseFile,
    String canonicalPath, {
    required IncludeTraversal traversal,
    int depth = 0,
  }) {
    final groups = <List<FlatEntry>>[];
    for (final include in includePaths) {
      final processed = processIncludePath(include);
      if (processed.isEmpty) {
        groups.add(const []);
        continue;
      }

      final includedFile = _resolveChild(baseFile.parent, processed.path);
      if (!includedFile.existsSync()) {
        groups.add(_missingOrThrow(processed, canonicalPath));
        continue;
      }

      final subDoc = parseWithIncludesRecursiveSync(
        includedFile,
        traversal: traversal,
        includedFrom: canonicalPath,
        depth: depth + 1,
      );
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
    final canonicalPath = await _canonical(file);
    final done = traversal.begin(
      canonicalPath,
      reportedAs: file.path,
      includedFrom: includedFrom,
      depth: depth,
    );
    if (done != null) {
      return done;
    }

    if (!await file.exists()) {
      throw MissingIncludeException(file.path, file.path);
    }

    final doc = await parseByteStream(
      file.openRead(),
      options: traversal.options,
      readOptions: traversal.readOptions,
    );

    final groups = await processIncludes(
      collectIncludes(doc, traversal.includeOptions).includeTargets,
      file,
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
    final canonicalPath = _canonicalSync(file);
    final done = traversal.begin(
      canonicalPath,
      reportedAs: file.path,
      includedFrom: includedFrom,
      depth: depth,
    );
    if (done != null) {
      return done;
    }

    if (!file.existsSync()) {
      throw MissingIncludeException(file.path, file.path);
    }

    final doc = FlatDocument.parse(
      file.readAsStringSync(encoding: traversal.readOptions.encoding),
      options: traversal.options,
      lineSplitter: traversal.readOptions.lineSplitter,
    );

    final groups = processIncludesSync(
      collectIncludes(doc, traversal.includeOptions).includeTargets,
      file,
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
