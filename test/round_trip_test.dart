import 'dart:convert';
import 'dart:math';

import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/src/parser.dart';
import 'package:test/test.dart';

/// Round-trip property: for every document a user can legally build,
/// `parse(encode(d))` must equal `d` — same entries, same order, same
/// duplicates, and the same distinction between `null` and `''`.
///
/// This is the Phase 1 gate from ROADMAP_1.0.md and the executable form of
/// SPEC.md §7. Both sides use default options on purpose: a conforming encoder
/// and a conforming parser must agree without the caller tuning anything.

/// Keys that are valid under SPEC.md §3.
const _keys = <String>[
  'a',
  'font-size',
  'window.width',
  'THEME',
  'k1',
  'a.b.c.d',
  'ünïcödé',
  'x_y',
];

/// Values that a user can legally hold, per SPEC.md §5 and §7.
/// Newlines are excluded: the format cannot represent them (§7).
const _values = <String?>[
  null, // explicit reset
  '', // empty string — must stay distinct from null
  'plain',
  '14',
  ' leading',
  'trailing ',
  ' both ',
  'with space',
  'say "hi"',
  '"fully quoted"',
  'ends with quote"',
  r'C:\temp\x',
  r'trailing\\',
  r'\',
  'a = b',
  '#not-a-comment',
  'has # hash',
  'tab\there',
  'emoji 🎛',
  '   ',
];

FlatDocument _rebuild(FlatDocument d) => FlatDocument.parse(d.encode());

void _expectRoundTrip(FlatDocument original, {String? reason}) {
  final encoded = original.encode();
  final actual = FlatDocument.parse(encoded);
  expect(
    actual.entries,
    original.entries,
    reason: '${reason ?? ''}\nencoded as: ${_visible(encoded)}',
  );
}

String _visible(String s) =>
    s.replaceAll('\n', '\\n').replaceAll('\t', '\\t').replaceAll('\r', '\\r');

void main() {
  group('round-trip, single entry', () {
    for (final value in _values) {
      test('value ${_visible(value.toString())}', () {
        _expectRoundTrip(
          FlatDocument([FlatEntry('k', value)]),
          reason: 'value ${_visible(value.toString())} did not survive',
        );
      });
    }
  });

  group('round-trip, structural', () {
    test('empty document', () {
      _expectRoundTrip(FlatDocument.empty());
    });

    test('duplicate keys keep order and count', () {
      final d = FlatDocument([
        FlatEntry('a', '1'),
        FlatEntry('b', 'x'),
        FlatEntry('a', '2'),
        FlatEntry('a', null),
      ]);
      _expectRoundTrip(d);
      expect(_rebuild(d).allValues('a'), ['1', '2', null]);
    });

    test('null and empty string stay distinct', () {
      final d = FlatDocument([
        FlatEntry('reset', null),
        FlatEntry('empty', ''),
      ]);
      final back = _rebuild(d);
      expect(back['reset'], isNull, reason: 'reset must read back as null');
      expect(back['empty'], '', reason: 'empty string must read back as ""');
    });

    test('encode is idempotent', () {
      final d = FlatDocument([
        for (final v in _values) FlatEntry('k${_values.indexOf(v)}', v),
      ]);
      expect(_rebuild(d).encode(), d.encode());
    });
  });

  group('round-trip, through the shapes a file actually takes', () {
    /// One entry per value, so a failure names the value that broke.
    final everyValue = FlatDocument([
      for (var i = 0; i < _values.length; i++) FlatEntry('k$i', _values[i]),
    ]);

    test('quoting everything changes the bytes but not the document', () {
      final encoded = everyValue.encode(
        options: const FlatEncodeOptions(alwaysQuote: true),
      );

      expect(encoded, isNot(everyValue.encode()));
      expect(FlatDocument.parse(encoded), everyValue);
    });

    for (final terminator in const ['\n', '\r\n', '\r']) {
      test('line terminator ${_visible(terminator)} survives', () {
        final bytes = everyValue.encodeToBytesWithWriteOptions(
          writeOptions: FlatStreamWriteOptions(lineTerminator: terminator),
        );

        expect(FlatDocument.parse(utf8.decode(bytes)), everyValue);
      });
    }

    test('a UTF-8 BOM in front of the first line is not data', () {
      final withBom = '\uFEFF${everyValue.encode()}';

      expect(FlatDocument.parse(withBom), everyValue);
    });

    test('turning escaping off quotes without escaping', () {
      // Not a round trip: a value holding a quote cannot survive being written
      // without escapes. The encoder still quotes what needs quoting, and what
      // comes back says where the information went.
      final doc = FlatDocument([
        FlatEntry('spaced', ' both '),
        FlatEntry('quoted', 'say "hi"'),
      ]);
      final encoded = doc.encode(
        options: const FlatEncodeOptions(escapeQuoted: false),
      );

      expect(encoded, '''
spaced = " both "
quoted = "say "hi""
''');
      expect(
        FlatDocument.parse(encoded)['spaced'],
        ' both ',
        reason: 'a value with no quote in it is unharmed',
      );
      expect(
        FlatDocument.parse(encoded)['quoted'],
        isNot('say "hi"'),
        reason:
            'a value with a quote in it is not, which is why the default '
            'is to escape',
      );
    });

    test('the byte-stream reader agrees with the string reader', () async {
      // Reached through src/ because the stream readers are internal: a file
      // or a socket goes through them, and nothing else should have to.
      final bytes = everyValue.encodeToBytesWithWriteOptions(
        writeOptions: const FlatStreamWriteOptions(lineTerminator: '\r\n'),
      );

      expect(await parseByteStream(Stream.value(bytes)), everyValue);
    });
  });

  group('round-trip, generated', () {
    test('200 random documents', () {
      final rnd = Random(20260916); // fixed seed: failures are reproducible
      final failures = <String>[];

      for (var i = 0; i < 200; i++) {
        final n = rnd.nextInt(8);
        final entries = [
          for (var j = 0; j < n; j++)
            FlatEntry(
              _keys[rnd.nextInt(_keys.length)],
              _values[rnd.nextInt(_values.length)],
            ),
        ];
        final original = FlatDocument(entries);
        final encoded = original.encode();
        final actual = FlatDocument.parse(encoded);
        if (actual != original) {
          failures.add(
            '  ${_visible(encoded)}\n'
            '    expected ${original.entries}\n'
            '    actual   ${actual.entries}',
          );
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            '${failures.length}/200 documents did not round-trip:\n'
            '${failures.take(5).join('\n')}',
      );
    });
  });
}
