import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatDocument Core Behavior', () {
    test('preserves order of keys (first occurrence only)', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      expect(doc.keys, ['a', 'b']);
    });

    test('indexer returns last value per key', () {
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

    test('indexer reflects null if last value is null', () {
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

    test('calling toMap does not mutate entries order', () {
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

    test('getString returns last value', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('a', '2'),
      ]);
      expect(doc.getString('a'), '2');
      expect(doc.getString('missing'), isNull);
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
  });

  group('FlatDocument Utility', () {
    test('cache() should populate expando caches for toMap() and/or valuesOf',
        () {
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

    test('cache() should not throw on empty document', () {
      final doc = FlatDocument.empty();
      expect(() => doc.cache(), returnsNormally);
      expect(() => doc.cache(toMap: true, toValuesOf: true), returnsNormally);
    });

    test('cache() can cache only toMap', () {
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

    test('cache() can cache only valuesOf', () {
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

    test('cache() with no parameters caches only toMap by default', () {
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

    test('whereKey() should return correct filtered subsets', () {
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

    test('whereKey() should preserve original order', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
        FlatEntry('c', '4'),
        FlatEntry('a', '5'),
      ]);
      final entries = doc.whereKey('a').toList();
      expect(entries.map((e) => e.value).toList(), ['1', '3', '5']);
    });

    test('whereKeys() should return correct filtered subsets', () {
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

    test('whereKeys() should preserve original order', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('c', '3'),
        FlatEntry('a', '4'),
        FlatEntry('d', '5'),
      ]);
      final entries = doc.whereKeys(['a', 'c']).toList();
      expect(entries.map((e) => e.key).toList(), ['a', 'c', 'a']);
    });

    test('whereValue() should return correct filtered subsets', () {
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

    test('whereValue() should preserve original order', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('c', '1'),
        FlatEntry('d', '3'),
        FlatEntry('e', '1'),
      ]);
      final entries = doc.whereValue('1').toList();
      expect(entries.map((e) => e.key).toList(), ['a', 'c', 'e']);
    });

    test('operator == should make two documents with identical entries equal',
        () {
      final doc1 = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      final doc2 = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      expect(doc1, equals(doc2));
    });

    test('operator == should make order differences unequal', () {
      final doc1 = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      final doc2 = FlatDocument(const [
        FlatEntry('b', '2'),
        FlatEntry('a', '1'),
      ]);
      expect(doc1, isNot(equals(doc2)));
    });

    test('hashCode should be equal for identical documents', () {
      final doc1 = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      final doc2 = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      expect(doc1.hashCode, equals(doc2.hashCode));
    });

    test('toString() should display entry count', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      expect(doc.toString(), 'FlatDocument(2 entries)');
      expect(FlatDocument.empty().toString(), 'FlatDocument(0 entries)');
    });
  });

  group('FlatDocument.empty and .length', () {
    test('should create document with 0 entries', () {
      final doc = FlatDocument.empty();
      expect(doc.length, 0);
      expect(doc.entries, isEmpty);
    });

    test('should report isEmpty == true, isNotEmpty == false', () {
      final doc = FlatDocument.empty();
      expect(doc.isEmpty, isTrue);
      expect(doc.isNotEmpty, isFalse);
    });

    test('.length should match entries count', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      expect(doc.length, 2);
      expect(doc.length, doc.entries.length);
    });

    test('empty document has no keys, empty toMap, empty valuesOf', () {
      final doc = FlatDocument.empty();
      expect(doc.keys, isEmpty);
      expect(doc.toMap(), isEmpty);
      expect(doc.valuesOf('missing'), isEmpty);
    });

    test('isEmpty and isNotEmpty work correctly for non-empty document', () {
      final doc = FlatDocument(const [FlatEntry('a', '1')]);
      expect(doc.isEmpty, isFalse);
      expect(doc.isNotEmpty, isTrue);
    });
  });

  group('FlatEntry.validated', () {
    test('should create an entry with a trimmed key and given value', () {
      final entry = FlatEntry.validated(' theme ', 'dark');
      expect(entry.key, 'theme');
      expect(entry.value, 'dark');
    });

    test('should throw ArgumentError when key is empty or whitespace only', () {
      expect(
        () => FlatEntry.validated(''),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('must not be empty or whitespace'),
        )),
      );

      expect(
        () => FlatEntry.validated('   '),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('must not be empty or whitespace'),
        )),
      );

      expect(
        () => FlatEntry.validated('\t\n'),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('must not be empty or whitespace'),
        )),
      );
    });

    test('should preserve value correctly, including null', () {
      final entry1 = FlatEntry.validated('key', 'value');
      expect(entry1.key, 'key');
      expect(entry1.value, 'value');

      final entry2 = FlatEntry.validated('key', null);
      expect(entry2.key, 'key');
      expect(entry2.value, isNull);
    });

    test('should produce correct toString()', () {
      final entry = FlatEntry.validated('theme', 'dark');
      expect(entry.toString(), 'FlatEntry(theme, dark)');

      final nullEntry = FlatEntry.validated('theme', null);
      expect(nullEntry.toString(), 'FlatEntry(theme, null)');
    });

    test('should implement proper == and hashCode equality', () {
      final entry1 = FlatEntry.validated('theme', 'dark');
      final entry2 = FlatEntry.validated('theme', 'dark');
      final entry3 = FlatEntry.validated('theme', 'light');

      expect(entry1, equals(entry2));
      expect(entry1.hashCode, equals(entry2.hashCode));
      expect(entry1, isNot(equals(entry3)));
    });
  });

  group('FlatDocument.fromMap', () {
    test('should create a document with entries matching map order', () {
      final map = {'a': '1', 'b': '2', 'c': '3'};
      final doc = FlatDocument.fromMap(map);
      expect(doc.entries.map((e) => e.key).toList(), ['a', 'b', 'c']);
      expect(doc.entries.map((e) => e.value).toList(), ['1', '2', '3']);
    });

    test('should return last value when key appears multiple times', () {
      final map = <String, String?>{};
      map['a'] = '1';
      map['b'] = '2';
      map['a'] = '3'; // This overwrites the previous 'a' value
      final doc = FlatDocument.fromMap(map);
      expect(doc['a'], '3');
      expect(doc['b'], '2');
    });

    test(
        'should throw FormatException on empty/whitespace key when strict: true',
        () {
      expect(
        () => FlatDocument.fromMap({'': 'value'}),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Empty key in fromMap input'),
        )),
      );

      expect(
        () => FlatDocument.fromMap({'   ': 'value'}),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Empty key in fromMap input'),
        )),
      );
    });

    test('should skip invalid keys when strict: false', () {
      final map = {'valid': 'value', '': 'invalid', '   ': 'also invalid'};
      final doc = FlatDocument.fromMap(map, strict: false);
      expect(doc.length, 1);
      expect(doc['valid'], 'value');
      expect(doc[''], isNull);
    });

    test('should preserve order of valid entries', () {
      final map = {'first': '1', 'second': '2', 'third': '3'};
      final doc = FlatDocument.fromMap(map);
      final keys = doc.entries.map((e) => e.key).toList();
      expect(keys, ['first', 'second', 'third']);
    });

    test('should correctly handle empty map', () {
      final doc = FlatDocument.fromMap({});
      expect(doc.length, 0);
      expect(doc.isEmpty, isTrue);
    });

    test('should produce expected toMap() result', () {
      final map = {'a': '1', 'b': '2'};
      final doc = FlatDocument.fromMap(map);
      expect(doc.toMap(), map);
    });

    test('should return correct keys iterable', () {
      final map = {'a': '1', 'b': '2', 'c': '3'};
      final doc = FlatDocument.fromMap(map);
      expect(doc.keys.toList(), ['a', 'b', 'c']);
    });

    test('should handle null values correctly', () {
      final map = {'a': '1', 'b': null, 'c': '3'};
      final doc = FlatDocument.fromMap(map);
      expect(doc['a'], '1');
      expect(doc['b'], isNull);
      expect(doc['c'], '3');
    });
  });

  group('FlatDocument.fromEntries', () {
    test('should create document preserving order and duplicates', () {
      final entries = [
        const FlatEntry('a', '1'),
        const FlatEntry('b', '2'),
        const FlatEntry('a', '3'),
      ];
      final doc = FlatDocument.fromEntries(entries);
      expect(doc.entries, entries);
      expect(doc.length, 3);
    });

    test(
        'should throw FormatException if any entry has empty key (strict: true)',
        () {
      final entries = [
        const FlatEntry('valid', 'value'),
        const FlatEntry('', 'invalid'),
      ];
      expect(
        () => FlatDocument.fromEntries(entries),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Empty key found in FlatEntry'),
        )),
      );
    });

    test('should not skip invalid entries when strict: false (validation only)',
        () {
      final entries = [
        const FlatEntry('valid', 'value'),
        const FlatEntry('', 'invalid'),
        const FlatEntry('   ', 'also invalid'),
      ];
      final doc = FlatDocument.fromEntries(entries, strict: false);
      expect(doc.length, 3);
      expect(doc['valid'], 'value');
      expect(doc[''], 'invalid');
      expect(doc['   '], 'also invalid');
    });

    test('should behave identically to fromMap for equivalent input', () {
      final map = {'a': '1', 'b': '2', 'c': '3'};
      final entries = [
        const FlatEntry('a', '1'),
        const FlatEntry('b', '2'),
        const FlatEntry('c', '3'),
      ];

      final docFromMap = FlatDocument.fromMap(map);
      final docFromEntries = FlatDocument.fromEntries(entries);

      expect(docFromMap.toMap(), docFromEntries.toMap());
      expect(docFromMap.entries, docFromEntries.entries);
    });

    test('should handle empty iterable', () {
      final doc = FlatDocument.fromEntries([]);
      expect(doc.isEmpty, isTrue);
      expect(doc.length, 0);
    });
  });

  group('FlatDocument.merge', () {
    test('should merge multiple documents and preserve all entries', () {
      final doc1 = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      final doc2 = FlatDocument(const [
        FlatEntry('c', '3'),
        FlatEntry('d', '4'),
      ]);
      final merged = FlatDocument.merge([doc1, doc2]);

      expect(merged.length, 4);
      expect(merged['a'], '1');
      expect(merged['b'], '2');
      expect(merged['c'], '3');
      expect(merged['d'], '4');
    });

    test('should preserve duplicates (order = concat of all)', () {
      final doc1 = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      final doc2 = FlatDocument(const [
        FlatEntry('a', '3'),
        FlatEntry('c', '4'),
      ]);
      final merged = FlatDocument.merge([doc1, doc2]);

      expect(merged.entries.map((e) => e.key).toList(), ['a', 'b', 'a', 'c']);
      expect(merged.entries.map((e) => e.value).toList(), ['1', '2', '3', '4']);
    });

    test('should ensure "last value wins" in toMap() for duplicate keys', () {
      final doc1 = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);
      final doc2 = FlatDocument(const [
        FlatEntry('a', '3'),
        FlatEntry('b', '4'),
      ]);
      final merged = FlatDocument.merge([doc1, doc2]);

      expect(merged['a'], '3');
      expect(merged['b'], '4');
    });

    test('should throw FormatException for invalid keys in strict mode', () {
      final doc1 = FlatDocument(const [FlatEntry('valid', 'value')]);
      final doc2 = FlatDocument(const [FlatEntry('', 'invalid')]);

      expect(
        () => FlatDocument.merge([doc1, doc2]),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Empty key found in FlatEntry'),
        )),
      );
    });

    test('should not skip invalid entries when strict: false (validation only)',
        () {
      final doc1 = FlatDocument(const [FlatEntry('valid', 'value')]);
      final doc2 = FlatDocument(const [FlatEntry('', 'invalid')]);
      final merged = FlatDocument.merge([doc1, doc2], strict: false);

      expect(merged.length, 2);
      expect(merged['valid'], 'value');
      expect(merged[''], 'invalid');
    });

    test('should handle empty list of documents', () {
      final merged = FlatDocument.merge([]);
      expect(merged.isEmpty, isTrue);
    });

    test('should handle single document', () {
      final doc = FlatDocument(const [FlatEntry('a', '1')]);
      final merged = FlatDocument.merge([doc]);
      expect(merged, doc);
    });
  });

  group('FlatDocument.single', () {
    test('should create a document with exactly one entry', () {
      final doc = FlatDocument.single('key', value: 'value');
      expect(doc.length, 1);
      expect(doc['key'], 'value');
      expect(doc.entries.first.key, 'key');
      expect(doc.entries.first.value, 'value');
    });

    test('should validate key when strict: true (throws on invalid)', () {
      expect(
        () => FlatDocument.single('', value: 'value'),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('must not be empty or whitespace'),
        )),
      );

      expect(
        () => FlatDocument.single('   ', value: 'value'),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('must not be empty or whitespace'),
        )),
      );
    });

    test('should accept invalid key when strict: false', () {
      final doc = FlatDocument.single('', value: 'value', strict: false);
      expect(doc.length, 1);
      expect(doc[''], 'value');
    });

    test('should correctly expose entry via doc[key]', () {
      final doc = FlatDocument.single('theme', value: 'dark');
      expect(doc['theme'], 'dark');
      expect(doc['missing'], isNull);
    });

    test('should handle null value', () {
      final doc = FlatDocument.single('key', value: null);
      expect(doc.length, 1);
      expect(doc['key'], isNull);
    });

    test('should trim key when strict: true', () {
      final doc = FlatDocument.single('  key  ', value: 'value');
      expect(doc['key'], 'value');
      expect(doc.entries.first.key, 'key');
    });
  });

  group('FlatDocument.validateEntries', () {
    test(
        'should throw FormatException if any entry has empty/whitespace key (strict: true)',
        () {
      final entries = [
        const FlatEntry('valid', 'value'),
        const FlatEntry('', 'invalid'),
      ];

      expect(
        () => FlatDocument.validateEntries(entries),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Empty key found in FlatEntry'),
        )),
      );
    });

    test('should do nothing when strict: false', () {
      final entries = [
        const FlatEntry('valid', 'value'),
        const FlatEntry('', 'invalid'),
      ];

      expect(() => FlatDocument.validateEntries(entries, strict: false),
          returnsNormally);
    });

    test('should handle empty iterable gracefully (no throw)', () {
      expect(() => FlatDocument.validateEntries([]), returnsNormally);
      expect(() => FlatDocument.validateEntries([], strict: false),
          returnsNormally);
    });

    test('should handle mixed entries: only valid keys pass', () {
      final entries = [
        const FlatEntry('valid1', 'value1'),
        const FlatEntry('valid2', 'value2'),
      ];

      expect(() => FlatDocument.validateEntries(entries), returnsNormally);
    });

    test('should throw on whitespace-only keys', () {
      final entries = [
        const FlatEntry('valid', 'value'),
        const FlatEntry('   ', 'whitespace'),
        const FlatEntry('\t\n', 'tab newline'),
      ];

      expect(
        () => FlatDocument.validateEntries(entries),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Empty key found in FlatEntry'),
        )),
      );
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
