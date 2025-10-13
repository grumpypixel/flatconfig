// lib/src/includes.dart
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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
    Map<String, FlatDocument>? cache,
  }) async =>
      parseWithIncludesRecursive(
        file,
        options: options,
        readOptions: readOptions,
        visited: <String>{},
        cache: cache ?? <String, FlatDocument>{},
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
    Map<String, FlatDocument>? cache,
  }) async =>
      parseWithIncludes(
        File(path),
        options: options,
        readOptions: readOptions,
        cache: cache,
      );

  /// Resolves a canonical path for a file, handling symbolic links.
  ///
  /// This method attempts to resolve symbolic links to get the canonical path.
  /// If symbolic link resolution fails, it falls back to the absolute path.
  static Future<String> _canonical(File file) async {
    try {
      return await file.resolveSymbolicLinks();
    } catch (_) {
      return file.absolute.path;
    }
  }

  /// Resolves a child file path relative to a base directory.
  ///
  /// This method properly handles both absolute and relative paths using
  /// the path package for cross-platform compatibility.
  static File _resolveChild(Directory base, String includePath) {
    final String abs = p.isAbsolute(includePath)
        ? includePath
        : p.normalize(p.join(base.path, includePath));
    return File(abs);
  }

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
    Map<String, FlatDocument> cache,
  ) async {
    final includeEntries = <FlatEntry>[];
    for (final include in includePaths) {
      var path = include.trim();
      if (path.isEmpty) {
        continue; // ignore empty include values
      }

      final optional = path.startsWith(Constants.optionalIncludePrefix);
      if (optional) {
        path = path.substring(1).trim();
      }

      // Handle quoted paths (for paths that actually start with [Constants.quote])
      if (path.startsWith(Constants.quote) && path.endsWith(Constants.quote)) {
        path = path.substring(1, path.length - 1);
      }

      // Resolve the include path
      final includedFile = _resolveChild(baseFile.parent, path);

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
        cache: cache,
      );

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
    required Map<String, FlatDocument> cache,
  }) async {
    // Canonicalize the path for cycle detection
    final canonicalPath = await _canonical(file);

    // Check for circular includes
    if (!visited.add(canonicalPath)) {
      throw CircularIncludeException(file.path, canonicalPath);
    }

    // Check if file exists
    if (!await file.exists()) {
      throw MissingIncludeException(file.path, file.path);
    }

    // Return cached parse if available
    final cached = cache[canonicalPath];
    if (cached != null) {
      visited.remove(canonicalPath);

      return cached;
    }

    // Parse the current file
    final doc = await FlatConfig.parseFromByteStream(
      file.openRead(),
      options: options,
      readOptions: readOptions,
    );

    // Process the file according to Ghostty semantics:
    // 1. Collect includes and entries before first include
    // 2. Process all includes at the end, in order
    // 3. Filter entries after first include to not override included keys

    // 1) Collect includes (in order), remember all non-include entries
    final includeValues = <String>[];
    final preIncludeEntries = <FlatEntry>[];
    var seenAnyInclude = false;

    for (final e in doc.entries) {
      if (e.key == options.includeKey) {
        if (e.value != null) {
          final trimmedValue = e.value!.trim();
          if (trimmedValue.isNotEmpty) {
            includeValues.add(trimmedValue);
            seenAnyInclude = true;
          }
        }
        // Don't add the include directive itself to any entries list (including empty ones)
        continue;
      } else if (!seenAnyInclude) {
        // Only add entries that come before the first include
        preIncludeEntries.add(e);
      }
      // Entries after the first include will be handled in the filtering step
    }

    // 2) Resolve includes
    final includeEntries = await processIncludes(
      includeValues,
      file,
      canonicalPath,
      options,
      readOptions,
      visited,
      cache,
    );

    // 3) Ghostty: Entries **after** the first include directive must not
    // override keys that were set in includes.
    // -> therefore we need to know which keys the includes set:
    final keysFromIncludes = includeEntries.map((e) => e.key).toSet();

    // 4) Now filter the **late** original entries (after the first include):
    final filteredTail = <FlatEntry>[];
    if (seenAnyInclude) {
      var afterFirstInclude = false;
      for (final e in doc.entries) {
        if (e.key == options.includeKey) {
          afterFirstInclude = true;
          // Skip empty include directives
          if (e.value == null || e.value!.trim().isEmpty) {
            continue;
          }
          continue;
        }
        if (!afterFirstInclude) {
          continue; // we only consider the "tail"
        }
        if (keysFromIncludes.contains(e.key)) {
          continue; // must not override
        }
        filteredTail.add(e);
      }
    }

    // 5) Final order:
    //    - all entries **before** first include directive
    //    - then **all include entries**
    //    - then the filtered tail entries (that do not override any key from includes)
    final all = <FlatEntry>[
      ...preIncludeEntries,
      ...includeEntries,
      ...filteredTail,
    ];

    // Remove the current file from visited set to allow it to be included again
    // in different contexts (e.g., if it's included from different files)
    visited.remove(canonicalPath);

    final result = FlatDocument(all);

    // Cache the parsed document for future use
    cache[canonicalPath] = result;

    return result;
  }
}
