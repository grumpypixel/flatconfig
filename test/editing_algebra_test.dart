import 'dart:math';

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

/// The laws the editing operations obey, checked over generated documents
/// rather than over the handful of shapes someone thought to write down.
///
/// A document is immutable, so every operation here answers the same question:
/// what does the result read back as, and is the original still what it was.

const _keys = <String>['a', 'b', 'font-size', 'window.width', 'ünïcödé'];

const _values = <String?>[null, '', '1', 'two', ' spaced ', 'say "hi"'];

FlatDocument _randomDocument(Random rnd) => FlatDocument([
  for (var i = 0; i < rnd.nextInt(8); i++)
    FlatEntry(
      _keys[rnd.nextInt(_keys.length)],
      _values[rnd.nextInt(_values.length)],
    ),
]);

/// Runs [law] over 200 generated documents and a key that is sometimes present
/// and sometimes not.
void _forManyDocuments(void Function(FlatDocument doc, String key) law) {
  final rnd = Random(20260916); // fixed seed: a failure is reproducible
  for (var i = 0; i < 200; i++) {
    law(_randomDocument(rnd), _keys[rnd.nextInt(_keys.length)]);
  }
}

void main() {
  group('withValue', () {
    test('the key reads back as what was written', () {
      _forManyDocuments((doc, key) {
        for (final value in _values) {
          expect(doc.withValue(key, value)[key], value);
        }
      });
    });

    test('the key is left with exactly one entry', () {
      _forManyDocuments((doc, key) {
        expect(doc.withValue(key, 'v').allValues(key), ['v']);
      });
    });

    test('setting twice is the same as setting once', () {
      _forManyDocuments((doc, key) {
        expect(
          doc.withValue(key, '1').withValue(key, '2').entries,
          doc.withValue(key, '2').entries,
        );
      });
    });

    test('no other key is touched', () {
      _forManyDocuments((doc, key) {
        final after = doc.withValue(key, 'v');
        for (final other in _keys.where((k) => k != key)) {
          expect(after.allValues(other), doc.allValues(other), reason: other);
        }
      });
    });

    test('an existing key keeps the place of its first occurrence', () {
      final doc = FlatDocument.parse('a = 1\nb = x\na = 3\n');

      expect(doc.withValue('a', '2').entries, [
        FlatEntry('a', '2'),
        FlatEntry('b', 'x'),
      ]);
    });

    test('a new key is appended', () {
      final doc = FlatDocument.parse('a = 1\n');

      expect(doc.withValue('z', '9').entries, [
        FlatEntry('a', '1'),
        FlatEntry('z', '9'),
      ]);
    });

    test('null writes a reset, which is not the same as removing', () {
      final doc = FlatDocument.parse('a = 1\n').withValue('a', null);

      expect(doc.lookup('a'), isA<FlatReset>());
      expect(doc.containsKey('a'), isTrue);
      expect(doc.encode().trim(), 'a =');
    });

    test('an invalid key is rejected rather than stored', () {
      expect(
        () => FlatDocument.empty().withValue('a=b', 'v'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('without', () {
    test('the key is gone afterwards', () {
      _forManyDocuments((doc, key) {
        final after = doc.without(key);

        expect(after.containsKey(key), isFalse);
        expect(after.allValues(key), isEmpty);
        expect(after.lookup(key), isA<FlatAbsent>());
      });
    });

    test('a reset goes too', () {
      final doc = FlatDocument.parse('a = 1\na =\n');

      expect(doc.lookup('a'), isA<FlatReset>());
      expect(doc.without('a').lookup('a'), isA<FlatAbsent>());
    });

    test('removing twice is the same as removing once', () {
      _forManyDocuments((doc, key) {
        expect(doc.without(key).without(key).entries, doc.without(key).entries);
      });
    });

    test('the surviving entries keep their order', () {
      _forManyDocuments((doc, key) {
        expect(
          doc.without(key).entries,
          doc.entries.where((e) => e.key != key).toList(),
        );
      });
    });

    test('removing a key that is not there changes nothing', () {
      _forManyDocuments((doc, _) {
        expect(doc.without('not-present').entries, doc.entries);
      });
    });
  });

  group('withEntry', () {
    test('the entry lands at the end and shadows an earlier one', () {
      _forManyDocuments((doc, key) {
        final after = doc.withEntry(FlatEntry(key, 'appended'));

        expect(after.entries.last, FlatEntry(key, 'appended'));
        expect(after[key], 'appended');
        expect(after.length, doc.length + 1);
      });
    });

    test('an earlier entry for the same key survives', () {
      final doc = FlatDocument.parse('a = 1\n').withEntry(FlatEntry('a', '2'));

      expect(doc.allValues('a'), ['1', '2']);
    });
  });

  group('concat', () {
    test('it is the resolved merge of the two maps', () {
      final rnd = Random(4711);
      for (var i = 0; i < 200; i++) {
        final a = _randomDocument(rnd);
        final b = _randomDocument(rnd);

        expect(a.concat(b).toMap(), {...a.toMap(), ...b.toMap()});
      }
    });

    test('it concatenates the entries, in order', () {
      _forManyDocuments((doc, _) {
        final other = FlatDocument.parse('z = 9\n');

        expect(doc.concat(other).entries, [...doc.entries, ...other.entries]);
      });
    });

    test('the empty document is the identity, on both sides', () {
      _forManyDocuments((doc, _) {
        expect(doc.concat(FlatDocument.empty()).entries, doc.entries);
        expect(FlatDocument.empty().concat(doc).entries, doc.entries);
      });
    });

    test('+ is concat', () {
      _forManyDocuments((doc, _) {
        final other = FlatDocument.parse('z = 9\n');

        expect((doc + other).entries, doc.concat(other).entries);
      });
    });
  });

  group('every operation leaves the original alone', () {
    test('the entries before and after are the same list', () {
      _forManyDocuments((doc, key) {
        final before = [...doc.entries];

        doc
          ..withValue(key, 'v')
          ..without(key)
          ..withEntry(FlatEntry(key, 'v'))
          ..concat(FlatDocument.parse('z = 9\n'))
          ..collapse()
          ..slice('a');

        // stripPrefix refuses a key it cannot rename, which a document whose
        // key is exactly `a` has. An operation that throws has to leave the
        // original alone just as one that returns does.
        try {
          doc.stripPrefix('a');
        } on ArgumentError {
          // Expected for that corpus member.
        }

        expect(doc.entries, before);
      });
    });
  });

  group('collapse', () {
    test('it leaves one entry per key, and the last value of each', () {
      _forManyDocuments((doc, _) {
        final collapsed = doc.collapse();

        expect(collapsed.toMap(), doc.toMap());
        expect(
          collapsed.entries.map((e) => e.key).toSet().length,
          collapsed.length,
        );
      });
    });

    test('collapsing twice changes nothing more', () {
      _forManyDocuments((doc, _) {
        expect(doc.collapse().collapse().entries, doc.collapse().entries);
      });
    });
  });
}
