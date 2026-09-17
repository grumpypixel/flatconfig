import 'dart:convert';

import 'constants.dart';
import 'exceptions.dart';
import 'issue.dart';
import 'validation.dart';

/// Parses a value token from a configuration line.
///
/// This function handles the parsing of values in flat configuration files,
/// supporting both quoted and unquoted values with appropriate escaping.
///
/// Parsing rules:
/// - Quoted values preserve inner whitespace and `=` characters
/// - Empty quoted values become empty strings
/// - Unquoted values are trimmed; empty values become `null`
/// - When [decodeEscapesInQuoted] is true, escape sequences are decoded
/// - When [strict] is true, parsing errors throw exceptions
///
/// Parameters:
/// - [raw]: the raw value string to parse
/// - [decodeEscapesInQuoted]: whether to decode escape sequences in quoted values
/// - [strict]: whether to throw exceptions on parsing errors
/// - [lineNumber]: line number for error reporting
/// - [rawLine]: raw line content for error reporting
String? parseValue(
  String raw, {
  bool decodeEscapesInQuoted = false,
  bool strict = false,
  int? lineNumber,
  String? rawLine,
  OnIssue? onIssue,
  int columnOffset = 0,
}) {
  if (raw.isEmpty) {
    return null;
  }

  // trim-left / trim-right without String-Allocations
  var start = 0;
  var end = raw.length;

  // left trim
  while (start < end) {
    final c = raw.codeUnitAt(start);
    if (!isWhitespace(c)) {
      break;
    }
    start++;
  }

  // right trim
  while (end > start) {
    final c = raw.codeUnitAt(end - 1);
    if (!isWhitespace(c)) {
      break;
    }
    end--;
  }

  if (end <= start) {
    return null; // only whitespace
  }

  // quoted?
  if (raw.codeUnitAt(start) == Constants.quoteCharCode) {
    // '"'
    // Search for last unescaped-Quote in the *trimmed* range.
    // We call your existing lastUnescapedQuote, but only on the slicing.
    final slice = raw.substring(start, end); // starts with '"'
    final endIdxInSlice = firstUnescapedQuote(slice, 1);

    if (endIdxInSlice <= 0) {
      // No closing quote in the slice
      if (strict) {
        throw UnterminatedQuoteException(
          lineNumber ?? 0,
          (rawLine ?? raw),
          column: start + 1, // Position of the opening quote
        );
      }

      onIssue?.call(
        FlatIssue(
          kind: FlatIssueKind.unterminatedQuote,
          line: lineNumber ?? 0,
          column: columnOffset + start + 1,
          rawLine: rawLine ?? raw,
        ),
      );

      // lax: treat as unquoted, returning the trimmed token
      return slice;
    }

    // Check for following non-Whitespace-Chars after the Quote (in the slice)
    final afterStart = endIdxInSlice + 1;
    var j = afterStart;
    while (j < slice.length) {
      final c = slice.codeUnitAt(j);
      if (!isWhitespace(c)) {
        // trailing non-ws
        if (strict) {
          throw TrailingCharactersAfterQuoteException(
            lineNumber ?? 0,
            (rawLine ?? raw),
            column: start + j + 1, // Position of the trailing character
          );
        }

        onIssue?.call(
          FlatIssue(
            kind: FlatIssueKind.trailingAfterQuote,
            line: lineNumber ?? 0,
            column: columnOffset + start + j + 1,
            rawLine: rawLine ?? raw,
          ),
        );

        // lax: return the entire trimmed token
        return slice;
      }
      j++;
    }

    // Extract the content between the quotes
    var inner = slice.substring(1, endIdxInSlice);
    if (decodeEscapesInQuoted) {
      inner = unescapeQuotesAndBackslashes(inner);
    }

    return inner;
  }

  // unquoted -> already trimmed; empty -> null (here never empty)
  return raw.substring(start, end);
}

/// Returns true if the character is a whitespace character.
bool isWhitespace(int c) =>
    c == Constants.blankCharCode ||
    c == Constants.tabCharCode ||
    c == Constants.newlineCharCode ||
    c == Constants.carriageReturnCharCode;

/// Strips one layer of quotes from [token] and decodes what they protected.
///
/// The rule SPEC.md 5 states for an inline item: a token wrapped in quotes
/// holds its content verbatim, separator included, and `\"` and `\\` inside it
/// stand for a quote and a backslash. A token that is not wrapped is returned
/// unchanged, so an unquoted backslash stays literal.
///
/// A lone `"` is not a wrapped token: it opens a quote and never closes one.
/// Without the length check both ends match it and the unquoting runs off the
/// end of the string.
String unquoteToken(String token, {bool decodeEscapes = true}) {
  if (token.length < 2 ||
      !token.startsWith(Constants.quote) ||
      !token.endsWith(Constants.quote)) {
    return token;
  }

  final inner = token.substring(1, token.length - 1);

  return decodeEscapes ? unescapeQuotesAndBackslashes(inner) : inner;
}

/// Decodes the escape sequences a quoted value may carry.
///
/// Exactly two of them, per SPEC.md 5.2: `\"` becomes `"` and `\\` becomes
/// `\`. Every other backslash is an ordinary character and is left where it
/// is, so `C:\temp\x` survives and `\n` stays two characters.
String unescapeQuotesAndBackslashes(String s) {
  var needsWork = false;
  for (var i = 0; i + 1 < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == Constants.backslashCharCode) {
      final n = s.codeUnitAt(i + 1);
      if (n == Constants.quoteCharCode || n == Constants.backslashCharCode) {
        needsWork = true;
        break;
      }
    }
  }

  if (!needsWork) {
    return s;
  }

  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == Constants.backslashCharCode && i + 1 < s.length) {
      final n = s.codeUnitAt(i + 1);
      if (n == Constants.quoteCharCode || n == Constants.backslashCharCode) {
        buf.writeCharCode(n);
        i++;
        continue;
      }
    }
    buf.writeCharCode(c);
  }

  return buf.toString();
}

/// Returns true if the character at the given index is an unescaped quote.
///
/// This function checks if a quote character at position [i] in string [s] is
/// not preceded by an odd number of backslashes, making it an actual quote
/// rather than an escaped quote.
bool isUnescapedQuoteAt(String s, int i) {
  if (i < 0 || i >= s.length || s.codeUnitAt(i) != Constants.quoteCharCode) {
    return false;
  } // '"'

  var backslashCount = 0;
  for (
    var j = i - 1;
    j >= 0 && s.codeUnitAt(j) == Constants.backslashCharCode;
    j--
  ) {
    backslashCount++;
  }

  return (backslashCount % 2) == 0;
}

/// Parses [s] as a double, rejecting NaN and the infinities.
///
/// `double.tryParse` accepts `NaN`, `Infinity` and `-Infinity`. NaN in
/// particular defeats every range guard silently: all comparisons with it are
/// false, so `min`/`max` do not reject the value, they simply never apply.
/// A configuration file has no legitimate use for either, so they are not
/// numbers as far as this package is concerned.
double? tryParseFinite(String? s) {
  if (s == null) {
    return null;
  }

  final d = double.tryParse(s);

  return (d == null || !d.isFinite) ? null : d;
}

/// Returns the index of the first unescaped quote at or after [from].
///
/// A quoted value closes at its *first* valid closer (SPEC.md 5.1). Closing at
/// the last one instead would silently accept `"one" junk "two"` as the single
/// value `one" junk "two`.
///
/// Returns -1 if no unescaped quote is found.
int firstUnescapedQuote(String s, int from) {
  for (var i = from; i < s.length; i++) {
    if (s.codeUnitAt(i) == Constants.quoteCharCode &&
        isUnescapedQuoteAt(s, i)) {
      return i;
    }
  }

  return -1;
}

/// Normalizes line endings in text according to the specified terminator.
///
/// This function converts all line endings in [text] to use [lineTerminator]
/// and optionally ensures the text ends with a newline.
///
/// Parameters:
/// - [text]: the text to normalize
/// - [lineTerminator]: the line ending to use (e.g., '\n', '\r\n', '\r')
/// - [ensureTrailingNewline]: whether to add a trailing newline if the text
///   does not already end with one. A trailing newline that was already there
///   is preserved regardless.
String normalizeLineEndings(
  String text, {
  required String lineTerminator,
  bool ensureTrailingNewline = false,
}) {
  checkLineTerminator(lineTerminator);

  // If the original had a trailing newline
  final hadTrailingNewline =
      text.endsWith(Constants.crlf) ||
      text.endsWith(Constants.newline) ||
      text.endsWith(Constants.carriageReturn);

  // Split robustly (\r\n / \n / \r)
  final lines = const LineSplitter().convert(text);
  var out = lines.join(lineTerminator);

  // 1) If the input had a trailing newline, restore it.
  if (hadTrailingNewline && !out.endsWith(lineTerminator)) {
    out += lineTerminator;
  }

  // 2) If the caller explicitly wants a trailing newline, ensure it.
  if (ensureTrailingNewline && !out.endsWith(lineTerminator)) {
    out += lineTerminator;
  }

  return out;
}

/// Splits a string by a single-character separator while respecting quotes and escapes.
///
/// This function splits [s] by [sep] but treats content inside double quotes as
/// a single unit, even if it contains the separator character. Backslash escapes
/// are also respected within quotes.
///
/// Example: `a="x,y",b` -> `["a=\"x,y\"", "b"]`
///
/// This function only decides where the boundaries are. Every other character,
/// backslashes included, is copied through untouched — decoding escapes is
/// [parseValue]'s job, and doing it here too would consume a backslash the
/// caller may not have meant as an escape (`C:\temp\x`).
///
/// Parameters:
/// - [s]: the string to split
/// - [sep]: the single-character separator (must be exactly one character)
List<String> splitRespectingQuotes(String s, String sep) {
  checkSingleCharacter(sep, 'sep');

  final out = <String>[];
  final sepC = sep.codeUnitAt(0);

  final buf = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);

    if (!inQuotes && c == sepC) {
      out.add(buf.toString());
      buf.clear();
      continue;
    }

    // A backslash only ever suppresses a quote, which is the same rule the
    // main parser applies.
    if (c == Constants.quoteCharCode && isUnescapedQuoteAt(s, i)) {
      inQuotes = !inQuotes;
    }

    buf.writeCharCode(c);
  }

  out.add(buf.toString());

  return out;
}

/// Returns the index of the first occurrence of [ch] that is not inside quotes.
///
/// This function searches for the first occurrence of [ch] in [s] that is not
/// inside double quotes. Backslash escapes are respected, so escaped quotes
/// don't count as quote boundaries.
///
/// Returns -1 if no unquoted occurrence of [ch] is found.
///
/// Parameters:
/// - [s]: the string to search in
/// - [ch]: the single character to search for (must be exactly one character)
int indexOfUnquoted(String s, String ch) {
  checkSingleCharacter(ch, 'ch');

  final target = ch.codeUnitAt(0);
  var inQuotes = false;

  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);

    if (c == Constants.quoteCharCode && isUnescapedQuoteAt(s, i)) {
      inQuotes = !inQuotes;
      continue;
    }

    if (!inQuotes && c == target) {
      return i;
    }
  }

  return -1;
}
