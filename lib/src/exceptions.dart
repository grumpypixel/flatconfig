import 'package:meta/meta.dart';

/// Base class for all parser-related exceptions with consistent message format.
///
/// This abstract class extends [FormatException] and provides a consistent
/// format for all parsing errors, including line and column information for
/// better error reporting and debugging.
abstract class FlatParseException extends FormatException {
  /// Creates a new [FlatParseException] with the specified details.
  ///
  /// The [message] describes the type of error that occurred, [lineNumber]
  /// indicates the 1-based line number where the error was found, and [rawLine]
  /// contains the actual line content that caused the error.
  FlatParseException(
    String message,
    this.lineNumber,
    this.rawLine, {
    int? column,
  }) : super(
          _composeMessage(message, lineNumber, rawLine, column ?? 0),
          rawLine,
          column ?? 0,
        );

  /// The 1-based line number where the error occurred.
  ///
  /// This helps identify the exact location of the parsing error in the
  /// configuration file.
  final int lineNumber;

  /// The raw line content that caused the exception.
  ///
  /// This contains the actual text that was being parsed when the error occurred,
  /// which is useful for debugging and error reporting.
  final String rawLine;

  static String _composeMessage(
    String base,
    int line,
    String raw,
    int column,
  ) =>
      '$base at line $line, column $column: $raw';
}

/// Thrown when a key-value pair is missing a separator (e.g., '=').
///
/// This exception is thrown when a line that should contain a configuration
/// entry doesn't have the required `=` separator between the key and value.
///
/// Example of invalid line: `background 343028` (missing `=`)
class MissingEqualsException extends FlatParseException {
  /// Creates a new [MissingEqualsException].
  MissingEqualsException(
    int lineNumber,
    String rawLine, {
    int? column,
  }) : super(errorMissingEquals, lineNumber, rawLine, column: column);
}

/// Thrown when a key is empty (e.g., '= value').
///
/// This exception is thrown when a configuration line has a value but no key,
/// which is not allowed in flat configuration files.
///
/// Example of invalid line: `= 343028` (empty key)
class EmptyKeyException extends FlatParseException {
  /// Creates a new [EmptyKeyException].
  EmptyKeyException(
    int lineNumber,
    String rawLine, {
    int? column,
  }) : super(errorEmptyKey, lineNumber, rawLine, column: column);
}

/// Thrown when a quoted value is not properly closed.
///
/// This exception is thrown when a line contains a quoted value that doesn't
/// have a matching closing quote, which makes the line invalid.
///
/// Example of invalid line: `title = "My Application` (missing closing quote)
class UnterminatedQuoteException extends FlatParseException {
  /// Creates a new [UnterminatedQuoteException].
  UnterminatedQuoteException(
    int lineNumber,
    String rawLine, {
    int? column,
  }) : super(errorUnterminatedQuote, lineNumber, rawLine, column: column);
}

/// Thrown when characters appear after a properly closed quoted value.
///
/// This exception is thrown when a quoted value is properly closed but there
/// are additional characters after the closing quote, which is not allowed.
///
/// Example of invalid line: `title = "My App" extra text` (trailing characters)
class TrailingCharactersAfterQuoteException extends FlatParseException {
  /// Creates a new [TrailingCharactersAfterQuoteException].
  TrailingCharactersAfterQuoteException(
    int lineNumber,
    String rawLine, {
    int? column,
  }) : super(errorTrailingAfterQuote, lineNumber, rawLine, column: column);
}

@internal
extension FormatExceptionCopyWith on FormatException {
  /// Creates a new [FormatException] with a custom message,
  /// preserving the original source and offset for IDE highlighting.
  ///
  /// This is useful for creating more specific error messages while maintaining
  /// the original error location information for debugging.
  FormatException copyWithMessage(String newMessage) =>
      FormatException(newMessage, source, offset);
}

@internal
extension FormatExceptionExplain on FormatException {
  /// Adds context information (e.g., key and actual value)
  /// to an existing [FormatException] message.
  ///
  /// This extension method is used internally to provide more detailed error
  /// messages that include the configuration key and the actual value that
  /// caused the error.
  FormatException explain({required String key, String? got}) {
    final suffix = got == null ? '' : " (got: '$got')";
    return FormatException('$message for "$key"$suffix', source, offset);
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
