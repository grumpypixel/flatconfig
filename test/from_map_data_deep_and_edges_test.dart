import 'dart:convert' show JsonUnsupportedObjectError;

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

class _Nope {
  final int x = 7;
}

class _OkRoot {
  final String v = 'x';
  Map<String, Object?> toJson() => {'v': v};
}

class _OkVal {
  _OkVal(this.n);
  final int n;
  Map<String, Object?> toJson() => {'n': n};
}

enum Mode { off, on }

void main() {
  group('Deep nesting & mixed types', () {
    test('deeply nested maps with mixed scalars', () {
      final now = DateTime.utc(2025, 1, 2, 3, 4, 5);
      final doc = FlatDocument.fromData({
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
                },
              },
            },
          },
        },
      });

      expect(doc['a.b.c.d.e.s'], 'str');
      expect(doc['a.b.c.d.e.n'], '1.25');
      expect(doc['a.b.c.d.e.b'], 'false');
      expect(doc['a.b.c.d.e.m'], 'on');
      expect(doc['a.b.c.d.e.t'], now.toIso8601String());
      expect(doc['a.b.c.d.e.u'], 'https://e/x');
    });

    test('list in map in list triggers JSON fallback for inner composites', () {
      final doc = FlatDocument.fromData({
        'pipeline': [
          {
            'name': 'blur',
            'params': [
              {'radius': 3},
            ],
          },
          'end',
        ],
      });

      final vals = doc.allValues('pipeline');
      expect(vals.length, 2);
      expect(vals.first, contains('"name":"blur"'));
      expect(vals.last, 'end');
    });
  });

  group('Key/path edge cases', () {
    test('child non-string map key is stringified', () {
      final doc = FlatDocument.fromData({
        'a': {42: 1},
      });

      expect(doc['a.42'], '1');
    });

    test('root non-string map key is stringified', () {
      final doc = FlatDocument.fromData({
        42.toString(): {'x': 1}, // simulate non-string origin
      });

      expect(doc['42.x'], '1');
    });

    test(
      'child empty key produces path with trailing separator (documented behavior)',
      () {
        final doc = FlatDocument.fromData({
          'parent': {'': 'v'},
        }, options: const FlatDataOptions(separator: '.'));

        // This results in 'parent.' (not trimmed). Valid key in FlatDocument.
        expect(doc['parent.'], 'v');
      },
    );

    test('custom separator with overlapping characters + keyEscaper', () {
      final doc = FlatDocument.fromData(
        {
          'root:part': {'child::part': 1},
        },
        options: FlatDataOptions(
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
    test(
      'valueEncoder on root Map short-circuits traversal (beats keyEscaper)',
      () {
        final doc = FlatDocument.fromData(
          {
            'r.o.o.t': {'child': 1},
          },
          options: FlatDataOptions(
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
      },
    );
  });

  group('CSV item encoder receives keyPath', () {
    test('csvItemEncoder sees the actual list key path', () {
      final seen = <String>[];
      String myCsvItemEncoder(String item, String keyPath) {
        seen.add(keyPath);
        return item; // no quoting
      }

      final doc = FlatDocument.fromData(
        {
          'list': ['a', 'b'],
        },
        options: FlatDataOptions(
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
      final doc = FlatDocument.fromData(
        {
          'n': [null, null],
        },
        options: const FlatDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
          csvNullToken: 'NULL',
          dropNulls: false,
        ),
      );

      expect(doc['n'], 'NULL,NULL');
    });

    test('empty list is empty string (csv)', () {
      final doc = FlatDocument.fromData({
        'e': <Object?>[],
      }, options: const FlatDataOptions(listMode: FlatListMode.csv));

      expect(doc['e'], '');
    });
  });

  group('Root null handling (dropNulls)', () {
    test('dropNulls=false creates explicit reset entry', () {
      final doc = FlatDocument.fromData({'k': null});
      expect(doc.allValues('k'), [null]);
      expect(doc['k'], isNull);
    });

    test('dropNulls=true omits the key entirely', () {
      final doc = FlatDocument.fromData({
        'k': null,
      }, options: const FlatDataOptions(dropNulls: true));
      expect(doc.allValues('k'), isEmpty);
      expect(doc['k'], isNull);
      expect(doc.keys.contains('k'), isFalse);
    });
  });

  group('JSON fallback behavior', () {
    test('non-encodable custom class throws JsonUnsupportedObjectError', () {
      expect(
        () => FlatDocument.fromData({'obj': _Nope()}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
    });

    test(
      'Set falls back to JSON -> also throws by default (non-encodable)',
      () {
        expect(
          () => FlatDocument.fromData({
            's': {1, 2, 3},
          }),
          throwsA(isA<JsonUnsupportedObjectError>()),
        );
      },
    );

    test('custom object with toJson() is JSON-encodable (root)', () {
      final doc = FlatDocument.fromData({'obj': _OkRoot()});
      expect(doc['obj'], '{"v":"x"}');
    });

    test('custom object with toJson() in list encodes via JSON', () {
      final doc = FlatDocument.fromData({
        'l': [_OkVal(1), _OkVal(2)],
      }, options: const FlatDataOptions(listMode: FlatListMode.multi));
      expect(doc.allValues('l'), ['{"n":1}', '{"n":2}']);
    });
  });

  group('Strict validation propagation', () {
    test('a whitespace-only key is rejected', () {
      // The parser trims keys, so '   ' could never be read back (SPEC.md 3).
      expect(
        () => FlatDocument.fromData({'   ': 'x'}),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Large document sanity', () {
    test('order preserved for many entries; multi emits duplicates', () {
      final map = <String, Object?>{};
      for (var i = 0; i < 200; i++) {
        map['k$i'] = [i, i + 1];
      }
      final doc = FlatDocument.fromData(map);

      // Spot check a few positions and values
      expect(doc.allValues('k0'), ['0', '1']);
      expect(doc.allValues('k50'), ['50', '51']);
      expect(doc.allValues('k199'), ['199', '200']);

      // Key order preserved
      final keys = doc.keys.toList();
      expect(keys.first, 'k0');
      expect(keys[100], 'k100');
      expect(keys.last, 'k199');
    });
  });

  group('CSV raw join without encoder', () {
    test('no quoting is applied when csvItemEncoder is null', () {
      final doc = FlatDocument.fromData(
        {
          'csv': ['a,b', 'x'],
        },
        options: const FlatDataOptions(
          listMode: FlatListMode.csv,
          csvSeparator: ',',
        ),
      );
      expect(doc['csv'], 'a,b,x');
    });
  });

  group('KeyEscaper with double-colon separator at root', () {
    test('root and child containing :: are both escaped', () {
      final doc = FlatDocument.fromData(
        {
          'root::part': {'child::part': 1},
        },
        options: FlatDataOptions(
          separator: '::',
          keyEscaper: (k) => k.replaceAll('::', r'\:\:'),
        ),
      );

      expect(doc[r'root\:\:part::child\:\:part'], '1');
    });
  });
}
