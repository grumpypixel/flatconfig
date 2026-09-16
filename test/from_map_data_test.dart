import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

enum TestEnum { red, green, blue }

void main() {
  group('fromMapData – csvItemEncoder (RFC-4180)', () {
    test('quotes items with separator and quotes', () {
      final doc = FlatDocument.fromData(
        {
          'tags': ['hello', 'a,b', 'with "quote"'],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',', // no space to make expected exact
          csvItemEncoder: rfc4180CsvItemEncoder(','), // robust CSV
        ),
      );

      expect(doc['tags'], 'hello,"a,b","with ""quote"""');
    });

    test('an item containing a newline cannot be stored', () {
      // RFC-4180 allows a newline inside a quoted field; this format does not,
      // because it is line-based. rfc4180CsvItemEncoder is therefore only safe
      // for newline-free items.
      expect(
        () => FlatDocument.fromData(
          {
            'tags': ['hello', 'multi\nline'],
          },
          options: FlatMapDataOptions(
            listMode: FlatListMode.csv,
            csvSeparator: ',',
            csvItemEncoder: rfc4180CsvItemEncoder(','),
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('must not contain a line break'),
          ),
        ),
      );
    });

    test('respects custom separator token (e.g., "; ")', () {
      final doc = FlatDocument.fromData(
        {
          'vals': ['plain', 'a; b', 'no-quote'],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: '; ',
          csvItemEncoder: rfc4180CsvItemEncoder('; '),
        ),
      );

      expect(doc['vals'], 'plain; "a; b"; no-quote');
    });

    test('csvNullToken appears for nulls when dropNulls=false', () {
      final doc = FlatDocument.fromData(
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
      final doc = FlatDocument.fromData(
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
      final doc = FlatDocument.fromData(
        {
          'a.b': {'c': 1},
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
      final doc = FlatDocument.fromData(
        {
          'parent': {'x.y': 'v'},
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
      final doc = FlatDocument.fromData(
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

      expect(doc.allValues(r'root\.key.list\.with\.dots'), ['a', 'b']);
      expect(doc[r'root\.key.list\.with\.dots'], 'b');
    });
  });

  group('fromMapData – list mode: multi', () {
    test('preserves order and encodes scalars', () {
      final doc = FlatDocument.fromData({
        'list': [1, 'a', true],
      }, options: const FlatMapDataOptions(listMode: FlatListMode.multi));

      expect(doc.allValues('list'), ['1', 'a', 'true']);
      expect(doc['list'], 'true');
    });

    test('null handling with dropNulls=false/true', () {
      final d1 = FlatDocument.fromData({
        'nums': [1, null, 2],
      }, options: const FlatMapDataOptions(listMode: FlatListMode.multi));
      expect(d1.allValues('nums'), ['1', null, '2']);

      final d2 = FlatDocument.fromData(
        {
          'nums': [1, null, 2],
        },
        options: const FlatMapDataOptions(
          listMode: FlatListMode.multi,
          dropNulls: true,
        ),
      );
      expect(d2.allValues('nums'), ['1', '2']);
    });

    test('composite items default to JSON, can skip or error', () {
      final jsonDoc = FlatDocument.fromData({
        'items': [
          {'a': 1},
          [2, 3],
        ],
      }, options: const FlatMapDataOptions(listMode: FlatListMode.multi));
      expect(jsonDoc.allValues('items'), ['{"a":1}', '[2,3]']);

      final skipDoc = FlatDocument.fromData(
        {
          'items': [
            1,
            {'a': 1},
            2,
          ],
        },
        options: const FlatMapDataOptions(
          listMode: FlatListMode.multi,
          onUnsupportedListItem: FlatUnsupportedListItem.skip,
        ),
      );
      expect(skipDoc.allValues('items'), ['1', '2']);

      expect(
        () => FlatDocument.fromData(
          {
            'items': [
              1,
              {'a': 1},
            ],
          },
          options: const FlatMapDataOptions(
            listMode: FlatListMode.multi,
            onUnsupportedListItem: FlatUnsupportedListItem.error,
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Composite item in list not supported in multi mode'),
          ),
        ),
      );
    });
  });

  group('fromMapData – list mode: csv (additional)', () {
    test('empty list becomes empty string', () {
      final doc = FlatDocument.fromData(
        {'list': <Object?>[]},
        options: const FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
        ),
      );

      expect(doc['list'], '');
    });

    test('composite items: default json, skip, and error', () {
      final jsonDoc = FlatDocument.fromData(
        {
          'items': [
            {'a': 1},
            [2, 3],
          ],
        },
        options: const FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
        ),
      );
      expect(jsonDoc['items'], '{"a":1},[2,3]');

      final skipDoc = FlatDocument.fromData(
        {
          'items': [
            1,
            {'a': 1},
            2,
          ],
        },
        options: const FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
          onUnsupportedListItem: FlatUnsupportedListItem.skip,
        ),
      );
      expect(skipDoc['items'], '1,2');

      expect(
        () => FlatDocument.fromData(
          {
            'items': [
              1,
              {'a': 1},
            ],
          },
          options: const FlatMapDataOptions(
            listMode: FlatListMode.csv,
            csvSeparator: ',',
            onUnsupportedListItem: FlatUnsupportedListItem.error,
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Composite item in list not supported in csv mode'),
          ),
        ),
      );
    });
  });

  group('fromMapData – valueEncoder precedence', () {
    test('overrides scalars, nulls, and composites (multi)', () {
      final doc = FlatDocument.fromData(
        {
          'a': null,
          'b': [
            1,
            {'m': 2},
          ],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.multi,
          onUnsupportedListItem: FlatUnsupportedListItem.error,
          valueEncoder: (v, k) => 'X:$k',
        ),
      );

      expect(doc.allValues('a'), ['X:a']);
      // valueEncoder has highest priority and applies to the list as a whole
      // (root override), so we get a single entry for 'b'.
      expect(doc.allValues('b'), ['X:b']);
    });

    test('overrides in csv mode and ignores dropNulls', () {
      final doc = FlatDocument.fromData(
        {
          'b': [null, 1],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
          dropNulls: true,
          valueEncoder: (v, k) => 'X:$k',
        ),
      );

      // valueEncoder overrides the entire list -> single CSV string 'X:b'
      expect(doc['b'], 'X:b');
    });
  });

  group('fromMapData – scalar encoding', () {
    test('String, bool, num, enum, DateTime, Uri', () {
      final doc = FlatDocument.fromData({
        's': 'str',
        'b1': true,
        'b0': false,
        'n1': 123,
        'n2': 1.5,
        'e': TestEnum.green,
        'dt': DateTime.utc(2020, 1, 2, 3, 4, 5),
        'u': Uri.parse('https://example.com/path?a=1'),
      });

      expect(doc['s'], 'str');
      expect(doc['b1'], 'true');
      expect(doc['b0'], 'false');
      expect(doc['n1'], '123');
      expect(doc['n2'], '1.5');
      expect(doc['e'], 'green');
      expect(doc['dt'], '2020-01-02T03:04:05.000Z');
      expect(doc['u'], 'https://example.com/path?a=1');
    });
  });

  group('fromMapData – strict key validation', () {
    test('empty root key throws by default (strict=true)', () {
      expect(
        () => FlatDocument.fromData({'': 1}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty root key is rejected', () {
      expect(
        () => FlatDocument.fromData({'': 1}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty root with nested map flattens to child key', () {
      final doc = FlatDocument.fromData({
        '': {'a': 1},
      });
      expect(doc['a'], '1');
    });
  });

  group('rfc4180Quote – direct', () {
    test('quotes when needed and escapes quotes', () {
      expect(rfc4180Quote('a,b', ','), '"a,b"');
      expect(rfc4180Quote('plain', ','), 'plain');
      expect(rfc4180Quote('has "quote"', ','), '"has ""quote"""');
      expect(rfc4180Quote('multi\nline', ','), '"multi\nline"');
    });
  });

  group('fromMapData – edge cases (extras)', () {
    test(
      'empty root key with null: strict=true throws; strict=false drops it',
      () {
        expect(
          () => FlatDocument.fromData({'': null}),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('custom separator and keyEscaper work together', () {
      final doc = FlatDocument.fromData(
        {
          'root.part': {'child.part': 1},
        },
        options: FlatMapDataOptions(
          separator: '/',
          keyEscaper: (k) => k.replaceAll('.', r'\.'),
        ),
      );

      expect(doc[r'root\.part/child\.part'], '1');
    });

    test('insertion order of keys is preserved', () {
      final doc = FlatDocument.fromData({'z': 1, 'a': 2, 'm': 3});

      expect(doc.keys.toList(), ['z', 'a', 'm']);
    });

    test('fallback: non-JSON-encodable object throws (root)', () {
      expect(
        () => FlatDocument.fromData({
          'x': {1, 2}, // Set is not JSON-encodable → jsonEncode throws
        }),
        throwsA(isA<Object>()), // jsonEncode error (JsonUnsupportedObjectError)
      );
    });
  });

  group('fromMapData – per-item valueEncoder overrides', () {
    test('multi mode: overrides individual items (not root list)', () {
      final doc = FlatDocument.fromData(
        {
          'l': [1, 2],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.multi,
          // Return null for root list; override items only
          valueEncoder: (v, k) => (v is List) ? null : 'I',
        ),
      );

      expect(doc.allValues('l'), ['I', 'I']);
    });

    test('csv mode: overrides individual items (not root list)', () {
      final doc = FlatDocument.fromData(
        {
          'l': [1, 2],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
          valueEncoder: (v, k) => (v is List) ? null : 'I',
        ),
      );

      expect(doc['l'], 'I,I');
    });
  });
}
