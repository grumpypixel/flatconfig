import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

/// Regression tests for the rules SPEC.md fixes, one group per section.
///
/// These pin the behaviour the format guarantees. The round-trip property test
/// proves encode and parse are inverse; this file proves they are inverse
/// *around the rules the spec actually states*, including the malformed inputs
/// a property test never generates.

void main() {
  group('SPEC 3 — a key must survive being written out and read back', () {
    const rejected = {
      '': 'must not be empty',
      '  ': 'must not have leading or trailing whitespace',
      ' a': 'must not have leading or trailing whitespace',
      'a ': 'must not have leading or trailing whitespace',
      'a=b': "must not contain '='",
      'a"b': 'must not contain a double quote',
      'a\nb': 'must not contain a line break',
      '#x': "must not begin with '#'",
    };

    test('a document cannot be built from one', () {
      rejected.forEach((key, reason) {
        expect(
          () => FlatDocument([FlatEntry(key, 'v')]),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(reason),
            ),
          ),
          reason: 'key "$key"',
        );
      });
    });

    test('the two that used to be lost silently are now impossible', () {
      // '#x = v' read back as a comment, losing the entry without a trace;
      // ' a  = v' read back with the padding gone.
      expect(() => FlatDocument.single('#x', value: 'v'), throwsArgumentError);
      expect(() => FlatDocument.single(' a ', value: 'v'), throwsArgumentError);
    });

    test('the parser skips such a line in lax mode', () {
      final doc = FlatConfig.parse('"a b" = v\ngood = 1');
      expect(doc.keys, ['good']);
    });

    test('the parser reports it in strict mode', () {
      expect(
        () => FlatConfig.parse(
          '"a b" = v',
          options: const FlatParseOptions(strict: true),
        ),
        throwsA(
          isA<InvalidKeyException>()
              .having((e) => e.key, 'key', '"a b"')
              .having((e) => e.reason, 'reason', contains('double quote')),
        ),
      );
    });

    test('validity does not depend on the configured comment prefix', () {
      // Otherwise a file written under one prefix loses entries under another.
      final doc = FlatConfig.parse(
        '#key = zero\nx = 1',
        options: const FlatParseOptions(commentPrefix: ';'),
      );
      expect(doc.keys, ['x']);
    });

    test('keys are case-sensitive', () {
      final doc = FlatConfig.parse('Theme = a\ntheme = b');
      expect(doc['Theme'], 'a');
      expect(doc['theme'], 'b');
    });
  });

  group('SPEC 5.1 — a quoted value closes at its first valid closer', () {
    test('lax: a second quoted run makes the token literal', () {
      // Closing at the last quote instead would silently yield
      // `one" junk "two`, which no one wrote and no one can detect.
      expect(FlatConfig.parse('a = "one" junk "two"')['a'], '"one" junk "two"');
    });

    test('strict: trailing content after the closer is an error', () {
      expect(
        () => FlatConfig.parse(
          'a = "one" junk "two"',
          options: const FlatParseOptions(strict: true),
        ),
        throwsA(isA<TrailingCharactersAfterQuoteException>()),
      );
    });

    test('only whitespace may follow the closer', () {
      expect(FlatConfig.parse('a = "one"   ')['a'], 'one');
      expect(
        () => FlatConfig.parse(
          'a = "one"x',
          options: const FlatParseOptions(strict: true),
        ),
        throwsA(isA<TrailingCharactersAfterQuoteException>()),
      );
    });

    test('an unterminated quote is malformed', () {
      expect(FlatConfig.parse('a = "open')['a'], '"open');
      expect(
        () => FlatConfig.parse(
          'a = "open',
          options: const FlatParseOptions(strict: true),
        ),
        throwsA(isA<UnterminatedQuoteException>()),
      );
    });

    test('an escaped quote does not close the value', () {
      expect(FlatConfig.parse(r'a = "say \"hi\" now"')['a'], 'say "hi" now');
    });
  });

  group('SPEC 5.2 — escapes', () {
    test('decoding is on by default', () {
      expect(FlatConfig.parse(r'a = "q\"q"')['a'], 'q"q');
      expect(FlatConfig.parse(r'a = "b\\c"')['a'], r'b\c');
    });

    test('every other backslash stays literal', () {
      // There is no \t escape, so Windows paths survive without doubling.
      expect(FlatConfig.parse(r'a = "C:\temp\x"')['a'], r'C:\temp\x');
    });

    test('unquoted values are never escape-processed', () {
      expect(FlatConfig.parse(r'a = C:\temp\x')['a'], r'C:\temp\x');
    });

    test('the inline grammar preserves them too', () {
      // splitRespectingQuotes used to consume every backslash as an escape
      // marker without copying it, so this returned win -> 'C:tempx'.
      final doc = FlatConfig.parse(r'paths = win=C:\temp\x,unix=/tmp');
      final paths = doc.getDocument('paths');
      expect(paths['win'], r'C:\temp\x');
      expect(paths['unix'], '/tmp');
    });

    test('a regex survives the inline grammar', () {
      final doc = FlatConfig.parse(r'rules = digits=\d+,word=\w+');
      final rules = doc.getDocument('rules');
      expect(rules['digits'], r'\d+');
      expect(rules['word'], r'\w+');
    });

    test('a trailing backslash survives', () {
      final doc = FlatConfig.parse(r'paths = dir=C:\temp\,other=x');
      expect(doc.getDocument('paths')['dir'], r'C:\temp\');
    });
  });

  group('SPEC 6 — absent, reset and empty string are three states', () {
    final doc = FlatConfig.parse('reset =\nempty = ""\nvalue = x');

    test('parsing keeps them apart', () {
      expect(doc.containsKey('absent'), isFalse);
      expect(doc['reset'], isNull);
      expect(doc['empty'], '');
      expect(doc['value'], 'x');
    });

    test('encoding keeps them apart', () {
      expect(doc.encode(), 'reset = \nempty = ""\nvalue = x\n');
    });
  });

  group('SPEC 7 — the encoder is the inverse of the parser', () {
    test('an empty string is quoted, a reset is not', () {
      final doc = FlatDocument(const [
        FlatEntry('empty', ''),
        FlatEntry('reset', null),
      ]);
      expect(doc.encode(), 'empty = ""\nreset = \n');
    });

    test('escaping is on by default', () {
      expect(
        FlatDocument(const [FlatEntry('k', r'say "hi" \ ok')]).encode(),
        'k = '
        r'"say \"hi\" \\ ok"'
        '\n',
      );
    });

    test('a value that is only whitespace keeps it', () {
      expect(
        FlatDocument(const [FlatEntry('k', '   ')]).encode(),
        'k = "   "\n',
      );
    });

    test('a value starting with the comment prefix is quoted', () {
      expect(FlatDocument(const [FlatEntry('k', '#x')]).encode(), 'k = "#x"\n');
    });

    test('a value containing a line break is rejected', () {
      // Quoting cannot rescue it: the format is line-based, so 'x\ny' was
      // written as two physical lines and read back as x -> '"x'.
      for (final bad in ['x\ny', 'x\r\ny', 'x\ry']) {
        expect(
          () => FlatDocument([FlatEntry('k', bad)]),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('must not contain a line break'),
            ),
          ),
        );
      }
    });

    test('null is a valid value, being the explicit reset', () {
      expect(FlatDocument(const [FlatEntry('k', null)]).encode(), 'k = \n');
    });

    test('a non-empty document always ends with the terminator', () {
      expect(
        FlatDocument(const [FlatEntry('k', 'v')]).encode(),
        endsWith('\n'),
      );
      expect(FlatDocument.empty().encode(), '');
    });
  });
}
