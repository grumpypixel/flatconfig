import 'dart:convert';
import 'dart:typed_data';

import 'package:flatconfig/flatconfig_includes.dart';
import 'package:test/test.dart';

/// The shipped defects that no other test file pins, named after what went
/// wrong rather than after the release that fixed it. The rest are covered
/// where they belong topically: quoting and backslashes in
/// `spec_conformance_test.dart`, the empty string in `round_trip_test.dart`,
/// cached views in `document_test.dart`, prefix guards in
/// `document_strip_prefix_test.dart`, and include path folding in
/// `includes_test.dart`.
///
/// Everything here asserts a thrown error or a returned value, never an
/// `assert`: a release build strips assertions, and one of these defects was a
/// guard that existed only as one.

void main() {
  group('an ignored reset is absent, not merely unread', () {
    // An ignored reset still claimed an anchor and still updated the last-write
    // position. The existing tests missed both shapes because each of their
    // keys ended on a real value, where the stale anchor is overwritten again.

    test('a key written only as a reset does not survive', () {
      final doc = FlatDocument([FlatEntry('a', null)]);

      expect(doc.collapse(ignoreResets: true).entries, isEmpty);
    });

    test('a trailing reset does not move the value it left alone', () {
      final doc = FlatDocument([
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('a', null),
      ]);

      for (final order in CollapseOrder.values) {
        expect(doc.collapse(ignoreResets: true, order: order).entries, [
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
        ], reason: 'with $order');
      }
    });

    test('a reset between two values still changes nothing', () {
      final doc = FlatDocument([
        FlatEntry('a', '1'),
        FlatEntry('a', null),
        FlatEntry('a', '3'),
      ]);

      expect(doc.collapse(ignoreResets: true).entries, [FlatEntry('a', '3')]);
    });

    test('without the flag a reset is an ordinary last write', () {
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('a', null)]);

      expect(doc.collapse().entries, [FlatEntry('a', null)]);
      expect(doc.collapse(dropNulls: true).entries, isEmpty);
    });
  });

  group('a configured comment prefix reaches the encoder', () {
    // Key validity is judged against the default `#` so that a document does
    // not become invalid because of the options of whoever parses it. That
    // left `;secret` valid at construction, encoding to `;secret = value` and
    // re-parsing to nothing at all — the entry gone without a trace.
    for (final prefix in const [';', '//', '--']) {
      test('a key beginning with «$prefix» is refused at encode time', () {
        final doc = FlatDocument([FlatEntry('${prefix}secret', 'value')]);

        expect(
          () => doc.encode(options: FlatEncodeOptions(commentPrefix: prefix)),
          throwsArgumentError,
        );
        // Only against the prefix in force. The same document is fine with the
        // default, where `;secret` is an ordinary key.
        expect(doc.encode(), '${prefix}secret = value\n');
      });
    }

    test('the default prefix needs no encode-time check', () {
      // A key beginning with `#` cannot be built, so the guard never fires for
      // the common case.
      expect(() => FlatEntry('#secret', 'value'), throwsArgumentError);
    });

    test('an empty prefix disables the check with comments', () {
      final doc = FlatDocument([FlatEntry(';secret', 'value')]);

      expect(
        doc.encode(options: const FlatEncodeOptions(commentPrefix: '')),
        ';secret = value\n',
      );
    });
  });

  group('a byte stream is whatever the caller happens to hold', () {
    // Both entry points transformed the stream with a decoder, which is a
    // StreamTransformer<List<int>, String> and throws when bound to a
    // Stream<Uint8List>. Every test passed the stream straight to the
    // parameter, where inference made it a Stream<List<int>> and hid it; a
    // caller who names the stream first gets the subtype and the crash.
    final utf8Bytes = Uint8List.fromList(utf8.encode('a = 1\nb = 2\n'));
    final expected = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);

    test('parseBytes accepts a Stream<Uint8List>', () async {
      final Stream<Uint8List> bytes = Stream.value(utf8Bytes);

      expect(await FlatDocument.parseBytes(bytes), expected);
    });

    test('streamEntries accepts a Stream<Uint8List>', () async {
      final Stream<Uint8List> bytes = Stream.value(utf8Bytes);

      expect(
        await FlatDocument.streamEntries(bytes).toList(),
        expected.entries,
      );
    });
  });

  group('a number that is not finite is not a number', () {
    // The range accessors compared with <= and >=, which are false for NaN in
    // both directions, so NaN passed every range unchecked. Those accessors
    // are gone as of the accessor collapse, but the rejection is what keeps a
    // NaN out of a caller's own comparison too.
    for (final text in const ['NaN', 'Infinity', '-Infinity', '-NaN']) {
      test('$text does not read back as a double', () {
        final doc = FlatDocument.parse('x = $text\n');

        expect(doc.getDouble('x'), isNull);
        expect(doc.getDoubleOr('x', 1), 1);
        expect(() => doc.requireDouble('x'), throwsFormatException);
      });
    }

    test('a converter written by hand sees nothing to compare', () {
      final doc = FlatDocument.parse('x = NaN\n');

      expect(doc.getAs('x', (raw) => double.tryParse(raw)), isNaN);
      expect(doc.getDouble('x'), isNull);
    });

    test('a finite number still parses, at the edges too', () {
      expect(FlatDocument.parse('x = 1.5\n').getDouble('x'), 1.5);
      expect(FlatDocument.parse('x = -0.0\n').getDouble('x'), -0.0);
      expect(FlatDocument.parse('x = 1e308\n').getDouble('x'), 1e308);
    });
  });

  group('the guards on public input survive a release build', () {
    // These were assertions. A release build strips them and the bad value
    // went on to be used, so each one is now a check that throws.
    test('a comment prefix cannot span a line break', () {
      expect(
        () => FlatDocument.parse(
          'a = 1\n',
          options: const FlatParseOptions(commentPrefix: '#\n'),
        ),
        throwsArgumentError,
      );
    });

    test('a separator must be exactly one character', () {
      expect(() => splitRespectingQuotes('a,b', '::'), throwsArgumentError);
      expect(() => splitRespectingQuotes('a,b', ''), throwsArgumentError);
      expect(() => indexOfUnquoted('a,b', '::'), throwsArgumentError);
      expect(() => indexOfUnquoted('a,b', ''), throwsArgumentError);
    });

    test('a line terminator cannot be empty', () {
      // Computed, so the constructor's assert is not evaluated at compile
      // time. A debug build rejects it there; a release build has dropped the
      // assert and rejects it in the encoder instead. The defect was that
      // neither happened.
      final empty = String.fromCharCodes(const <int>[]);

      expect(
        () => FlatDocument.parse('a = 1\n').encodeToBytesWithWriteOptions(
          writeOptions: FlatStreamWriteOptions(lineTerminator: empty),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });

    test('a negative include depth is rejected where it is used', () {
      final negative = int.parse('-1');

      expect(
        () => parseWithIncludesSync(
          'a = 1\n',
          resolver: MemoryIncludeResolver(const {}),
          includeOptions: FlatIncludeOptions(maxIncludeDepth: negative),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });

    test('a key the format cannot represent never reaches a document', () {
      for (final key in const ['a=b', 'a"b', '#a', ' a', 'a ', '', 'a\nb']) {
        expect(
          () => FlatEntry(key, 'v'),
          throwsArgumentError,
          reason: 'key "$key" should have been rejected',
        );
      }
    });

    test('a value the format cannot represent does not either', () {
      expect(() => FlatEntry('a', 'one\ntwo'), throwsArgumentError);
    });
  });

  group('a malformed include directive is handled, not crashed on', () {
    final resolver = MemoryIncludeResolver(const {'theme.conf': 'k = v'});

    test('a lone quote does not run the unquoting off the end', () {
      // Both "starts with a quote" and "ends with a quote" are true of a
      // single quote character, so the unquoting asked for substring(1, 0) and
      // a hand-edited file reached the caller as a RangeError.
      for (final directive in const ['config-file = "', 'config-file = ?"']) {
        expect(
          () => parseWithIncludesSync('$directive\n', resolver: resolver),
          isNot(throwsA(isA<RangeError>())),
          reason: directive,
        );
      }
    });

    test('a directive that names nothing asks no resolver anything', () {
      // Emptiness used to be judged before the marker and the quotes were
      // stripped, so `?` and `""` were resolved as a unit named "" — for a
      // network resolver, a request for an empty URL.
      final counting = _CountingResolver();

      for (final directive in const [
        'config-file =',
        'config-file = ?',
        'config-file = ""',
        'config-file = ?""',
      ]) {
        final doc = parseWithIncludesSync(
          '$directive\nk = v\n',
          resolver: counting,
        );

        expect(doc.toMap(), {'k': 'v'}, reason: directive);
        // Asserting toMap() alone is what hid the duplicate below for a
        // release: a key repeated with the same value resolves identically.
        expect(doc.entries, [FlatEntry('k', 'v')], reason: directive);
      }

      expect(counting.requested, isEmpty);
    });

    test('a directive that names nothing does not start the tail', () {
      // The head stopped at the first line using the include key, while the
      // tail started there too, so an entry after an empty directive was
      // collected as both and appeared twice.
      for (final directive in const [
        'config-file =',
        'config-file = ?',
        'config-file = ""',
        'config-file = ?""',
      ]) {
        final doc = parseWithIncludesSync(
          'a = 1\n$directive\nb = 2\n',
          resolver: _CountingResolver(),
        );

        expect(doc.entries, [
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
        ], reason: directive);
      }
    });

    test('an empty directive does not shield a key from a real include', () {
      // The boundary decides which local entries an include may drop. With the
      // empty directive counted as one, `b` sat in the tail and lost to the
      // include; it belongs to the head, where it survives and loses only the
      // lookup.
      final doc = parseWithIncludesSync(
        'config-file =\nb = local\nconfig-file = theme.conf\n',
        resolver: MemoryIncludeResolver(const {'theme.conf': 'b = included'}),
      );

      expect(doc.entries, [
        FlatEntry('b', 'local'),
        FlatEntry('b', 'included'),
      ]);
      expect(doc['b'], 'included');
    });
  });
}

/// A resolver that answers nothing and records what it was asked for.
final class _CountingResolver extends SyncIncludeResolver {
  final requested = <String>[];

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    requested.add(request.target);

    return null;
  }
}
