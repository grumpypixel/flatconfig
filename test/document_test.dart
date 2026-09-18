import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  _lookupTests();

  group('FlatDocument Core Behavior', () {
    test('preserves order of keys (first occurrence only)', () {
      final doc = FlatDocument([
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      expect(doc.keys, ['a', 'b']);
    });

    test('indexer returns last value per key', () {
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('a', '2')]);
      expect(doc['a'], '2');
    });

    test('allValues returns all values for a key', () {
      final doc = FlatDocument([FlatEntry('x', 'foo'), FlatEntry('x', 'bar')]);
      expect(doc.allValues('x'), ['foo', 'bar']);
    });

    test('supports null values (reset)', () {
      final doc = FlatDocument([FlatEntry('font-family', null)]);
      expect(doc['font-family'], isNull);
      expect(doc.allValues('font-family'), [null]);
    });

    test('indexer reflects null if last value is null', () {
      final doc = FlatDocument([FlatEntry('x', 'one'), FlatEntry('x', null)]);
      expect(doc['x'], isNull);
    });

    test('allValues returns nulls among values', () {
      final doc = FlatDocument([
        FlatEntry('k', 'v1'),
        FlatEntry('k', null),
        FlatEntry('k', 'v3'),
      ]);
      expect(doc.allValues('k'), ['v1', null, 'v3']);
    });

    test('calling toMap does not mutate entries order', () {
      final doc = FlatDocument([
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      doc.toMap(); // the point of the test: it has to run
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
      final doc = FlatDocument([FlatEntry('a', '1')]);
      expect(
        () => doc.entries.add(FlatEntry('b', '2')),
        throwsUnsupportedError,
      );
    });

    test('allValues returns empty for missing key in non-empty doc', () {
      final doc = FlatDocument([FlatEntry('a', '1')]);
      expect(doc.allValues('missing'), isEmpty);
    });

    test('allValues exposes the first occurrence too', () {
      // firstValueOf used to do this; allValues answers it and more.
      final doc = FlatDocument([
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      expect(doc.allValues('a').first, '1');
      expect(doc.allValues('b').first, '2');
      expect(doc.allValues('missing'), isEmpty);
    });

    test('operator [] returns the last occurrence value', () {
      final doc = FlatDocument([
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ]);
      expect(doc['a'], '3');
      expect(doc['b'], '2');
      expect(doc['missing'], isNull);
    });

    test('getString returns last value', () {
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('a', '2')]);
      expect(doc.getString('a'), '2');
      expect(doc.getString('missing'), isNull);
    });

    test('entries is the iterable view, and it is the only one', () {
      // FlatDocument no longer is an Iterable, so 'which view' is now something
      // the call site has to say out loud (Phase 2.2).
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);

      expect(doc.entries.map((e) => e.key), ['a', 'b']);
      expect(doc.length, 2);
      expect(doc.isEmpty, isFalse);
      expect(doc.isNotEmpty, isTrue);
    });

    test('toMap returns unmodifiable map', () {
      final doc = FlatDocument([FlatEntry('a', '1')]);
      expect(() => doc.toMap()['b'] = '2', throwsUnsupportedError);
    });

    test('toMap handles empty document', () {
      final doc = FlatDocument.empty();
      expect(doc.toMap(), isEmpty);
      expect(doc.toMap(), isA<Map<String, String?>>());
    });

    test('toMap handles null values', () {
      final doc = FlatDocument([
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
    test(
      'cache() should populate expando caches for toMap() and/or allValues',
      () {
        final doc = FlatDocument([
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
          FlatEntry('a', '3'),
        ]);

        // Cache both maps
        doc.cache(toMap: true, toAllValues: true);

        // Verify toMap is cached
        expect(doc.toMap(), {'a': '3', 'b': '2'});
        expect(doc['a'], '3');

        // Verify allValues is cached
        expect(doc.allValues('a'), ['1', '3']);
        expect(doc.allValues('b'), ['2']);
      },
    );

    test('cache() should not throw on empty document', () {
      final doc = FlatDocument.empty();
      expect(() => doc.cache(), returnsNormally);
      expect(() => doc.cache(toMap: true, toAllValues: true), returnsNormally);
    });

    test('cache() can cache only toMap', () {
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);

      // Cache only toMap
      doc.cache(toMap: true, toAllValues: false);

      // Verify toMap is cached
      expect(doc.toMap(), {'a': '1', 'b': '2'});

      // allValues should still work but not be cached
      expect(doc.allValues('a'), ['1']);
    });

    test('cache() can cache only allValues', () {
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('a', '2')]);

      // Cache only valuesOf
      doc.cache(toMap: false, toAllValues: true);

      // Verify allValues is cached
      expect(doc.allValues('a'), ['1', '2']);

      // toMap should still work but not be cached
      expect(doc.toMap(), {'a': '2'});
    });

    test('cache() with no parameters caches only toMap by default', () {
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);

      // Cache with default parameters
      doc.cache();

      // Verify toMap is cached
      expect(doc.toMap(), {'a': '1', 'b': '2'});

      // valuesOf should not be cached
      expect(doc.allValues('a'), ['1']);
    });

    test('whereKey() should return correct filtered subsets', () {
      final doc = FlatDocument([
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
      final doc = FlatDocument([
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
      final doc = FlatDocument([
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
      final doc = FlatDocument([
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
      final doc = FlatDocument([
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
      final doc = FlatDocument([
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('c', '1'),
        FlatEntry('d', '3'),
        FlatEntry('e', '1'),
      ]);
      final entries = doc.whereValue('1').toList();
      expect(entries.map((e) => e.key).toList(), ['a', 'c', 'e']);
    });

    test(
      'operator == should make two documents with identical entries equal',
      () {
        final doc1 = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
        final doc2 = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
        expect(doc1, equals(doc2));
      },
    );

    test('operator == should make order differences unequal', () {
      final doc1 = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
      final doc2 = FlatDocument([FlatEntry('b', '2'), FlatEntry('a', '1')]);
      expect(doc1, isNot(equals(doc2)));
    });

    test('hashCode should be equal for identical documents', () {
      final doc1 = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
      final doc2 = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
      expect(doc1.hashCode, equals(doc2.hashCode));
    });

    test('toString() should display entry count', () {
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
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
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
      expect(doc.length, 2);
      expect(doc.length, doc.entries.length);
    });

    test('empty document has no keys, empty toMap, empty valuesOf', () {
      final doc = FlatDocument.empty();
      expect(doc.keys, isEmpty);
      expect(doc.toMap(), isEmpty);
      expect(doc.allValues('missing'), isEmpty);
    });

    test('isEmpty and isNotEmpty work correctly for non-empty document', () {
      final doc = FlatDocument([FlatEntry('a', '1')]);
      expect(doc.isEmpty, isFalse);
      expect(doc.isNotEmpty, isTrue);
    });
  });

  group('FlatEntry', () {
    test('should keep a valid key exactly as given', () {
      final entry = FlatEntry('theme', 'dark');
      expect(entry.key, 'theme');
      expect(entry.value, 'dark');
    });

    test('should reject edge whitespace rather than trim it away', () {
      // Trimming would hand back an entry the caller never asked for.
      expect(
        () => FlatEntry(' theme ', 'dark'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must not have leading or trailing whitespace'),
          ),
        ),
      );
    });

    test('should name the rule a key breaks', () {
      void expectRejected(String key, String reason) {
        expect(
          () => FlatEntry(key),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains(reason),
            ),
          ),
          reason: 'key "$key" should be rejected',
        );
      }

      expectRejected('', 'must not be empty');
      expectRejected('   ', 'must not have leading or trailing whitespace');
      expectRejected('\t\n', 'must not have leading or trailing whitespace');
      expectRejected('a=b', "must not contain '='");
      expectRejected('a"b', 'must not contain a double quote');
      expectRejected('a\nb', 'must not contain a line break');
      expectRejected('#x', "must not begin with '#'");
    });

    test('should preserve value correctly, including null', () {
      final entry1 = FlatEntry('key', 'value');
      expect(entry1.key, 'key');
      expect(entry1.value, 'value');

      final entry2 = FlatEntry('key', null);
      expect(entry2.key, 'key');
      expect(entry2.value, isNull);
    });

    test('should produce correct toString()', () {
      final entry = FlatEntry('theme', 'dark');
      expect(entry.toString(), 'FlatEntry(theme, dark)');

      final nullEntry = FlatEntry('theme', null);
      expect(nullEntry.toString(), 'FlatEntry(theme, null)');
    });

    test('should implement proper == and hashCode equality', () {
      final entry1 = FlatEntry('theme', 'dark');
      final entry2 = FlatEntry('theme', 'dark');
      final entry3 = FlatEntry('theme', 'light');

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
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('must not be empty'),
            ),
          ),
        );

        expect(
          () => FlatDocument.fromMap({'   ': 'value'}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('must not have leading or trailing whitespace'),
            ),
          ),
        );
      },
    );

    test('has no lenient mode: an invalid key is a bug at the call site', () {
      // Leniency belongs to the parser, where hand-edited files arrive. A map
      // built in code holding a key the format cannot write is a defect.
      expect(
        () => FlatDocument.fromMap({'valid': 'value', '': 'invalid'}),
        throwsA(isA<ArgumentError>()),
      );
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
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', '3'),
      ];
      final doc = FlatDocument.fromEntries(entries);
      expect(doc.entries, entries);
      expect(doc.length, 3);
    });

    test('never sees an invalid entry, because none can be built', () {
      // FlatEntry rejects the key, so fromEntries has nothing left to filter.
      expect(() => FlatEntry(''), throwsArgumentError);
      expect(() => FlatEntry('   '), throwsArgumentError);
    });

    test('should behave identically to fromMap for equivalent input', () {
      final map = {'a': '1', 'b': '2', 'c': '3'};
      final entries = [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('c', '3'),
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
    test('should concatenate documents and preserve all entries', () {
      final doc1 = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
      final doc2 = FlatDocument([FlatEntry('c', '3'), FlatEntry('d', '4')]);
      final merged = doc1.concat(doc2);

      expect(merged.length, 4);
      expect(merged['a'], '1');
      expect(merged['b'], '2');
      expect(merged['c'], '3');
      expect(merged['d'], '4');
    });

    test('should preserve duplicates (order = concat of all)', () {
      final doc1 = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
      final doc2 = FlatDocument([FlatEntry('a', '3'), FlatEntry('c', '4')]);
      final merged = doc1 + doc2;

      expect(merged.entries.map((e) => e.key).toList(), ['a', 'b', 'a', 'c']);
      expect(merged.entries.map((e) => e.value).toList(), ['1', '2', '3', '4']);
    });

    test('should ensure "last value wins" in toMap() for duplicate keys', () {
      final doc1 = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);
      final doc2 = FlatDocument([FlatEntry('a', '3'), FlatEntry('b', '4')]);
      final merged = doc1.concat(doc2);

      expect(merged['a'], '3');
      expect(merged['b'], '4');
    });

    test('cannot be handed an invalid key, because no document holds one', () {
      // The guard sits at document construction, so merge never has to check.
      expect(
        () => FlatDocument([FlatEntry('', 'invalid')]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must not be empty'),
          ),
        ),
      );
    });

    test('folds a list of documents into one', () {
      // What the static FlatDocument.merge used to do.
      final docs = [
        FlatDocument([FlatEntry('a', '1')]),
        FlatDocument([FlatEntry('b', '2')]),
      ];
      final merged = docs.reduce((a, b) => a.concat(b));

      expect(merged.toMap(), {'a': '1', 'b': '2'});
    });

    test('concatenating with an empty document changes nothing', () {
      final doc = FlatDocument([FlatEntry('a', '1')]);

      expect(doc.concat(FlatDocument.empty()), doc);
      expect(FlatDocument.empty().concat(doc), doc);
    });
  });

  group('FlatEntry validates at construction (Phase 2.3)', () {
    test('builds a valid entry', () {
      final doc = FlatDocument([FlatEntry('key', 'value')]);
      expect(doc.length, 1);
      expect(doc['key'], 'value');
    });

    test('a null value is the explicit reset', () {
      final doc = FlatDocument([FlatEntry.reset('key')]);
      expect(doc.length, 1);
      expect(doc['key'], isNull);
      expect(doc.lookup('key'), const FlatLookup.reset());
      expect(FlatEntry.reset('k'), FlatEntry('k', null));
    });

    test('rejects an empty or whitespace-only key', () {
      expect(
        () => FlatEntry('', 'value'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must not be empty'),
          ),
        ),
      );

      expect(
        () => FlatEntry('   ', 'value'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must not have leading or trailing whitespace'),
          ),
        ),
      );
    });

    test('rejects a padded key rather than trimming it', () {
      expect(() => FlatEntry('  key  ', 'value'), throwsArgumentError);
    });

    test('rejects a value spanning a line break', () {
      expect(() => FlatEntry('k', 'a\nb'), throwsArgumentError);
    });

    test('leaves nothing for a document to filter', () {
      // There is no lenient mode anywhere, because an invalid entry cannot be
      // built in the first place.
      expect(
        () => FlatDocument([FlatEntry('ok', '1'), FlatEntry('', '2')]),
        throwsArgumentError,
      );
    });
  });

  group('FlatDocument helpers', () {
    test('getInt parses ints and returns null for invalid/missing', () {
      final doc = FlatDocument([FlatEntry('i1', '42'), FlatEntry('i2', 'x')]);
      expect(doc.getInt('i1'), 42);
      expect(doc.getInt('i2'), isNull);
      expect(doc.getInt('missing'), isNull);
    });

    test('getBool recognizes common forms and returns null when unknown', () {
      final doc = FlatDocument([
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
      final doc = FlatDocument([
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
      final a = FlatDocument([FlatEntry('k', 'v')]);
      final b = FlatDocument([FlatEntry('k', 'v')]);
      final c = FlatDocument([FlatEntry('k', 'x')]);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a == c, isFalse);
    });

    test('FlatEntry.toString includes key and value/null', () {
      final e1 = FlatEntry('k', 'v');
      final e2 = FlatEntry('n', null);
      expect(e1.toString(), contains('k'));
      expect(e1.toString(), contains('v'));
      expect(e2.toString(), contains('null'));
    });
  });

  group('immutability holds with and without cache()', () {
    // cache() used to store a plain map while toMap() wrapped its own copy, so
    // pre-caching quietly handed out a writable view of an @immutable type.
    test('toMap() is unwritable without pre-caching', () {
      final doc = FlatDocument.parse('a = 1');
      expect(() => doc.toMap()['a'] = 'HACKED', throwsUnsupportedError);
      expect(doc['a'], '1');
    });

    test('toMap() is unwritable after pre-caching', () {
      final doc = FlatDocument.parse('a = 1')..cache();
      expect(() => doc.toMap()['a'] = 'HACKED', throwsUnsupportedError);
      expect(doc['a'], '1');
    });

    test('allValues() is unwritable either way', () {
      final plain = FlatDocument.parse('a = 1\na = 2');
      expect(() => plain.allValues('a').add('3'), throwsUnsupportedError);

      final cached = FlatDocument.parse('a = 1\na = 2')
        ..cache(toAllValues: true);
      expect(() => cached.allValues('a').add('3'), throwsUnsupportedError);
      expect(cached.allValues('a'), ['1', '2']);
    });
  });
}

void _lookupTests() {
  group('FlatDocument.lookup (Phase 2.5)', () {
    final doc = FlatDocument([
      FlatEntry('present', 'x'),
      FlatEntry('empty', ''),
      FlatEntry('reset', null),
    ]);

    test('separates the three states operator [] collapses', () {
      expect(doc.lookup('present'), const FlatLookup.present('x'));
      expect(doc.lookup('reset'), const FlatLookup.reset());
      expect(doc.lookup('missing'), const FlatLookup.absent());

      // All three of those read as the same thing through the operator.
      expect(doc['reset'], isNull);
      expect(doc['missing'], isNull);
    });

    test('an empty string is present, not a reset', () {
      expect(doc.lookup('empty'), const FlatLookup.present(''));
    });

    test('last write wins, resets included', () {
      final overwritten = FlatDocument([
        FlatEntry('k', 'first'),
        FlatEntry('k', null),
      ]);
      expect(overwritten.lookup('k'), const FlatLookup.reset());
      expect(overwritten.containsKey('k'), isTrue);
    });

    test('is exhaustively switchable', () {
      String describe(FlatLookup lookup) => switch (lookup) {
        FlatAbsent() => 'absent',
        FlatReset() => 'reset',
        FlatPresent(:final value) => 'present:$value',
      };

      expect(describe(doc.lookup('present')), 'present:x');
      expect(describe(doc.lookup('reset')), 'reset');
      expect(describe(doc.lookup('missing')), 'absent');
    });

    test('valueOrNull agrees with operator []', () {
      for (final key in ['present', 'empty', 'reset', 'missing']) {
        expect(doc.lookup(key).valueOrNull, doc[key], reason: key);
      }
    });
  });
}
