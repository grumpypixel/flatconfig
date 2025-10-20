import 'dart:convert' show JsonUnsupportedObjectError;

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

class _Nope {
  final int x = 7;
}

enum Mode { off, on }

void main() {
  group('Deep nesting & mixed types', () {
    test('deeply nested maps with mixed scalars', () {
      final now = DateTime.utc(2025, 1, 2, 3, 4, 5);
      final doc = FlatConfig.fromMapData(
        {
          'a': {
            'b': {
              'c': {
                'd': {
                  'e': {
                    's': 'str',
                    'n': 1.25,
                    'b': false,
                    'm': Mode.on,
                    't': now,
                    'u': Uri.parse('https://e/x'),
                  }
                }
              }
            }
          }
        },
      );

      expect(doc['a.b.c.d.e.s'], 'str');
      expect(doc['a.b.c.d.e.n'], '1.25');
      expect(doc['a.b.c.d.e.b'], 'false');
      expect(doc['a.b.c.d.e.m'], 'on');
      expect(doc['a.b.c.d.e.t'], now.toIso8601String());
      expect(doc['a.b.c.d.e.u'], 'https://e/x');
    });

    test('list in map in list triggers JSON fallback for inner composites', () {
      final doc = FlatConfig.fromMapData({
        'pipeline': [
          {
            'name': 'blur',
            'params': [
              {'radius': 3}
            ],
          },
          'end',
        ],
      });

      final vals = doc.valuesOf('pipeline');
      expect(vals.length, 2);
      expect(vals.first, contains('"name":"blur"'));
      expect(vals.last, 'end');
    });
  });

  group('Key/path edge cases', () {
    test('root non-string map key is stringified', () {
      final doc = FlatConfig.fromMapData(
        {
          42.toString(): {'x': 1}, // simulate non-string origin
        },
      );

      expect(doc['42.x'], '1');
    });

    test(
        'child empty key produces path with trailing separator (documented behavior)',
        () {
      final doc = FlatConfig.fromMapData(
        {
          'parent': {
            '': 'v',
          }
        },
        options: const FlatMapDataOptions(separator: '.'),
      );

      // This results in 'parent.' (not trimmed). Valid key in FlatDocument.
      expect(doc['parent.'], 'v');
    });

    test('custom separator with overlapping characters + keyEscaper', () {
      final doc = FlatConfig.fromMapData(
        {
          'root:part': {
            'child::part': 1,
          }
        },
        options: FlatMapDataOptions(
          separator: '::',
          // escape only occurrences of the double-colon sequence
          keyEscaper: (k) => k.replaceAll('::', r'\:\:'),
        ),
      );

      // Root does not contain '::', so it is NOT escaped; child does.
      expect(doc[r'root:part::child\:\:part'], '1');
      // Mis-escaped root should not match
      expect(doc[r'root\:part::child\:\:part'], isNull);
    });
  });

  group('valueEncoder order & keyEscaper together', () {
    test('valueEncoder on root Map short-circuits traversal (beats keyEscaper)',
        () {
      final doc = FlatConfig.fromMapData(
        {
          'r.o.o.t': {'child': 1},
        },
        options: FlatMapDataOptions(
          keyEscaper: (k) => k.replaceAll('.', r'\.'),
          valueEncoder: (v, key) {
            if (key == r'r\.o\.o\.t' && v is Map) {
              return '<ROOT-FORCED>';
            }

            return null;
          },
        ),
      );

      // Single forced entry at the root key (already escaped)
      expect(doc.keys.length, 1);
      expect(doc[r'r\.o\.o\.t'], '<ROOT-FORCED>');
    });
  });

  group('CSV item encoder receives keyPath', () {
    test('csvItemEncoder sees the actual list key path', () {
      final seen = <String>[];
      String myCsvItemEncoder(String item, String keyPath) {
        seen.add(keyPath);
        return item; // no quoting
      }

      final doc = FlatConfig.fromMapData(
        {
          'list': ['a', 'b'],
        },
        options: FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: '|',
          csvItemEncoder: myCsvItemEncoder,
        ),
      );

      expect(doc['list'], 'a|b');
      expect(seen, everyElement(equals('list')));
    });
  });

  group('CSV all-nulls & empty', () {
    test('all nulls with dropNulls=false -> only csvNullToken repeated', () {
      final doc = FlatConfig.fromMapData(
        {
          'n': [null, null],
        },
        options: const FlatMapDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
          csvNullToken: 'NULL',
          dropNulls: false,
        ),
      );

      expect(doc['n'], 'NULL,NULL');
    });

    test('empty list is empty string (csv)', () {
      final doc = FlatConfig.fromMapData(
        {'e': <Object?>[]},
        options: const FlatMapDataOptions(listMode: FlatListMode.csv),
      );

      expect(doc['e'], '');
    });
  });

  group('JSON fallback behavior', () {
    test('non-encodable custom class throws JsonUnsupportedObjectError', () {
      expect(
        () => FlatConfig.fromMapData({'obj': _Nope()}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });

    test('Set falls back to JSON -> also throws by default (non-encodable)',
        () {
      expect(
        () => FlatConfig.fromMapData({
          's': {1, 2, 3}
        }),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });
  });

  group('rfc4180Quote corner cases', () {
    test('empty string, no quoting needed', () {
      expect(rfc4180Quote('', ','), '');
    });

    test('separator is empty, only quotes/newlines trigger quoting', () {
      expect(rfc4180Quote('a,b', ''), 'a,b');
      expect(rfc4180Quote('has "q"', ''), '"has ""q"""');
      expect(rfc4180Quote('multi\nline', ''), '"multi\nline"');
    });

    test('multiple-char separator', () {
      expect(rfc4180Quote('a; b', '; '), '"a; b"');
      expect(rfc4180Quote('plain', '; '), 'plain');
    });
  });

  group('Strict validation propagation', () {
    test('strict=false keeps whitespace-only key exactly as provided', () {
      final doc = FlatConfig.fromMapData(
        {'   ': 'x'},
        options: const FlatMapDataOptions(strict: false),
      );

      expect(doc.valuesOf('   '), ['x']);
    });
  });

  group('Large document sanity', () {
    test('order preserved for many entries; multi emits duplicates', () {
      final map = <String, Object?>{};
      for (var i = 0; i < 200; i++) {
        map['k$i'] = [i, i + 1];
      }
      final doc = FlatConfig.fromMapData(map);

      // Spot check a few positions and values
      expect(doc.valuesOf('k0'), ['0', '1']);
      expect(doc.valuesOf('k50'), ['50', '51']);
      expect(doc.valuesOf('k199'), ['199', '200']);

      // Key order preserved
      final keys = doc.keys.toList();
      expect(keys.first, 'k0');
      expect(keys[100], 'k100');
      expect(keys.last, 'k199');
    });
  });
}
