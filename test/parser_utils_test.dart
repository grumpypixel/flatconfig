import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/src/constants.dart';
import 'package:flatconfig/src/parser_utils.dart';
import 'package:test/test.dart';

void main() {
  group('ParserUtils', () {
    test('parseValue with strict mode throws on unterminated quotes', () {
      expect(
        () => parseValue(
          '"unterminated',
          strict: true,
          lineNumber: 1,
          rawLine: 'key = "unterminated',
        ),
        throwsA(isA<UnterminatedQuoteException>()),
      );
    });

    test(
        'parseValue with strict mode throws on trailing characters after quote',
        () {
      expect(
        () => parseValue(
          '"value" extra',
          strict: true,
          lineNumber: 2,
          rawLine: 'key = "value" extra',
        ),
        throwsA(isA<TrailingCharactersAfterQuoteException>()),
      );
    });

    test('parseValue in lax mode handles unterminated quotes', () {
      final result = parseValue('"unterminated');
      expect(result, '"unterminated');
    });

    test('parseValue in lax mode handles trailing characters after quote', () {
      final result = parseValue('"value" extra');
      expect(result, '"value" extra');
    });

    test('unescapeQuotesAndBackslashes handles escaped quotes and backslashes',
        () {
      expect(unescapeQuotesAndBackslashes(r'He said: \"hello\" \\ o/'),
          r'He said: "hello" \ o/');
      expect(unescapeQuotesAndBackslashes(r'no escapes'), 'no escapes');
      expect(unescapeQuotesAndBackslashes(r'\\'), r'\');
      expect(unescapeQuotesAndBackslashes(r'\"'), '"');
    });

    test('isUnescapedQuoteAt correctly identifies unescaped quotes', () {
      expect(isUnescapedQuoteAt('"hello"', 0), isTrue);
      expect(isUnescapedQuoteAt('"hello"', 6), isTrue);
      expect(isUnescapedQuoteAt(r'\"hello\"', 0), isFalse);
      expect(isUnescapedQuoteAt(r'\"hello\"', 1),
          isFalse); // escaped by backslash at 0
      expect(isUnescapedQuoteAt(r'\\"hello"', 1), isFalse);
      expect(isUnescapedQuoteAt(r'\\"hello"', 2),
          isTrue); // even number of backslashes
      expect(isUnescapedQuoteAt('no quotes', 0), isFalse);
      expect(isUnescapedQuoteAt('', 0), isFalse);
    });

    test('lastUnescapedQuote finds the last unescaped quote', () {
      expect(lastUnescapedQuote('"hello"'), 6);
      expect(lastUnescapedQuote(r'\"hello\"'), -1); // all quotes are escaped
      expect(lastUnescapedQuote(r'\\"hello"'), 8);
      expect(lastUnescapedQuote('no quotes'), -1);
      expect(lastUnescapedQuote(r'\"'), -1);
      expect(lastUnescapedQuote(''), -1);
      expect(lastUnescapedQuote('"'), 0);
    });

    test('normalizeLineEndings handles various line ending scenarios', () {
      // Test with trailing newline
      expect(
          normalizeLineEndings('line1\nline2\n',
              lineTerminator: '\r\n', ensureTrailingNewline: false),
          'line1\r\nline2\r\n');

      // Test without trailing newline
      expect(
          normalizeLineEndings('line1\nline2',
              lineTerminator: '\r\n', ensureTrailingNewline: false),
          'line1\r\nline2');

      // Test ensureTrailingNewline
      expect(
          normalizeLineEndings('line1\nline2',
              lineTerminator: '\n', ensureTrailingNewline: true),
          'line1\nline2\n');

      // Test CRLF input
      expect(
          normalizeLineEndings('line1\r\nline2\r\n',
              lineTerminator: '\n', ensureTrailingNewline: false),
          'line1\nline2\n');

      // Test CR input
      expect(
          normalizeLineEndings('line1\rline2\r',
              lineTerminator: '\n', ensureTrailingNewline: false),
          'line1\nline2\n');
    });

    test('normalizeLineEndings with empty lineTerminator throws', () {
      expect(
        () => normalizeLineEndings('test',
            lineTerminator: '', ensureTrailingNewline: false),
        throwsA(isA<AssertionError>()),
      );
    });

    group('splitRespectingQuotes', () {
      test('splits simple comma-separated values', () {
        final result = splitRespectingQuotes('a,b,c', ',');
        expect(result, ['a', 'b', 'c']);
      });

      test('respects quotes when splitting', () {
        final result = splitRespectingQuotes('a="x,y",b', ',');
        expect(result, ['a="x,y"', 'b']);
      });

      test('handles escaped quotes inside quoted values', () {
        final result = splitRespectingQuotes(r'a="x\"y",b', ',');
        expect(result, ['a="x"y"', 'b']);
      });

      test('handles backslash escapes', () {
        final result = splitRespectingQuotes(r'a="x\\y",b', ',');
        expect(result, ['a="x\\y"', 'b']);
      });

      test('handles empty segments', () {
        final result = splitRespectingQuotes('a,,b', ',');
        expect(result, ['a', '', 'b']);
      });

      test('handles single segment', () {
        final result = splitRespectingQuotes('single', ',');
        expect(result, ['single']);
      });

      test('handles empty string', () {
        final result = splitRespectingQuotes('', ',');
        expect(result, ['']);
      });

      test('handles different separators', () {
        final result = splitRespectingQuotes('a;b;c', ';');
        expect(result, ['a', 'b', 'c']);
      });

      test('throws assertion error for multi-character separator', () {
        expect(
          () => splitRespectingQuotes('a,b,c', '::'),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('indexOfUnquoted', () {
      test('finds unquoted character', () {
        final result = indexOfUnquoted('a,b,c', ',');
        expect(result, 1);
      });

      test('ignores quoted characters', () {
        final result = indexOfUnquoted('a="x,y",b', ',');
        expect(result, 7);
      });

      test('handles escaped quotes', () {
        final result = indexOfUnquoted(r'a="x\"y",b', ',');
        expect(result, 8);
      });

      test('handles backslash escapes', () {
        final result = indexOfUnquoted(r'a="x\\y",b', ',');
        expect(result, 8);
      });

      test('returns -1 when character not found', () {
        final result = indexOfUnquoted('abc', ',');
        expect(result, -1);
      });

      test('returns -1 when character only appears in quotes', () {
        final result = indexOfUnquoted('a="x,y"', ',');
        expect(result, -1);
      });

      test('handles empty string', () {
        final result = indexOfUnquoted('', ',');
        expect(result, -1);
      });

      test('finds first occurrence', () {
        final result = indexOfUnquoted('a,b,c,d', ',');
        expect(result, 1);
      });

      test('throws assertion error for multi-character search', () {
        expect(
          () => indexOfUnquoted('abc', '::'),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('getters', () {
      test('pairSeparatorString returns correct string', () {
        expect(Constants.pairSeparator, '=');
      });
    });

    group('parseValue enhanced tests', () {
      test('handles empty quoted value', () {
        final result = parseValue('""');
        expect(result, '');
      });

      test('handles quoted value with spaces', () {
        final result = parseValue('"  value with spaces  "');
        expect(result, '  value with spaces  ');
      });

      test('handles quoted value with equals sign', () {
        final result = parseValue('"key=value"');
        expect(result, 'key=value');
      });

      test('handles unquoted value trimming', () {
        final result = parseValue('  unquoted  ');
        expect(result, 'unquoted');
      });

      test('returns null for empty unquoted value', () {
        final result = parseValue('   ');
        expect(result, isNull);
      });

      test('handles complex escaped sequences', () {
        final result = parseValue(r'"complex \"escaped\" \\sequence"',
            decodeEscapesInQuoted: true);
        expect(result, r'complex "escaped" \sequence');
      });

      test('handles unterminated quote with decodeEscapesInQuoted', () {
        final result = parseValue('"unterminated', decodeEscapesInQuoted: true);
        expect(result, '"unterminated');
      });
    });
  });
}
