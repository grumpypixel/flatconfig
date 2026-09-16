import 'dart:convert';

import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/src/parser.dart';
import 'package:test/test.dart';

/// Reading a document that arrives in pieces.
///
/// A file, a socket and an HTTP body all reach the parser as a byte stream cut
/// into chunks at arbitrary offsets. Nothing in the format cares where those
/// cuts fall, and this file is what says so: the same bytes must produce the
/// same document however they are split, whichever line ending they use, and
/// with or without a byte order mark.

/// Cuts [bytes] into pieces of [size], so a line ending, a multi-byte
/// character or the BOM itself can land across a boundary.
Stream<List<int>> _chunked(List<int> bytes, int size) async* {
  for (var i = 0; i < bytes.length; i += size) {
    yield bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size);
  }
}

void main() {
  group('where the chunks are cut makes no difference', () {
    // Deliberately awkward: a BOM, all three line endings in one document,
    // multi-byte characters, a quoted value and a comment.
    const source =
        '\uFEFF# a comment\r\n'
        'ünïcödé = ställe\n'
        'quoted = " spaced "\r'
        'emoji = 🎛\r\n'
        'last = 1\n';

    final expected = FlatDocument([
      FlatEntry('ünïcödé', 'ställe'),
      FlatEntry('quoted', ' spaced '),
      FlatEntry('emoji', '🎛'),
      FlatEntry('last', '1'),
    ]);

    test('the whole thing at once', () async {
      final bytes = utf8.encode(source);

      expect(await parseByteStream(Stream.value(bytes)), expected);
    });

    for (final size in const [1, 2, 3, 5, 7, 16]) {
      test('cut into $size-byte chunks', () async {
        final bytes = utf8.encode(source);

        expect(await parseByteStream(_chunked(bytes, size)), expected);
      });
    }

    test('an empty stream is an empty document', () async {
      expect(await parseByteStream(const Stream.empty()), FlatDocument.empty());
    });

    test('empty chunks in between change nothing', () async {
      final bytes = utf8.encode(source);
      final stream = Stream<List<int>>.fromIterable([
        const <int>[],
        bytes,
        const <int>[],
      ]);

      expect(await parseByteStream(stream), expected);
    });
  });

  group('a BOM is stripped once, and only at the front', () {
    test('a BOM alone yields an empty document', () async {
      expect(
        await parseByteStream(Stream.value(utf8.encode('\uFEFF'))),
        FlatDocument.empty(),
      );
    });

    test('a second BOM is part of the value', () async {
      final doc = await parseByteStream(
        Stream.value(utf8.encode('\uFEFFa = \uFEFFx\n')),
      );

      expect(doc['a'], '\uFEFFx');
    });

    test('a later line loses its BOM too, and nothing is lost with it', () {
      // Lines can arrive from concatenated sources, so a BOM is stripped
      // wherever a line starts, not only at the very front. That costs
      // nothing: a key beginning with one is rejected as leading whitespace,
      // so no key this could damage can exist in the first place.
      expect(() => FlatEntry('\uFEFFb', '2'), throwsArgumentError);

      expect(FlatDocument.parse('a = 1\n\uFEFFb = 2\n')['b'], '2');
    });

    test('a BOM inside a key or a value is ordinary data', () {
      final doc = FlatDocument([
        FlatEntry('a\uFEFFb', 'x'),
        FlatEntry('v', '\uFEFFx'),
      ]);

      expect(FlatDocument.parse(doc.encode()), doc);
    });
  });

  group('strict and lax disagree the same way in a stream as in a string', () {
    const broken = 'good = 1\nno-equals-here\n   = orphan\n';

    test('lax reports the issues and keeps going', () async {
      final issues = <FlatIssue>[];
      final doc = await parseByteStream(
        Stream.value(utf8.encode(broken)),
        options: FlatParseOptions(onIssue: issues.add),
      );

      expect(doc['good'], '1');
      expect(doc.length, 1);
      expect(issues.map((i) => i.kind), [
        FlatIssueKind.missingEquals,
        FlatIssueKind.emptyKey,
      ]);
    });

    test('strict throws on the first one', () {
      expect(
        () => parseByteStream(
          Stream.value(utf8.encode(broken)),
          options: const FlatParseOptions(strict: true),
        ),
        throwsA(isA<MissingEqualsException>()),
      );
    });

    test('a string stream agrees with a byte stream', () async {
      final fromBytes = await parseByteStream(
        Stream.value(utf8.encode(broken)),
      );
      final fromStrings = await parseStringStream(
        Stream.fromIterable(const LineSplitter().convert(broken)),
      );

      expect(fromBytes, fromStrings);
    });

    test('the reported line number counts lines, not chunks', () async {
      final issues = <FlatIssue>[];
      await parseByteStream(
        _chunked(utf8.encode(broken), 3),
        options: FlatParseOptions(onIssue: issues.add),
      );

      expect(issues.map((i) => i.line), [2, 3]);
    });
  });
}
