import 'dart:convert';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'exceptions.dart';

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
    final slice = raw.substring(start, end); // beginnt mit '"'
    final endIdxInSlice = lastUnescapedQuote(slice);

    if (endIdxInSlice <= 0) {
      // No closing quote in the slice
      if (strict) {
        throw UnterminatedQuoteException(lineNumber ?? 0, (rawLine ?? raw));
      }

      // lax: as before -> treat as unquoted (return trimmed token)
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
          );
        }

        // lax: return the entire trimmed token as before
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
@internal
bool isWhitespace(int c) =>
    c == Constants.blankCharCode ||
    c == Constants.tabCharCode ||
    c == Constants.newlineCharCode ||
    c == Constants.carriageReturnCharCode;

/// Decodes escape sequences in quoted values.
///
/// This function processes escape sequences in quoted configuration values:
/// - `\"` becomes `"`
/// - `\\` becomes `\`
/// - Other backslashes are left intact
///
/// This is used when [decodeEscapesInQuoted] is true in parsing options.
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
  for (var j = i - 1;
      j >= 0 && s.codeUnitAt(j) == Constants.backslashCharCode;
      j--) {
    backslashCount++;
  }

  return (backslashCount % 2) == 0;
}

/// Returns the index of the last unescaped quote in the string.
///
/// This function searches backwards through the string to find the last quote
/// that is not escaped by backslashes. Returns -1 if no unescaped quote is found.
int lastUnescapedQuote(String s) {
  for (var i = s.length - 1; i >= 0; i--) {
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
/// - [ensureTrailingNewline]: whether to add a trailing newline if missing
String normalizeLineEndings(
  String text, {
  required String lineTerminator,
  required bool ensureTrailingNewline,
}) {
  assert(lineTerminator.isNotEmpty);

  // If the original had a trailing newline
  final hadTrailingNewline =
      text.endsWith(Constants.crlf) || text.endsWith(Constants.newline) || text.endsWith(Constants.carriageReturn);

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
/// Parameters:
/// - [s]: the string to split
/// - [sep]: the single-character separator (must be exactly one character)
// splitRespectingQuotes
List<String> splitRespectingQuotes(String s, String sep) {
  assert(sep.length == 1, 'sep must be a single character');

  final out = <String>[];
  final q = Constants.quoteCharCode;
  final bs = Constants.backslashCharCode;
  final sepC = sep.codeUnitAt(0);

  final buf = StringBuffer();
  var inQuotes = false;
  var escaped = false;

  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);

    if (escaped) {
      buf.writeCharCode(c);
      escaped = false;
      continue;
    }
    if (c == bs) {
      escaped = true;
      continue;
    }
    if (c == q) {
      inQuotes = !inQuotes;
      buf.writeCharCode(c);
      continue;
    }
    if (!inQuotes && c == sepC) {
      out.add(buf.toString());
      buf.clear();
      continue;
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
// indexOfUnquoted
int indexOfUnquoted(String s, String ch) {
  assert(ch.length == 1, 'ch must be a single character');

  final target = ch.codeUnitAt(0);
  final q = Constants.quoteCharCode;
  final bs = Constants.backslashCharCode;

  var inQuotes = false;
  var escaped = false;

  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);

    if (escaped) {
      escaped = false;
      continue;
    }
    if (c == bs) {
      escaped = true;
      continue;
    }
    if (c == q) {
      inQuotes = !inQuotes;
      continue;
    }

    if (!inQuotes && c == target) {
      return i;
    }
  }

  return -1;
}
