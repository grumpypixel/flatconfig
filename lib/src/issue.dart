import 'exceptions.dart';

/// The kinds of problem a parser can find in a line.
///
/// New kinds are added over time. Handle the ones you care about and let the
/// rest fall through a `default`, rather than switching exhaustively.
enum FlatIssueKind {
  /// The line has no `=` separator, so it is neither a key nor a comment.
  missingEquals,

  /// Everything left of the `=` was whitespace, as in `= value`.
  emptyKey,

  /// The key cannot be written back out (SPEC.md 3), so reading it would not
  /// round-trip. [FlatIssue.detail] says which rule it breaks.
  invalidKey,

  /// A value opened with `"` that is never closed.
  unterminatedQuote,

  /// A quoted value is followed by something other than whitespace, as in
  /// `a = "one" junk`.
  trailingAfterQuote,
}

/// A problem found while parsing, reported when
/// [FlatParseOptions.strict] is false.
///
/// In strict mode the equivalent [FlatParseException] is thrown instead. The
/// two carry the same information, so a caller can log issues during
/// development and switch to strict in production without losing detail.
final class FlatIssue {
  /// Creates an issue at a 1-based [line] and [column] of [rawLine].
  const FlatIssue({
    required this.kind,
    required this.line,
    required this.column,
    required this.rawLine,
    this.detail,
  });

  /// What went wrong.
  final FlatIssueKind kind;

  /// The 1-based line number, or 0 when the source was a single line with no
  /// position given.
  final int line;

  /// The 1-based column the problem starts at.
  final int column;

  /// The line as it appeared in the source, before trimming.
  final String rawLine;

  /// Extra context for kinds that have more than one cause, currently only
  /// [FlatIssueKind.invalidKey].
  final String? detail;

  /// A human-readable description, without the position.
  String get message => switch (kind) {
    FlatIssueKind.missingEquals => 'Missing "=" separator',
    FlatIssueKind.emptyKey => 'Empty key',
    FlatIssueKind.invalidKey => detail ?? 'Invalid key',
    FlatIssueKind.unterminatedQuote => 'Unterminated quote',
    FlatIssueKind.trailingAfterQuote => 'Trailing characters after quote',
  };

  @override
  String toString() => 'FlatIssue($message at line $line, column $column)';

  @override
  bool operator ==(Object other) =>
      other is FlatIssue &&
      other.kind == kind &&
      other.line == line &&
      other.column == column &&
      other.rawLine == rawLine &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, line, column, rawLine, detail);
}

/// Handler invoked for each [FlatIssue] found in lenient mode.
///
/// Returning normally means "skip this line and carry on". Throwing from the
/// handler aborts the parse, which is one way to build a policy stricter than
/// [FlatParseOptions.strict] without being all-or-nothing.
typedef OnIssue = void Function(FlatIssue issue);

/// Delivers [issue] the way [strict] asks for.
///
/// Strict mode throws a [FlatParseException] carrying it; lenient mode hands
/// it to [onIssue], if there is one, and returns so the caller can skip the
/// line. One construction site for both, which is what keeps the two modes
/// naming the same character: they used to build their own positions and
/// disagreed by however much whitespace had been trimmed.
void reportIssue(FlatIssue issue, {required bool strict, OnIssue? onIssue}) {
  if (strict) {
    throw FlatParseException(issue);
  }

  onIssue?.call(issue);
}
