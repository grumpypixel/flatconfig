import 'package:flatconfig/flatconfig_includes.dart';
import 'package:test/test.dart';

/// The two shipped defects that no other test file pins, named after what went
/// wrong rather than after the release that fixed it. The rest are covered
/// where they belong topically: quoting and backslashes in
/// `spec_conformance_test.dart`, the empty string in `round_trip_test.dart`,
/// cached views in `document_test.dart`, prefix guards in
/// `document_strip_prefix_test.dart`, and include path folding in
/// `includes_test.dart`.
///
/// Everything here asserts a thrown error or a returned value, never an
/// `assert`: a release build strips assertions, and one of these two defects
/// was a guard that existed only as one.

void main() {
  group('a number that is not finite is not a number', () {
    // The range accessors compared with <= and >=, which are false for NaN in
    // both directions, so NaN passed every range unchecked. Those accessors
    // are gone as of the accessor collapse, but the rejection is what keeps a
    // NaN out of a caller's own comparison too.
    for (final text in const ['NaN', 'Infinity', '-Infinity', '-NaN']) {
      test('$text does not read back as a double', () {
        final doc = FlatDocument.parse('x = $text\n');

        expect(doc.getDouble('x'), isNull);
        expect(doc.getDoubleOr('x', 1), 1);
        expect(() => doc.requireDouble('x'), throwsFormatException);
      });
    }

    test('a converter written by hand sees nothing to compare', () {
      final doc = FlatDocument.parse('x = NaN\n');

      expect(doc.getAs('x', (raw) => double.tryParse(raw)), isNaN);
      expect(doc.getDouble('x'), isNull);
    });

    test('a finite number still parses, at the edges too', () {
      expect(FlatDocument.parse('x = 1.5\n').getDouble('x'), 1.5);
      expect(FlatDocument.parse('x = -0.0\n').getDouble('x'), -0.0);
      expect(FlatDocument.parse('x = 1e308\n').getDouble('x'), 1e308);
    });
  });

  group('the guards on public input survive a release build', () {
    // These were assertions. A release build strips them and the bad value
    // went on to be used, so each one is now a check that throws.
    test('a comment prefix cannot span a line break', () {
      expect(
        () => FlatDocument.parse(
          'a = 1\n',
          options: const FlatParseOptions(commentPrefix: '#\n'),
        ),
        throwsArgumentError,
      );
    });

    test('a separator must be exactly one character', () {
      expect(() => splitRespectingQuotes('a,b', '::'), throwsArgumentError);
      expect(() => splitRespectingQuotes('a,b', ''), throwsArgumentError);
      expect(() => indexOfUnquoted('a,b', '::'), throwsArgumentError);
      expect(() => indexOfUnquoted('a,b', ''), throwsArgumentError);
    });

    test('a line terminator cannot be empty', () {
      // Computed, so the constructor's assert is not evaluated at compile
      // time. A debug build rejects it there; a release build has dropped the
      // assert and rejects it in the encoder instead. The defect was that
      // neither happened.
      final empty = String.fromCharCodes(const <int>[]);

      expect(
        () => FlatDocument.parse('a = 1\n').encodeToBytesWithWriteOptions(
          writeOptions: FlatStreamWriteOptions(lineTerminator: empty),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });

    test('a negative include depth is rejected where it is used', () {
      final negative = int.parse('-1');

      expect(
        () => parseWithIncludesSync(
          'a = 1\n',
          resolver: MemoryIncludeResolver(const {}),
          includeOptions: FlatIncludeOptions(maxIncludeDepth: negative),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });

    test('a key the format cannot represent never reaches a document', () {
      for (final key in const ['a=b', 'a"b', '#a', ' a', 'a ', '', 'a\nb']) {
        expect(
          () => FlatEntry(key, 'v'),
          throwsArgumentError,
          reason: 'key "$key" should have been rejected',
        );
      }
    });

    test('a value the format cannot represent does not either', () {
      expect(() => FlatEntry('a', 'one\ntwo'), throwsArgumentError);
    });
  });
}
