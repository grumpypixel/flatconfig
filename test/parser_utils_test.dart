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
        throwsA(
          isA<FlatParseException>().having(
            (e) => e.kind,
            'kind',
            FlatIssueKind.unterminatedQuote,
          ),
        ),
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
          throwsA(
            isA<FlatParseException>().having(
              (e) => e.kind,
              'kind',
              FlatIssueKind.trailingAfterQuote,
            ),
          ),
        );
      },
    );

    test('parseValue in lax mode handles unterminated quotes', () {
      final result = parseValue('"unterminated');
      expect(result, '"unterminated');
    });

    test('parseValue in lax mode handles trailing characters after quote', () {
      final result = parseValue('"value" extra');
      expect(result, '"value" extra');
    });

    test(
      'unescapeQuotesAndBackslashes handles escaped quotes and backslashes',
      () {
        expect(
          unescapeQuotesAndBackslashes(r'He said: \"hello\" \\ o/'),
          r'He said: "hello" \ o/',
        );
        expect(unescapeQuotesAndBackslashes(r'no escapes'), 'no escapes');
        expect(unescapeQuotesAndBackslashes(r'\\'), r'\');
        expect(unescapeQuotesAndBackslashes(r'\"'), '"');
      },
    );

    test('isUnescapedQuoteAt correctly identifies unescaped quotes', () {
      expect(isUnescapedQuoteAt('"hello"', 0), isTrue);
      expect(isUnescapedQuoteAt('"hello"', 6), isTrue);
      expect(isUnescapedQuoteAt(r'\"hello\"', 0), isFalse);
      expect(
        isUnescapedQuoteAt(r'\"hello\"', 1),
        isFalse,
      ); // escaped by backslash at 0
      expect(isUnescapedQuoteAt(r'\\"hello"', 1), isFalse);
      expect(
        isUnescapedQuoteAt(r'\\"hello"', 2),
        isTrue,
      ); // even number of backslashes
      expect(isUnescapedQuoteAt('no quotes', 0), isFalse);
      expect(isUnescapedQuoteAt('', 0), isFalse);
    });

    test(
      'firstUnescapedQuote finds the first unescaped quote at or after from',
      () {
        expect(firstUnescapedQuote('"hello"', 1), 6);
        expect(firstUnescapedQuote(r'\"hello\"', 0), -1); // all quotes escaped
        expect(
          firstUnescapedQuote(r'\\"hello"', 0),
          2,
        ); // the backslash is escaped
        expect(firstUnescapedQuote('no quotes', 0), -1);
        expect(firstUnescapedQuote(r'\"', 0), -1);
        expect(firstUnescapedQuote('', 0), -1);
        expect(firstUnescapedQuote('"', 0), 0);
        // The closer is the first one, not the last (SPEC.md 5.1).
        expect(firstUnescapedQuote('"one" junk "two"', 1), 4);
      },
    );

    test('normalizeLineEndings handles various line ending scenarios', () {
      // Test with trailing newline
      expect(
        normalizeLineEndings(
          'line1\nline2\n',
          lineTerminator: '\r\n',
          ensureTrailingNewline: false,
        ),
        'line1\r\nline2\r\n',
      );

      // Test without trailing newline
      expect(
        normalizeLineEndings(
          'line1\nline2',
          lineTerminator: '\r\n',
          ensureTrailingNewline: false,
        ),
        'line1\r\nline2',
      );

      // Test ensureTrailingNewline
      expect(
        normalizeLineEndings(
          'line1\nline2',
          lineTerminator: '\n',
          ensureTrailingNewline: true,
        ),
        'line1\nline2\n',
      );

      // Test CRLF input
      expect(
        normalizeLineEndings(
          'line1\r\nline2\r\n',
          lineTerminator: '\n',
          ensureTrailingNewline: false,
        ),
        'line1\nline2\n',
      );

      // Test CR input
      expect(
        normalizeLineEndings(
          'line1\rline2\r',
          lineTerminator: '\n',
          ensureTrailingNewline: false,
        ),
        'line1\nline2\n',
      );
    });

    test('normalizeLineEndings with empty lineTerminator throws', () {
      expect(
        () => normalizeLineEndings(
          'test',
          lineTerminator: '',
          ensureTrailingNewline: false,
        ),
        throwsA(isA<ArgumentError>()),
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

      test('an escaped quote does not end the quoted run', () {
        // The token is passed through verbatim; decoding is parseValue's job.
        final result = splitRespectingQuotes(r'a="x\"y",b', ',');
        expect(result, [r'a="x\"y"', 'b']);
      });

      test('backslashes are preserved, not consumed', () {
        final result = splitRespectingQuotes(r'a="x\\y",b', ',');
        expect(result, [r'a="x\\y"', 'b']);
      });

      test('an unquoted Windows path keeps every separator it has', () {
        // This used to come back as 'win=C:tempx'.
        final result = splitRespectingQuotes(r'win=C:\temp\x,unix=/tmp', ',');
        expect(result, [r'win=C:\temp\x', 'unix=/tmp']);
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

      test('throws for a multi-character separator', () {
        expect(
          () => splitRespectingQuotes('a,b,c', '::'),
          throwsA(isA<ArgumentError>()),
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

      test('throws for a multi-character search string', () {
        expect(
          () => indexOfUnquoted('abc', '::'),
          throwsA(isA<ArgumentError>()),
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
        final result = parseValue(
          r'"complex \"escaped\" \\sequence"',
          decodeEscapesInQuoted: true,
        );
        expect(result, r'complex "escaped" \sequence');
      });

      test('handles unterminated quote with decodeEscapesInQuoted', () {
        final result = parseValue('"unterminated', decodeEscapesInQuoted: true);
        expect(result, '"unterminated');
      });
    });

    group('the reported column points at the character in the raw line', () {
      // Both modes report a position, and asserting only the kind left the
      // number itself unchecked. It is built from three parts — the offset of
      // the value within the line, the whitespace the trim removed, and the
      // step from a zero-based index to a one-based column — and getting any
      // of their signs wrong still produces a plausible-looking column.
      //
      // `  key = "open`: the value starts at offset 8, its quote sits two
      // characters further in, and columns count from one.
      const rawLine = '  key = "open';
      const rawValue = '  "open';
      const columnOffset = 6;
      const quoteColumn = 9;

      test('strict mode names the quote that was never closed', () {
        expect(
          () => parseValue(
            rawValue,
            strict: true,
            lineNumber: 3,
            rawLine: rawLine,
            columnOffset: columnOffset,
          ),
          throwsA(
            isA<FlatParseException>()
                .having((e) => e.issue.column, 'column', quoteColumn)
                .having((e) => e.lineNumber, 'line', 3),
          ),
        );
      });

      test('lenient mode names the same character', () {
        final issues = <FlatIssue>[];

        parseValue(
          rawValue,
          lineNumber: 3,
          rawLine: rawLine,
          columnOffset: columnOffset,
          onIssue: issues.add,
        );

        expect(issues.single.column, quoteColumn);
        expect(rawLine[quoteColumn - 1], Constants.quote);
      });
    });

    group('a token is unquoted only when both ends are quotes', () {
      test('a token quoted on one side only is returned unchanged', () {
        expect(unquoteToken('"open'), '"open');
        expect(unquoteToken('close"'), 'close"');
      });

      test('a lone quote is not a wrapped token', () {
        expect(unquoteToken('"'), '"');
      });

      test('a wrapped token loses exactly one layer', () {
        expect(unquoteToken('"inner"'), 'inner');
      });
    });

    test('a value ending in a lone backslash keeps it', () {
      // The escape decoder looks one character ahead. Reaching the last
      // backslash of a value with that lookahead unguarded reads past the end
      // of the string, and only a trailing backslash gets there.
      expect(unescapeQuotesAndBackslashes('\\"x\\'), '"x\\');
    });

    test('isUnescapedQuoteAt refuses an index past the end', () {
      expect(isUnescapedQuoteAt('"abc"', 5), isFalse);
      expect(isUnescapedQuoteAt('"abc"', 99), isFalse);
    });

    test('isWhitespace counts both line break characters', () {
      // They cannot reach a split line, which is why nothing noticed that they
      // were still expected to trim. Callers that hand over unsplit text rely
      // on it.
      expect(isWhitespace(Constants.newlineCharCode), isTrue);
      expect(isWhitespace(Constants.carriageReturnCharCode), isTrue);
      expect(isWhitespace(Constants.blankCharCode), isTrue);
      expect(isWhitespace(Constants.tabCharCode), isTrue);
      expect(isWhitespace('x'.codeUnitAt(0)), isFalse);
    });
  });
}
