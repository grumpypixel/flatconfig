// Shared utilities for processing include paths.

import 'constants.dart';
import 'parser_utils.dart';

/// Represents a processed include path with its properties.
class ProcessedIncludePath {
  /// Creates a processed include path.
  ProcessedIncludePath({
    required this.path,
    required this.isOptional,
    required this.isEmpty,
  });

  /// The processed path (trimmed, unquoted, unescaped).
  final String path;

  /// Whether the include is optional (prefixed with `?`).
  final bool isOptional;

  /// Whether the path is empty and should be skipped.
  final bool isEmpty;
}

/// Processes a raw include path value according to flatconfig semantics.
///
/// This function handles:
/// - Trimming whitespace
/// - Detecting and removing the optional prefix (`?`)
/// - Removing surrounding quotes
/// - Unescaping quotes and backslashes
///
/// Returns a [ProcessedIncludePath] with the processed path and metadata.
ProcessedIncludePath processIncludePath(String rawPath) {
  var path = rawPath.trim();

  if (path.isEmpty) {
    return ProcessedIncludePath(
      path: '',
      isOptional: false,
      isEmpty: true,
    );
  }

  final optional = path.startsWith(Constants.optionalIncludePrefix);
  if (optional) {
    path = path.substring(1).trim();
  }

  // Handle quoted paths (for paths that actually start with Constants.quote)
  if (path.startsWith(Constants.quote) && path.endsWith(Constants.quote)) {
    path = path.substring(1, path.length - 1);
  }

  // Always decode simple escapes for include paths to support Windows-like backslashes
  // even when the parser didn't decode quoted escapes.
  path = unescapeQuotesAndBackslashes(path);

  return ProcessedIncludePath(
    path: path,
    isOptional: optional,
    isEmpty: false,
  );
}
