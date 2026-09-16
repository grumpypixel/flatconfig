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
