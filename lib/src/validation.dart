import 'constants.dart';

/// Why [key] is not a valid configuration key, or `null` if it is.
///
/// The rules are SPEC.md 3. Each one exists because the key would otherwise
/// not survive being written out and read back:
///
/// - an empty key has no wire form at all;
/// - edge whitespace is trimmed away by the parser;
/// - `=` would be read as the separator, splitting the key;
/// - a leading `"` would be read as the start of a quoted value;
/// - a line break would split the entry across two lines;
/// - a leading `#` would make the whole line a comment, and the entry would
///   vanish without a trace.
///
/// The comment prefix is checked against the default `#` rather than the
/// configured one on purpose: a document is written once and read by many, so
/// key validity must not depend on the options of whoever happens to parse it.
///
/// Returns a reason phrased to follow the key, e.g. "must not be empty".
String? invalidKeyReason(String key) {
  if (key.isEmpty) {
    return 'must not be empty';
  }

  if (key.trim().length != key.length) {
    return 'must not have leading or trailing whitespace';
  }

  if (key.contains(Constants.pairSeparator)) {
    return "must not contain '${Constants.pairSeparator}'";
  }

  if (key.contains(Constants.quote)) {
    return 'must not contain a double quote';
  }

  if (key.contains(Constants.newline) ||
      key.contains(Constants.carriageReturn)) {
    return 'must not contain a line break';
  }

  if (key.startsWith(Constants.commentPrefix)) {
    return "must not begin with '${Constants.commentPrefix}'";
  }

  return null;
}

/// Why [value] cannot be written out, or `null` if it can.
///
/// A line break is the only thing a value may not contain (SPEC.md 7): the
/// format is line-based, so `x\ny` is written as two physical lines and reads
/// back as `x` followed by a line the parser cannot make sense of. Everything
/// else — quotes, `=`, leading `#`, whitespace — is representable, because the
/// encoder can quote and escape it.
///
/// A `null` value is valid; it is the explicit reset.
String? invalidValueReason(String? value) {
  if (value == null) {
    return null;
  }

  if (value.contains(Constants.newline) ||
      value.contains(Constants.carriageReturn)) {
    return 'must not contain a line break';
  }

  return null;
}

/// Throws an [ArgumentError] unless [value] is exactly one character.
///
/// Separators are compared by code unit, so anything longer would silently
/// match nothing.
void checkSingleCharacter(String value, String name) {
  if (value.length != 1) {
    throw ArgumentError.value(value, name, 'Must be a single character');
  }
}

/// Throws an [ArgumentError] unless [value] is a line terminator.
///
/// The three the parser recognises, and no others. Rejecting only the empty
/// string let `lineTerminator: '|'` write every entry onto one physical line,
/// which reads back as a single entry: an option that quietly produced a
/// document the package cannot parse.
void checkLineTerminator(String value) {
  const accepted = [
    Constants.newline,
    Constants.carriageReturn,
    '${Constants.carriageReturn}${Constants.newline}',
  ];

  if (!accepted.contains(value)) {
    throw ArgumentError.value(
      value,
      'lineTerminator',
      r'Must be one of "\n", "\r" or "\r\n"',
    );
  }
}

/// Throws an [ArgumentError] unless [prefix] can mark a comment line.
///
/// An empty prefix is allowed and disables comments. A prefix spanning a line
/// break is not, since no single line could ever match it.
void checkCommentPrefix(String prefix) {
  if (prefix.contains(Constants.newline) ||
      prefix.contains(Constants.carriageReturn)) {
    throw ArgumentError.value(
      prefix,
      'commentPrefix',
      'Must not contain a line break',
    );
  }
}

/// Throws an [ArgumentError] unless [value] is zero or more.
///
/// For the limits and budgets the options classes carry. Each asserts its own
/// too, which catches a literal at compile time, but a release build drops the
/// assertion and a computed value would go through unchecked — so the code
/// that relies on the limit checks it as well.
void checkNonNegative(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'Must not be negative');
  }
}

/// Throws an [ArgumentError] unless [key] is valid.
///
/// Used at every boundary where a key enters a document from outside. The
/// parser reports the same rules as a [FlatParseException] instead, because it
/// knows the line number and has to honour lax mode.
void checkKey(String key, [String name = 'key']) {
  final reason = invalidKeyReason(key);
  if (reason != null) {
    throw ArgumentError.value(key, name, 'Key $reason');
  }
}

/// Throws an [ArgumentError] if [key] would read back as a comment.
///
/// Key validity is judged against the default `#`, so that a document does not
/// become invalid because of the options of whoever parses it (SPEC.md 3). A
/// configured prefix therefore escapes that check, and `;secret = value`
/// encodes cleanly and re-parses as a comment — the entry gone without a
/// trace. SPEC.md 3 puts the check here instead, at the one point where the
/// prefix in force is known.
void checkKeyAgainstCommentPrefix(String key, String commentPrefix) {
  if (commentPrefix.isEmpty || !key.startsWith(commentPrefix)) {
    return;
  }

  throw ArgumentError.value(
    key,
    'key',
    "Key must not begin with the comment prefix '$commentPrefix'",
  );
}
