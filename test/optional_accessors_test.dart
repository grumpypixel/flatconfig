import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/flatconfig_accessors.dart';
import 'package:test/test.dart';

enum Mode { auto, off }

/// Tests for the accessors that moved out of core into
/// `package:flatconfig/flatconfig_accessors.dart`.
///
/// They follow the same three shapes as the core catalog, so these groups check
/// the shapes hold for each moved type rather than re-testing the shapes
/// themselves.

void main() {
  group('DateTime', () {
    final doc = FlatDocument.parse(
      'when = 2024-12-31T23:59:59Z\nbad = not-a-date',
    );
    final fallback = DateTime.utc(2000);

    test('an ISO-8601 value parses', () {
      expect(doc.getDateTime('when'), DateTime.utc(2024, 12, 31, 23, 59, 59));
    });

    test('a malformed value is null, falls back, or throws', () {
      expect(doc.getDateTime('bad'), isNull);
      expect(doc.getDateTimeOr('bad', fallback), fallback);
      expect(() => doc.requireDateTime('bad'), throwsFormatException);
    });

    test('an absent key behaves the same way', () {
      expect(doc.getDateTime('nope'), isNull);
      expect(doc.getDateTimeOr('nope', fallback), fallback);
      expect(() => doc.requireDateTime('nope'), throwsFormatException);
    });
  });

  group('Duration', () {
    final doc = FlatDocument.parse('''
bare = 150
ms = 150ms
s = 2.5s
m = 3m
h = 1h
d = 1d
bad = soon
''');

    test('a bare number is milliseconds', () {
      expect(doc.getDuration('bare'), const Duration(milliseconds: 150));
    });

    test('every unit suffix is understood', () {
      expect(doc.getDuration('ms'), const Duration(milliseconds: 150));
      expect(doc.getDuration('s'), const Duration(milliseconds: 2500));
      expect(doc.getDuration('m'), const Duration(minutes: 3));
      expect(doc.getDuration('h'), const Duration(hours: 1));
      expect(doc.getDuration('d'), const Duration(days: 1));
    });

    test('a malformed value is null, falls back, or throws', () {
      expect(doc.getDuration('bad'), isNull);
      expect(doc.getDurationOr('bad', Duration.zero), Duration.zero);
      expect(() => doc.requireDuration('bad'), throwsFormatException);
    });

    test('a non-finite number is not a duration', () {
      final d = FlatDocument.parse('t = NaN');
      expect(d.getDuration('t'), isNull);
    });
  });

  group('Uri', () {
    final doc = FlatDocument.parse('url = https://example.com/v1');
    final fallback = Uri.parse('https://fallback.test');

    test('a URI parses and the three shapes agree', () {
      expect(doc.getUri('url'), Uri.parse('https://example.com/v1'));
      expect(
        doc.getUriOr('url', fallback),
        Uri.parse('https://example.com/v1'),
      );
      expect(doc.requireUri('url'), Uri.parse('https://example.com/v1'));
    });

    test('an absent key is null, falls back, or throws', () {
      expect(doc.getUri('nope'), isNull);
      expect(doc.getUriOr('nope', fallback), fallback);
      expect(() => doc.requireUri('nope'), throwsFormatException);
    });
  });

  group('JSON', () {
    final doc = FlatDocument.parse(
      'obj = {"k": [1,2,3], "ok": true}\nbad = {not json',
    );

    test('a document decodes', () {
      expect(doc.getJson('obj'), {
        'k': [1, 2, 3],
        'ok': true,
      });
    });

    test('a malformed document is null, falls back, or throws', () {
      expect(doc.getJson('bad'), isNull);
      expect(doc.getJsonOr('bad', 'fb'), 'fb');
      expect(() => doc.requireJson('bad'), throwsFormatException);
    });
  });

  group('enum mapping', () {
    const mapping = {'auto': Mode.auto, 'off': Mode.off};
    final doc = FlatDocument.parse('mode = AUTO\nbad = sideways');

    test('matching ignores case by default', () {
      expect(doc.getEnum('mode', mapping), Mode.auto);
    });

    test('case sensitivity can be demanded', () {
      expect(doc.getEnum('mode', mapping, caseInsensitive: false), isNull);
    });

    test('an unmapped value is null, falls back, or throws', () {
      expect(doc.getEnum('bad', mapping), isNull);
      expect(doc.getEnumOr('bad', mapping, Mode.off), Mode.off);
      expect(() => doc.requireEnum('bad', mapping), throwsFormatException);
    });

    test('the failure message lists what was expected', () {
      expect(
        () => doc.requireEnum('bad', mapping),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('auto'), contains('off'), contains('sideways')),
          ),
        ),
      );
    });
  });
}
