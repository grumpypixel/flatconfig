import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

/// Tests for the single issue-reporting channel.
///
/// Lenient mode used to report exactly two problems through two typed
/// callbacks; the other three were skipped in silence. These pin that every
/// kind now arrives through `onIssue`, and that strict mode still throws the
/// matching exception for the same input.

void main() {
  List<FlatIssue> issuesOf(String source) {
    final collected = <FlatIssue>[];
    FlatDocument.parse(
      source,
      options: FlatParseOptions(onIssue: collected.add),
    );

    return collected;
  }

  group('every kind of problem reaches onIssue', () {
    test('a line without a separator', () {
      final issues = issuesOf('justakey\nk = v');
      expect(issues.single.kind, FlatIssueKind.missingEquals);
      expect(issues.single.line, 1);
      expect(issues.single.rawLine, 'justakey');
    });

    test('a line whose key is only whitespace', () {
      final issues = issuesOf('k = v\n = orphan');
      expect(issues.single.kind, FlatIssueKind.emptyKey);
      expect(issues.single.line, 2);
    });

    test('a key the encoder could not write back out', () {
      // This one was dropped in silence: no callback existed for it, so a
      // hand-edited file could lose a line without saying anything. A quote is
      // the reachable case; a leading '#' is taken as a comment first.
      final issues = issuesOf('good = 1\nbad"key = 2');
      expect(issues.single.kind, FlatIssueKind.invalidKey);
      expect(issues.single.line, 2);
      expect(issues.single.detail, isNotNull);
    });

    test('a value that opens a quote and never closes it', () {
      final issues = issuesOf('k = "unterminated');
      expect(issues.single.kind, FlatIssueKind.unterminatedQuote);
    });

    test('a quoted value followed by something else', () {
      final issues = issuesOf('k = "one" junk');
      expect(issues.single.kind, FlatIssueKind.trailingAfterQuote);
    });
  });

  group('the issue carries enough to point at the problem', () {
    test('line numbers are 1-based and count every source line', () {
      final issues = issuesOf('# comment\nfirst\nk = v\nsecond');
      expect(issues.map((i) => i.line), [2, 4]);
    });

    test('the raw line is untrimmed, as it appeared in the file', () {
      final issues = issuesOf('  spaced out  ');
      expect(issues.single.rawLine, '  spaced out  ');
    });

    test('the column points into the line, not to zero', () {
      final issues = issuesOf('k = "one" junk');
      expect(issues.single.column, greaterThan(1));
    });

    test('message describes the kind without repeating the position', () {
      final issues = issuesOf('justakey');
      expect(issues.single.message, contains('='));
      expect(issues.single.toString(), contains('line 1'));
    });

    test('two issues from the same place compare equal', () {
      const a = FlatIssue(
        kind: FlatIssueKind.emptyKey,
        line: 3,
        column: 1,
        rawLine: '= x',
      );
      const b = FlatIssue(
        kind: FlatIssueKind.emptyKey,
        line: 3,
        column: 1,
        rawLine: '= x',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('strict mode throws where lenient mode reports', () {
    const cases = {
      'justakey': MissingEqualsException,
      ' = orphan': EmptyKeyException,
      'bad"key = 2': InvalidKeyException,
      'k = "unterminated': UnterminatedQuoteException,
      'k = "one" junk': TrailingCharactersAfterQuoteException,
    };

    for (final entry in cases.entries) {
      test('${entry.value} for `${entry.key}`', () {
        // The same input yields one issue leniently and one exception strictly,
        // so a caller can develop with onIssue and ship with strict.
        expect(issuesOf(entry.key), hasLength(1));
        expect(
          () => FlatDocument.parse(
            entry.key,
            options: const FlatParseOptions(strict: true),
          ),
          throwsA(isA<FlatParseException>()),
        );
      });
    }
  });

  test('a handler that throws aborts the parse', () {
    // This is how you build a policy stricter than lenient but narrower than
    // strict: fail on one kind, tolerate the rest.
    expect(
      () => FlatDocument.parse(
        'ok = 1\nbad"key = 2\nalso_ok = 3',
        options: FlatParseOptions(
          onIssue: (i) {
            if (i.kind == FlatIssueKind.invalidKey) {
              throw FormatException(i.message, i.rawLine);
            }
          },
        ),
      ),
      throwsFormatException,
    );
  });

  test('without a handler, unparseable lines are skipped silently', () {
    final doc = FlatDocument.parse('ok = 1\njunk\nbad"key = 2\nfine = 3');
    expect(doc.keys, ['ok', 'fine']);
  });
}
