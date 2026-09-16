import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

/// Tests for the core accessor catalog.
///
/// Every supported type offers exactly three shapes -- `getX`, `getXOr`,
/// `requireX` -- so these groups are organised by shape rather than by type:
/// what matters is that no type is an exception to the rule.

void main() {
  FlatDocument docOf(Map<String, String?> m) =>
      FlatDocument([for (final e in m.entries) FlatEntry(e.key, e.value)]);

  group('getX returns null rather than guessing', () {
    final doc = docOf({
      'str': 'text',
      'int': '42',
      'double': '0.5',
      'bool': 'yes',
      'list': 'a, b, c',
      'junk': 'nonsense',
      'reset': null,
    });

    test('a parseable value comes back typed', () {
      expect(doc.getString('str'), 'text');
      expect(doc.getInt('int'), 42);
      expect(doc.getDouble('double'), 0.5);
      expect(doc.getBool('bool'), isTrue);
      expect(doc.getList('list'), ['a', 'b', 'c']);
    });

    test('an unparseable value is null, not a thrown exception', () {
      expect(doc.getInt('junk'), isNull);
      expect(doc.getDouble('junk'), isNull);
      expect(doc.getBool('junk'), isNull);
    });

    test('an absent key is null for every type', () {
      expect(doc.getString('nope'), isNull);
      expect(doc.getInt('nope'), isNull);
      expect(doc.getDouble('nope'), isNull);
      expect(doc.getBool('nope'), isNull);
      expect(doc.getList('nope'), isNull);
    });

    test('a reset key reads like an absent one', () {
      expect(doc.getString('reset'), isNull);
      expect(doc.getInt('reset'), isNull);
      expect(doc.getList('reset'), isNull);
    });
  });

  group('getXOr substitutes the fallback in exactly those cases', () {
    final doc = docOf({'int': '7', 'junk': 'x', 'reset': null});

    test('a usable value wins over the fallback', () {
      expect(doc.getIntOr('int', 99), 7);
    });

    test('absent, reset and unparseable all fall back', () {
      for (final key in ['nope', 'reset', 'junk']) {
        expect(doc.getIntOr(key, 99), 99, reason: key);
        expect(doc.getDoubleOr(key, 9.9), 9.9, reason: key);
        expect(doc.getBoolOr(key, true), isTrue, reason: key);
        expect(doc.getStringOr(key, 'fb'), key == 'junk' ? 'x' : 'fb');
      }
    });

    test('getListOr replaces the old getListOrEmpty', () {
      expect(doc.getListOr('nope', const []), isEmpty);
      expect(doc.getListOr('nope', const ['a']), ['a']);
    });
  });

  group('requireX throws, and says which key and value', () {
    final doc = docOf({'int': '42', 'junk': 'x', 'reset': null});

    test('a usable value is returned unchanged', () {
      expect(doc.requireString('int'), '42');
      expect(doc.requireInt('int'), 42);
      expect(doc.requireDouble('int'), 42.0);
      expect(doc.requireList('int'), ['42']);
    });

    test('every type throws on an absent key', () {
      expect(() => doc.requireString('nope'), throwsFormatException);
      expect(() => doc.requireInt('nope'), throwsFormatException);
      expect(() => doc.requireDouble('nope'), throwsFormatException);
      expect(() => doc.requireBool('nope'), throwsFormatException);
      expect(() => doc.requireList('nope'), throwsFormatException);
    });

    test('every type throws on an unparseable value', () {
      expect(() => doc.requireInt('junk'), throwsFormatException);
      expect(() => doc.requireDouble('junk'), throwsFormatException);
      expect(() => doc.requireBool('junk'), throwsFormatException);
    });

    test('the message names the key and the offending value', () {
      expect(
        () => doc.requireInt('junk'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('junk'), contains("got: 'x'")),
          ),
        ),
      );
    });
  });

  group('getList splitting', () {
    test('items are trimmed and empties dropped by default', () {
      final doc = docOf({'k': 'a, b , , c'});
      expect(doc.getList('k'), ['a', 'b', 'c']);
    });

    test('both defaults can be turned off', () {
      final doc = docOf({'k': 'a, b , , c'});
      expect(doc.getList('k', trimItems: false, skipEmpty: false), [
        'a',
        ' b ',
        ' ',
        ' c',
      ]);
    });

    test('a custom separator is honoured everywhere in the family', () {
      final doc = docOf({'k': 'a|b'});
      expect(doc.getList('k', separator: '|'), ['a', 'b']);
      expect(doc.getListOr('k', const [], separator: '|'), ['a', 'b']);
      expect(doc.requireList('k', separator: '|'), ['a', 'b']);
    });

    test('an explicitly empty value is an empty list, not null', () {
      final doc = FlatDocument.parse('k = ""');
      expect(doc.getList('k'), isEmpty);
      expect(doc.getList('k'), isNotNull);
    });
  });

  group('getAs is the escape hatch for every other type', () {
    final doc = docOf({'n': ' 42 ', 'junk': 'x', 'empty': ''});

    test('the value is trimmed before conversion unless asked otherwise', () {
      expect(doc.getAs('n', int.parse), 42);
      expect(doc.getAs('n', (v) => v, trim: false), ' 42 ');
    });

    test('a converter that throws means null, not a crash', () {
      expect(doc.getAs('junk', int.parse), isNull);
      expect(doc.getAsOr('junk', int.parse, -1), -1);
      expect(() => doc.requireAs('junk', int.parse), throwsFormatException);
    });

    test('an empty value is skipped unless ignoreEmpty is off', () {
      expect(doc.getAs('empty', (v) => v), isNull);
      expect(doc.getAs('empty', (v) => v, ignoreEmpty: false), '');
    });

    test('an Error from the converter is a bug and propagates', () {
      // A config file cannot cause this; only a wrong converter can, and
      // swallowing it would report the user's data as the problem.
      expect(
        () => doc.getAs<int>('n', (_) => throw ArgumentError('bad converter')),
        throwsArgumentError,
      );
      expect(
        () => doc.getAsOr<int>('n', (_) => throw StateError('bug'), 0),
        throwsStateError,
      );
    });
  });

  group('allAs converts every occurrence of a key', () {
    final doc = FlatDocument.parse('p = 1\np = 2\nreset =\nbad = 1\nbad = x');

    test('values come back in file order', () {
      expect(doc.allAs('p', int.parse), [1, 2]);
    });

    test('an absent key is null, which an empty list cannot express', () {
      expect(doc.allAs('nope', int.parse), isNull);
    });

    test('a key that is only a reset is present but carries no values', () {
      expect(doc.allAs('reset', int.parse), isEmpty);
      expect(doc.allAs('reset', int.parse), isNotNull);
    });

    test('one bad value throws instead of shortening the list', () {
      // requireAllAs used to return [] for a missing key and getAllAs used to
      // drop bad items, so a typo turned into a silently shorter list.
      expect(() => doc.allAs('bad', int.parse), throwsFormatException);
    });
  });

  group('FlatDocument Core Accessors', () {
    test('toMap() should include only last value per key', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'first'),
        FlatEntry('key2', 'second'),
        FlatEntry('key1', 'last'), // duplicate key
        FlatEntry('key3', null),
      ]);

      final map = doc.toMap();
      expect(map['key1'], 'last'); // should be the last value
      expect(map['key2'], 'second');
      expect(map['key3'], null);
      expect(map.length, 3);
    });

    test('toMap() should return immutable map', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'value1'),
        FlatEntry('key2', 'value2'),
      ]);

      final map = doc.toMap();
      expect(() => map['key3'] = 'value3', throwsUnsupportedError);
      expect(() => map.remove('key1'), throwsUnsupportedError);
      expect(() => map.clear(), throwsUnsupportedError);
    });

    test('toMap() should not modify after creation', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'value1'),
        FlatEntry('key2', 'value2'),
      ]);

      final map1 = doc.toMap();
      final map2 = doc.toMap();

      // Should return the same cached instance
      expect(identical(map1, map2), isTrue);

      // Modifying the document should not affect the cached map
      FlatDocument([...doc.entries, FlatEntry('key3', 'value3')]);
      expect(map1.containsKey('key3'), isFalse);
    });

    test('allValues(key) should return all values for key in order', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'first'),
        FlatEntry('key2', 'only'),
        FlatEntry('key1', 'second'),
        FlatEntry('key1', null),
        FlatEntry('key1', 'last'),
      ]);

      final values = doc.allValues('key1');
      expect(values, ['first', 'second', null, 'last']);
      expect(values.length, 4);
    });

    test('allValues(key) should return empty list if key not found', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'value1'),
        FlatEntry('key2', 'value2'),
      ]);

      final values = doc.allValues('missing');
      expect(values, isEmpty);
      expect(values, isA<List<String?>>());
    });

    test('allValues(key) should be immutable', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'value1'),
        FlatEntry('key1', 'value2'),
      ]);

      final values = doc.allValues('key1');
      expect(() => values.add('value3'), throwsUnsupportedError);
      expect(() => values.removeAt(0), throwsUnsupportedError);
      expect(() => values.clear(), throwsUnsupportedError);
    });

    test('allValues(key).first is the first occurrence', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'first'),
        FlatEntry('key2', 'only'),
        FlatEntry('key1', 'second'),
        FlatEntry('key1', 'last'),
      ]);

      expect(doc.allValues('key1').first, 'first');
      expect(doc.allValues('key2').first, 'only');
    });

    test('allValues(key) is empty if the key is not found', () {
      final doc = FlatDocument([FlatEntry('key1', 'value1')]);

      expect(doc.allValues('missing'), isEmpty);
    });

    test(
      'lastValueOf(key) should return most recent value (alias to this[key])',
      () {
        final doc = FlatDocument([
          FlatEntry('key1', 'first'),
          FlatEntry('key2', 'only'),
          FlatEntry('key1', 'second'),
          FlatEntry('key1', 'last'),
        ]);

        expect(doc['key1'], 'last');
        expect(doc['key2'], 'only');
        expect(doc['key1'], doc['key1']); // should be equivalent
      },
    );

    test('lastValueOf(key) should return null if missing', () {
      final doc = FlatDocument([FlatEntry('key1', 'value1')]);

      expect(doc['missing'], isNull);
    });

    test('has() should be true if key exists (even with null)', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'value1'),
        FlatEntry('key2', null),
        FlatEntry('key3', ''),
      ]);

      expect(doc.containsKey('key1'), isTrue);
      expect(doc.containsKey('key2'), isTrue); // should be true even with null
      expect(doc.containsKey('key3'), isTrue);
      expect(doc.containsKey('missing'), isFalse);
    });

    test('operator [] is null exactly when the value is null', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'value1'),
        FlatEntry('key2', null),
        FlatEntry('key3', ''),
      ]);

      expect(doc['key1'], isNotNull);
      expect(doc['key2'], isNull); // null value
      expect(doc['key3'], isNotNull); // empty string is not null
      expect(doc['missing'], isNull);
    });

    test('getInt() should parse valid numeric values correctly', () {
      final doc = FlatDocument([
        FlatEntry('positive', '42'),
        FlatEntry('negative', '-17'),
        FlatEntry('zero', '0'),
        FlatEntry('large', '2147483647'),
      ]);

      expect(doc.getInt('positive'), 42);
      expect(doc.getInt('negative'), -17);
      expect(doc.getInt('zero'), 0);
      expect(doc.getInt('large'), 2147483647);
    });

    test('getInt() should return null for invalid or missing keys', () {
      final doc = FlatDocument([
        FlatEntry('invalid', 'not-a-number'),
        FlatEntry('float', '3.14'),
        FlatEntry('empty', ''),
        FlatEntry('null', null),
      ]);

      expect(doc.getInt('invalid'), isNull);
      expect(doc.getInt('float'), isNull);
      expect(doc.getInt('empty'), isNull);
      expect(doc.getInt('null'), isNull);
      expect(doc.getInt('missing'), isNull);
    });

    test('getDouble() should parse valid numeric values correctly', () {
      final doc = FlatDocument([
        FlatEntry('positive', '42.5'),
        FlatEntry('negative', '-17.25'),
        FlatEntry('zero', '0.0'),
        FlatEntry('integer', '100'),
        FlatEntry('scientific', '1.23e-4'),
      ]);

      expect(doc.getDouble('positive'), closeTo(42.5, 1e-9));
      expect(doc.getDouble('negative'), closeTo(-17.25, 1e-9));
      expect(doc.getDouble('zero'), closeTo(0.0, 1e-9));
      expect(doc.getDouble('integer'), closeTo(100.0, 1e-9));
      expect(doc.getDouble('scientific'), closeTo(1.23e-4, 1e-9));
    });

    test('getDouble() should return null for invalid or missing keys', () {
      final doc = FlatDocument([
        FlatEntry('invalid', 'not-a-number'),
        FlatEntry('empty', ''),
        FlatEntry('null', null),
      ]);

      expect(doc.getDouble('invalid'), isNull);
      expect(doc.getDouble('empty'), isNull);
      expect(doc.getDouble('null'), isNull);
      expect(doc.getDouble('missing'), isNull);
    });

    test('getBool() should handle boolean strings correctly', () {
      final doc = FlatDocument([
        FlatEntry('true1', 'true'),
        FlatEntry('true2', 'TRUE'),
        FlatEntry('true3', '1'),
        FlatEntry('true4', 'yes'),
        FlatEntry('true5', 'YES'),
        FlatEntry('true6', 'on'),
        FlatEntry('true7', 'ON'),
        FlatEntry('false1', 'false'),
        FlatEntry('false2', 'FALSE'),
        FlatEntry('false3', '0'),
        FlatEntry('false4', 'no'),
        FlatEntry('false5', 'NO'),
        FlatEntry('false6', 'off'),
        FlatEntry('false7', 'OFF'),
      ]);

      // True values
      expect(doc.getBool('true1'), isTrue);
      expect(doc.getBool('true2'), isTrue);
      expect(doc.getBool('true3'), isTrue);
      expect(doc.getBool('true4'), isTrue);
      expect(doc.getBool('true5'), isTrue);
      expect(doc.getBool('true6'), isTrue);
      expect(doc.getBool('true7'), isTrue);

      // False values
      expect(doc.getBool('false1'), isFalse);
      expect(doc.getBool('false2'), isFalse);
      expect(doc.getBool('false3'), isFalse);
      expect(doc.getBool('false4'), isFalse);
      expect(doc.getBool('false5'), isFalse);
      expect(doc.getBool('false6'), isFalse);
      expect(doc.getBool('false7'), isFalse);
    });

    test('getBool() should return null for invalid or missing keys', () {
      final doc = FlatDocument([
        FlatEntry('invalid1', 'maybe'),
        FlatEntry('invalid2', '2'),
        FlatEntry('invalid3', 'enabled'),
        FlatEntry('empty', ''),
        FlatEntry('null', null),
      ]);

      expect(doc.getBool('invalid1'), isNull);
      expect(doc.getBool('invalid2'), isNull);
      expect(doc.getBool('invalid3'), isNull);
      expect(doc.getBool('empty'), isNull);
      expect(doc.getBool('null'), isNull);
      expect(doc.getBool('missing'), isNull);
    });

    test('getString() should return string values correctly', () {
      final doc = FlatDocument([
        FlatEntry('normal', 'hello world'),
        FlatEntry('empty', ''),
        FlatEntry('null', null),
        FlatEntry('special', 'special chars: !@#\$%^&*()'),
      ]);

      expect(doc.getString('normal'), 'hello world');
      expect(doc.getString('empty'), '');
      expect(doc.getString('null'), isNull);
      expect(doc.getString('special'), 'special chars: !@#\$%^&*()');
      expect(doc.getString('missing'), isNull);
    });

    test('getString() should be equivalent to this[key]', () {
      final doc = FlatDocument([
        FlatEntry('key1', 'value1'),
        FlatEntry('key2', null),
        FlatEntry('key3', ''),
      ]);

      expect(doc.getString('key1'), doc['key1']);
      expect(doc.getString('key2'), doc['key2']);
      expect(doc.getString('key3'), doc['key3']);
      expect(doc.getString('missing'), doc['missing']);
    });

    test('requireAs tells an absent key from an empty value', () {
      final doc = FlatDocument([FlatEntry('empty', ''), FlatEntry('set', 'x')]);

      expect(
        () => doc.requireAs('missing', int.parse),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Missing value'),
          ),
        ),
      );
      expect(
        () => doc.requireAs('empty', int.parse),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Empty value'),
          ),
        ),
      );
      expect(
        doc.requireAs('empty', (raw) => raw.length, ignoreEmpty: false),
        0,
        reason: 'an empty value is a value when ignoreEmpty is off',
      );
    });
  });
}
