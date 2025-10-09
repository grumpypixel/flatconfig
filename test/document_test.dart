// test/document_test.dart

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatDocument', () {
    test('preserves order of keys (first occurrence only)', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      expect(doc.keys, ['a', 'b']);
    });

    test('latest returns last value per key', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('a', '2'),
      ]);
      expect(doc['a'], '2');
    });

    test('valuesOf returns all values for a key', () {
      final doc = FlatDocument(const [
        FlatEntry('x', 'foo'),
        FlatEntry('x', 'bar'),
      ]);
      expect(doc.valuesOf('x'), ['foo', 'bar']);
    });

    test('supports null values (reset)', () {
      final doc = FlatDocument(const [
        FlatEntry('font-family', null),
      ]);
      expect(doc['font-family'], isNull);
      expect(doc.valuesOf('font-family'), [null]);
    });

    test('latest map reflects null if last value is null', () {
      final doc = FlatDocument(const [
        FlatEntry('x', 'one'),
        FlatEntry('x', null),
      ]);
      expect(doc['x'], isNull);
    });

    test('valuesOf returns nulls among values', () {
      final doc = FlatDocument(const [
        FlatEntry('k', 'v1'),
        FlatEntry('k', null),
        FlatEntry('k', 'v3'),
      ]);
      expect(doc.valuesOf('k'), ['v1', null, 'v3']);
    });

    test('empty document has no keys, no latest, empty valuesOf', () {
      final doc = FlatDocument.empty();
      expect(doc.keys, isEmpty);
      expect(doc.toMap(), isEmpty);
      expect(doc.valuesOf('missing'), isEmpty);
    });

    test('calling latest does not mutate entries order', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      final _ = doc.toMap; // trigger computation
      expect(doc.entries.map((e) => e.key).toList(), ['a', 'b', 'a']);
    });

    test('handles many entries (smoke test)', () {
      final entries = List.generate(
        10000,
        (i) => FlatEntry('k${i % 10}', '$i'),
      );
      final doc = FlatDocument(entries);
      expect(doc.keys.length, 10);
      expect(doc['k0'], isNotNull);
    });

    test('entries list is unmodifiable', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
      ]);
      expect(
        () => doc.entries.add(const FlatEntry('b', '2')),
        throwsUnsupportedError,
      );
    });

    test('valuesOf returns empty for missing key in non-empty doc', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
      ]);
      expect(doc.valuesOf('missing'), isEmpty);
    });

    test('firstValueOf returns first occurrence value', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      expect(doc.firstValueOf('a'), '1');
      expect(doc.firstValueOf('b'), '2');
      expect(doc.firstValueOf('missing'), isNull);
    });

    test('lastValueOf returns last occurrence value', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      expect(doc.lastValueOf('a'), '3');
      expect(doc.lastValueOf('b'), '2');
      expect(doc.lastValueOf('missing'), isNull);
    });

    test('whereKey returns all entries with matching key', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
        FlatEntry('c', '4'),
      ]);
      final entries = doc.whereKey('a').toList();
      expect(entries.length, 2);
      expect(entries[0].value, '1');
      expect(entries[1].value, '3');
      expect(doc.whereKey('missing').toList(), isEmpty);
    });

    test('whereKeys returns entries with keys in the set', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('c', '3'),
        FlatEntry('d', '4'),
      ]);
      final entries = doc.whereKeys(['a', 'c']).toList();
      expect(entries.length, 2);
      expect(entries.map((e) => e.key).toSet(), {'a', 'c'});
      expect(doc.whereKeys(['missing']).toList(), isEmpty);
    });

    test('whereValue returns entries with matching value', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('c', '1'),
        FlatEntry('d', null),
      ]);
      final entries = doc.whereValue('1').toList();
      expect(entries.length, 2);
      expect(entries.map((e) => e.key).toSet(), {'a', 'c'});

      final nullEntries = doc.whereValue(null).toList();
      expect(nullEntries.length, 1);
      expect(nullEntries[0].key, 'd');

      expect(doc.whereValue('missing').toList(), isEmpty);
    });

    test('getString returns latest value', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('a', '2'),
      ]);
      expect(doc.getString('a'), '2');
      expect(doc.getString('missing'), isNull);
    });

    test('toString shows entry count', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      expect(doc.toString(), 'FlatDocument(2 entries)');
      expect(FlatDocument.empty().toString(), 'FlatDocument(0 entries)');
    });

    test('iterator works correctly', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      final entries = doc.iterator;
      expect(entries.moveNext(), isTrue);
      expect(entries.current.key, 'a');
      expect(entries.moveNext(), isTrue);
      expect(entries.current.key, 'b');
      expect(entries.moveNext(), isFalse);
    });

    test('length returns entry count', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      expect(doc.length, 2);
      expect(FlatDocument.empty().length, 0);
    });

    test('isEmpty and isNotEmpty work correctly', () {
      final doc = FlatDocument(const [FlatEntry('a', '1')]);
      expect(doc.isEmpty, isFalse);
      expect(doc.isNotEmpty, isTrue);

      expect(FlatDocument.empty().isEmpty, isTrue);
      expect(FlatDocument.empty().isNotEmpty, isFalse);
    });

    test('toMap returns unmodifiable map', () {
      final doc = FlatDocument(const [FlatEntry('a', '1')]);
      expect(() => doc.toMap()['b'] = '2', throwsUnsupportedError);
    });

    test('toMap handles empty document', () {
      final doc = FlatDocument.empty();
      expect(doc.toMap(), isEmpty);
      expect(doc.toMap(), isA<Map<String, String?>>());
    });

    test('toMap handles null values', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', null),
        FlatEntry('c', '3'),
      ]);

      expect(doc['a'], '1');
      expect(doc['b'], isNull);
      expect(doc['c'], '3');
    });

    test('cache method precomputes toMap and valuesOf', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);

      // Cache both maps
      doc.cache(toMap: true, toValuesOf: true);

      // Verify toMap is cached
      expect(doc.toMap(), {'a': '3', 'b': '2'});
      expect(doc['a'], '3');

      // Verify valuesOf is cached
      expect(doc.valuesOf('a'), ['1', '3']);
      expect(doc.valuesOf('b'), ['2']);
    });

    test('cache method can cache only toMap', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);

      // Cache only toMap
      doc.cache(toMap: true, toValuesOf: false);

      // Verify toMap is cached
      expect(doc.toMap(), {'a': '1', 'b': '2'});

      // valuesOf should still work but not be cached
      expect(doc.valuesOf('a'), ['1']);
    });

    test('cache method can cache only valuesOf', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('a', '2'),
      ]);

      // Cache only valuesOf
      doc.cache(toMap: false, toValuesOf: true);

      // Verify valuesOf is cached
      expect(doc.valuesOf('a'), ['1', '2']);

      // toMap should still work but not be cached
      expect(doc.toMap(), {'a': '2'});
    });

    test('cache method with no parameters caches only toMap by default', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);

      // Cache with default parameters
      doc.cache();

      // Verify toMap is cached
      expect(doc.toMap(), {'a': '1', 'b': '2'});

      // valuesOf should not be cached
      expect(doc.valuesOf('a'), ['1']);
    });
  });

  group('FlatDocument helpers', () {
    test('getInt parses ints and returns null for invalid/missing', () {
      final doc = FlatDocument(const [
        FlatEntry('i1', '42'),
        FlatEntry('i2', 'x'),
      ]);
      expect(doc.getInt('i1'), 42);
      expect(doc.getInt('i2'), isNull);
      expect(doc.getInt('missing'), isNull);
    });

    test('getBool recognizes common forms and returns null when unknown', () {
      final doc = FlatDocument(const [
        FlatEntry('t1', 'true'),
        FlatEntry('t2', '1'),
        FlatEntry('t3', 'yes'),
        FlatEntry('t4', 'on'),
        FlatEntry('f1', 'false'),
        FlatEntry('f2', '0'),
        FlatEntry('f3', 'no'),
        FlatEntry('f4', 'off'),
        FlatEntry('u', 'maybe'),
      ]);

      expect(doc.getBool('t1'), isTrue);
      expect(doc.getBool('t2'), isTrue);
      expect(doc.getBool('t3'), isTrue);
      expect(doc.getBool('t4'), isTrue);
      expect(doc.getBool('f1'), isFalse);
      expect(doc.getBool('f2'), isFalse);
      expect(doc.getBool('f3'), isFalse);
      expect(doc.getBool('f4'), isFalse);
      expect(doc.getBool('u'), isNull);
      expect(doc.getBool('missing'), isNull);
    });

    test('getDouble parses doubles and returns null for invalid/missing', () {
      final doc = FlatDocument(const [
        FlatEntry('d1', '3.14'),
        FlatEntry('d2', '  2.5  '),
        FlatEntry('d3', 'x'),
      ]);
      expect(doc.getDouble('d1'), closeTo(3.14, 1e-9));
      expect(doc.getDouble('d2'), closeTo(2.5, 1e-9));
      expect(doc.getDouble('d3'), isNull);
      expect(doc.getDouble('missing'), isNull);
    });

    // document extension tests moved to test/document_extension_test.dart

    test('equality and hashCode reflect entries identity', () {
      final a = FlatDocument(const [FlatEntry('k', 'v')]);
      final b = FlatDocument(const [FlatEntry('k', 'v')]);
      final c = FlatDocument(const [FlatEntry('k', 'x')]);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });

    test('FlatEntry.toString includes key and value/null', () {
      const e1 = FlatEntry('k', 'v');
      const e2 = FlatEntry('n', null);
      expect(e1.toString(), contains('k'));
      expect(e1.toString(), contains('v'));
      expect(e2.toString(), contains('null'));
    });
  });
}
