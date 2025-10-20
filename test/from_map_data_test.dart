// file: test/from_map_data_hooks_test.dart
import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('fromMapData – csvItemEncoder (RFC-4180)', () {
    test('quotes items with separator, quotes, and newlines', () {
      final doc = FlatConfig.fromMapData(
        {
          'tags': ['hello', 'a,b', 'with "quote"', 'multi\nline'],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',', // no space to make expected exact
          csvItemEncoder: rfc4180CsvItemEncoder(','), // robust CSV
        ),
      );

      // Expected CSV:
      // hello,"a,b","with ""quote""","multi
      // line"
      expect(
        doc['tags'],
        'hello,"a,b","with ""quote""","multi\nline"',
      );
    });

    test('respects custom separator token (e.g., "; ")', () {
      final doc = FlatConfig.fromMapData(
        {
          'vals': ['plain', 'a; b', 'no-quote'],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: '; ',
          csvItemEncoder: rfc4180CsvItemEncoder('; '),
        ),
      );

      expect(
        doc['vals'],
        'plain; "a; b"; no-quote',
      );
    });

    test('csvNullToken appears for nulls when dropNulls=false', () {
      final doc = FlatConfig.fromMapData(
        {
          'nums': [1, null, 3],
        },
        options: const FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
          csvNullToken: 'NULL',
          // no csvItemEncoder needed here
        ),
      );

      expect(doc['nums'], '1,NULL,3');
    });

    test('nulls are removed when dropNulls=true (no double delimiters)', () {
      final doc = FlatConfig.fromMapData(
        {
          'nums': [1, null, 3, null],
        },
        options: const FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
          dropNulls: true,
        ),
      );

      expect(doc['nums'], '1,3');
    });
  });

  group('fromMapData – keyEscaper (root + child)', () {
    test('escapes separator in ROOT key segment', () {
      final doc = FlatConfig.fromMapData(
        {
          'a.b': {
            'c': 1,
          },
        },
        options: FlatMapDataOptions(
          keyEscaper: (k) => k.replaceAll('.', r'\.'),
          separator: '.',
        ),
      );

      // Root 'a.b' becomes 'a\.b', then child '.c' is appended:
      expect(doc['a\\.b.c'], '1');
    });

    test('escapes separator in CHILD key segment', () {
      final doc = FlatConfig.fromMapData(
        {
          'parent': {
            'x.y': 'v',
          },
        },
        options: FlatMapDataOptions(
          keyEscaper: (k) => k.replaceAll('.', r'\.'),
          separator: '.',
        ),
      );

      // Child 'x.y' becomes 'x\.y'
      expect(doc['parent.x\\.y'], 'v');
    });

    test('works together with lists (multi) under escaped paths', () {
      final doc = FlatConfig.fromMapData(
        {
          'root.key': {
            'list.with.dots': ['a', 'b'],
          },
        },
        options: FlatMapDataOptions(
          keyEscaper: (k) => k.replaceAll('.', r'\.'),
          separator: '.',
          listMode: FlatListMode.multi,
        ),
      );

      expect(doc.valuesOf(r'root\.key.list\.with\.dots'), ['a', 'b']);
      expect(doc[r'root\.key.list\.with\.dots'], 'b');
    });
  });
}
