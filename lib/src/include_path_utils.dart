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
/// - Unescaping quotes and backslashes, inside quotes only
///
/// [decodeEscapes] mirrors [FlatParseOptions.decodeEscapesInQuoted] and only
/// applies to a path this function unquotes itself. A `?` marker hides the
/// quotes from the parser — `?"a\\b"` is not a quoted value to it — so the
/// same path reaches here already decoded without the marker and still
/// wrapped with it. Passing the option through is what makes the two agree.
///
/// Returns a [ProcessedIncludePath] with the processed path and metadata.
ProcessedIncludePath processIncludePath(
  String rawPath, {
  bool decodeEscapes = true,
}) {
  var path = rawPath.trim();

  final optional = path.startsWith(Constants.optionalIncludePrefix);
  if (optional) {
    path = path.substring(1).trim();
  }

  // An unquoted path is literal (SPEC.md 5), which unquoteToken respects.
  // Decoding it anyway cost a bare Windows UNC path one of its two leading
  // backslashes, turning \\server\share into \server\share.
  path = unquoteToken(path, decodeEscapes: decodeEscapes);

  // Emptiness is decided on what is left, so a directive that names nothing
  // after the marker and the quotes are gone asks no resolver anything.
  return ProcessedIncludePath(
    path: path,
    isOptional: optional,
    isEmpty: path.isEmpty,
  );
}
