// lib/src/includes.dart
import 'dart:io';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'document.dart';
import 'exceptions.dart';
import 'options.dart';
import 'parser.dart';

/// File-based includes functionality for flat configuration files.
///
/// This class provides static methods for parsing configuration files
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
class FlatConfigIncludes {
  /// Parses a configuration file with automatic include processing.
  ///
  /// This method parses a configuration file and automatically processes any
  /// include directives found within it. The include key is configurable via
  /// [options.includeKey] (defaults to `config-file` for Ghostty compatibility).
  /// The includes are processed recursively with cycle detection and support
  /// for optional includes.
  ///
  /// Include processing follows Ghostty semantics:
  /// - Include directives are processed at the end of the current file
  /// - Later entries in the current file do not override entries from included files
  /// - Optional includes are prefixed with `?` and are silently ignored if missing
  /// - Relative paths are resolved relative to the including file's directory
  /// - Absolute paths are used as-is
  /// - Circular includes are detected and cause an exception
  ///
  /// Example:
  /// ```dart
  /// // Default behavior (Ghostty compatible)
  /// final doc = await FlatConfig.parseWithIncludes(File('main.conf'));
  ///
  /// // Custom include key
  /// final doc = await FlatConfig.parseWithIncludes(
  ///   File('main.conf'),
  ///   options: const FlatParseOptions(includeKey: 'include'),
  /// );
  /// ```
  ///
  /// Throws [CircularIncludeException] if a circular include is detected.
  /// Throws [MissingIncludeException] if a required include file is missing.
  static Future<FlatDocument> parseWithIncludes(
    File file, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async =>
      parseWithIncludesRecursive(
        file,
        options: options,
        readOptions: readOptions,
        visited: <String>{},
      );

  /// Parses a configuration file with includes from a file path.
  ///
  /// This is a convenience method that creates a [File] object from the given
  /// [path] and calls [parseWithIncludes].
  ///
  /// Example:
  /// ```dart
  /// final doc = await FlatConfig.parseWithIncludesFromPath('main.conf');
  /// ```
  static Future<FlatDocument> parseWithIncludesFromPath(
    String path, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async =>
      parseWithIncludes(
        File(path),
        options: options,
        readOptions: readOptions,
      );

  /// Processes a list of include paths and returns the combined entries.
  ///
  /// This method handles path resolution, optional includes, quoted paths,
  /// and recursive parsing of included files.
  @visibleForTesting
  static Future<List<FlatEntry>> processIncludes(
    List<String> includePaths,
    File baseFile,
    String canonicalPath,
    FlatParseOptions options,
    FlatStreamReadOptions readOptions,
    Set<String> visited,
    Set<String> keysSetByIncludes,
  ) async {
    final includeEntries = <FlatEntry>[];
    for (final include in includePaths) {
      var path = include.trim();
      final optional = path.startsWith(Constants.optionalIncludePrefix);
      if (optional) {
        path = path.substring(1).trim();
      }

      // Handle quoted paths (for paths that actually start with [Constants.quote])
      if (path.startsWith(Constants.quote) && path.endsWith(Constants.quote)) {
        path = path.substring(1, path.length - 1);
      }

      // Resolve the include path
      final includedFile = File(
        path.startsWith(Platform.pathSeparator)
            ? path // absolute path
            : '${baseFile.parent.path}/$path', // relative path
      );

      // Check if the included file exists
      if (!await includedFile.exists()) {
        if (!optional) {
          throw MissingIncludeException(canonicalPath, path);
        }
        // Skip optional missing files
        continue;
      }

      // Recursively parse the included file
      final subDoc = await parseWithIncludesRecursive(
        includedFile,
        options: options,
        readOptions: readOptions,
        visited: visited,
      );

      // Track keys set by includes
      for (final entry in subDoc.entries) {
        keysSetByIncludes.add(entry.key);
      }

      // Add sub-document entries
      includeEntries.addAll(subDoc.entries);
    }

    return includeEntries;
  }

  /// Internal recursive method for parsing with includes.
  ///
  /// This method handles the recursive processing of includes with cycle detection
  /// and proper path resolution.
  @visibleForTesting
  static Future<FlatDocument> parseWithIncludesRecursive(
    File file, {
    required FlatParseOptions options,
    required FlatStreamReadOptions readOptions,
    required Set<String> visited,
  }) async {
    // Canonicalize the path for cycle detection
    final canonicalPath = file.absolute.path;

    // Check for circular includes
    if (!visited.add(canonicalPath)) {
      throw CircularIncludeException(canonicalPath, canonicalPath);
    }

    // Check if file exists
    if (!await file.exists()) {
      throw MissingIncludeException(canonicalPath, canonicalPath);
    }

    // Parse the current file
    final doc = await FlatConfig.parseFromByteStream(
      file.openRead(),
      options: options,
      readOptions: readOptions,
    );

    // Process the file according to Ghostty semantics:
    // 1. Process all entries in order, but defer includes until the end
    // 2. Entries after config-file directives do not override included entries
    // 3. Process all includes at the end, in order

    final entries = <FlatEntry>[];
    final includes = <String>[];
    final keysSetByIncludes = <String>{};

    // First pass: collect entries and includes
    for (final entry in doc.entries) {
      if (entry.key == options.includeKey && entry.value != null) {
        includes.add(entry.value!);
      } else {
        entries.add(entry);
      }
    }

    // Second pass: process all includes at the end
    final includeEntries = await processIncludes(
      includes,
      file,
      canonicalPath,
      options,
      readOptions,
      visited,
      keysSetByIncludes,
    );

    // Third pass: filter out entries that come after config-file directives
    // if the key was already set by an include
    final filteredEntries = <FlatEntry>[];
    var foundConfigFile = false;

    for (final entry in doc.entries) {
      if (entry.key == options.includeKey) {
        foundConfigFile = true;
        continue;
      }

      if (foundConfigFile && keysSetByIncludes.contains(entry.key)) {
        // Skip this entry because it comes after a config-file directive
        // and the key was already set by an include
        continue;
      }

      filteredEntries.add(entry);
    }

    // Build final result: filtered entries + includes
    entries.clear();
    entries.addAll(filteredEntries);
    entries.addAll(includeEntries);

    // Remove the current file from visited set to allow it to be included again
    // in different contexts (e.g., if it's included from different files)
    visited.remove(canonicalPath);

    return FlatDocument(entries);
  }
}
