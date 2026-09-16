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

  final optional = path.startsWith(Constants.optionalIncludePrefix);
  if (optional) {
    path = path.substring(1).trim();
  }

  // A single quote character is not a quoted path: it opens one and never
  // closes it. Without the length check both tests below pass for it and the
  // unquoting runs off the end of the string.
  if (path.length >= 2 &&
      path.startsWith(Constants.quote) &&
      path.endsWith(Constants.quote)) {
    path = path.substring(1, path.length - 1);
  }

  // Always decode simple escapes for include paths to support Windows-like backslashes
  // even when the parser didn't decode quoted escapes.
  path = unescapeQuotesAndBackslashes(path);

  // Emptiness is decided on what is left, so a directive that names nothing
  // after the marker and the quotes are gone asks no resolver anything.
  return ProcessedIncludePath(
    path: path,
    isOptional: optional,
    isEmpty: path.isEmpty,
  );
}
