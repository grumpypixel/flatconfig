import 'package:meta/meta.dart';

import 'issue.dart';

/// Thrown in strict mode for a line the format cannot read.
///
/// One type for every way a line can be malformed, carrying the same
/// [FlatIssue] a lenient parse would have reported. Five subclasses used to
/// say what [FlatIssue.kind] says, so the two modes described the same five
/// conditions in two vocabularies — and drifted, reporting different columns
/// for the same character.
///
/// ```dart
/// try {
///   FlatDocument.parse(source, options: const FlatParseOptions(strict: true));
/// } on FlatParseException catch (e) {
///   if (e.issue.kind == FlatIssueKind.invalidKey) {
///     // ...
///   }
/// }
/// ```
class FlatParseException extends FormatException {
  /// Creates an exception reporting [issue].
  FlatParseException(this.issue)
    : super(
        '${issue.message} at line ${issue.line}, '
        'column ${issue.column}: ${issue.rawLine}',
        issue.rawLine,
        // FormatException counts an offset from zero; a displayed column
        // counts from one.
        issue.column > 0 ? issue.column - 1 : 0,
      );

  /// What went wrong, where, and in which line.
  final FlatIssue issue;

  /// What went wrong. Shorthand for `issue.kind`.
  FlatIssueKind get kind => issue.kind;

  /// The 1-based line the problem was found on. Shorthand for `issue.line`.
  int get lineNumber => issue.line;

  /// The line as it appeared in the source. Shorthand for `issue.rawLine`.
  String get rawLine => issue.rawLine;
}

/// Thrown when a config file include fails.
///
/// This exception is thrown when there's an error processing a `config-file`
/// directive, such as a missing required file or a circular include.
class ConfigIncludeException extends FormatException {
  /// Creates a new [ConfigIncludeException].
  ConfigIncludeException(super.message, this.filePath, {this.includePath});

  /// The path of the file that was being processed when the error occurred.
  final String filePath;

  /// The path of the include that caused the error, if applicable.
  final String? includePath;
}

/// Thrown when a circular include is detected.
///
/// This exception is thrown when the config file include chain creates a cycle,
/// which would lead to infinite recursion.
class CircularIncludeException extends ConfigIncludeException {
  /// Creates a new [CircularIncludeException].
  CircularIncludeException(this.includingFile, this.canonicalPath)
    : super(
        'Circular include detected: cycle at "$canonicalPath" (included by "$includingFile")',
        includingFile,
        includePath: canonicalPath,
      );

  /// The file that was trying to include the circular reference.
  final String includingFile;

  /// The canonical path that was already being processed.
  final String canonicalPath;

  @override
  String toString() =>
      'CircularIncludeException: cycle at "$canonicalPath" (included by "$includingFile")';
}

/// Thrown when a required config file include is missing.
///
/// This exception is thrown when a `config-file` directive references a file
/// that doesn't exist and the include is not marked as optional (no `?` prefix).
class MissingIncludeException extends ConfigIncludeException {
  /// Creates a new [MissingIncludeException].
  MissingIncludeException(this.includingFile, this.missingPath)
    : super(
        'Required include file not found: "$missingPath" (required by "$includingFile")',
        includingFile,
        includePath: missingPath,
      );

  /// The file that was trying to include the missing file.
  final String includingFile;

  /// The path of the missing include file.
  final String missingPath;

  @override
  String toString() =>
      'MissingIncludeException: "$missingPath" (required by "$includingFile")';
}

/// Thrown when the maximum include depth is exceeded.
///
/// This defensive guard prevents unbounded recursion in cases where
/// path canonicalization fails or the include graph is excessively deep.
class MaxIncludeDepthExceededException extends ConfigIncludeException {
  /// Creates a new [MaxIncludeDepthExceededException].
  MaxIncludeDepthExceededException(String filePath, this.depth, this.maxDepth)
    : super(
        'Maximum include depth exceeded at "$filePath" (depth=$depth, max=$maxDepth)',
        filePath,
      );

  /// The current include depth at the time of failure.
  final int depth;

  /// The configured maximum allowed include depth.
  final int maxDepth;

  @override
  String toString() =>
      'MaxIncludeDepthExceededException: depth=$depth (max=$maxDepth) at "$filePath"';
}

/// Thrown when an include traversal outgrows one of its budgets.
///
/// Depth alone does not bound an include graph. A document whose includes each
/// pull in the previous one twice doubles per level, and since a repeated unit
/// is parsed once and then copied into every parent that names it, sixteen
/// such levels reach 65,536 entries from under a kilobyte of source — well
/// inside the default depth limit. [budget] names which limit was reached, so
/// the message says what to raise.
class IncludeBudgetExceededException extends ConfigIncludeException {
  /// Creates a new [IncludeBudgetExceededException].
  IncludeBudgetExceededException(String filePath, this.budget, this.limit)
    : super(
        'Include budget exceeded at "$filePath": $budget reached its limit of '
        '$limit',
        filePath,
      );

  /// The name of the option that was reached, as written in the API.
  final String budget;

  /// The value that option held.
  final int limit;

  @override
  String toString() =>
      'IncludeBudgetExceededException: $budget=$limit reached at "$filePath"';
}

@internal
extension FormatExceptionExplain on FormatException {
  /// Adds context information (e.g., key and actual value)
  /// to an existing [FormatException] message.
  ///
  /// This extension method is used internally to provide more detailed error
  /// messages that include the configuration key and the actual value that
  /// caused the error.
  FormatException explain({required String key, String? got, Object? cause}) {
    final suffix = got == null ? '' : " (got: '$got')";
    final causeSuffix = cause == null ? '' : " (cause: $cause)";

    return FormatException(
      '$message for "$key"$suffix$causeSuffix',
      source,
      offset,
    );
  }
}

@internal
const String errorMissingEquals = "Missing '='";

@internal
const String errorEmptyKey = 'Empty key';

@internal
const String errorUnterminatedQuote = 'Unterminated quoted value';

@internal
const String errorInvalidEscape = 'Invalid escape sequence';

@internal
const String errorTrailingAfterQuote = 'Trailing characters after quoted value';
