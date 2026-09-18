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
  group('getList reads the inline grammar, not just String.split', () {
    // The guide promised that a quoted item may contain the separator, while
    // the implementation split on every occurrence — so a,"b,c",d came back as
    // four fragments, two of them carrying a stray quote.

    test('a quoted item may contain the separator', () {
      final doc = FlatDocument.parse('items = a,"b,c",d\n');

      expect(doc.getList('items'), ['a', 'b,c', 'd']);
    });

    test('quotes protect whitespace that trimming would take', () {
      final doc = FlatDocument.parse('items = a, "  b  " , c\n');

      expect(doc.getList('items'), ['a', '  b  ', 'c']);
    });

    test('an item quoted as empty is kept, a bare empty one is dropped', () {
      expect(FlatDocument.parse('k = a,,b\n').getList('k'), ['a', 'b']);
      expect(FlatDocument.parse('k = a,"",b\n').getList('k'), ['a', '', 'b']);
    });

    test('escapes inside an item are decoded once', () {
      final doc = FlatDocument.parse(
        r'k = "say \"hi\"",plain'
        '\n',
      );

      expect(doc.getList('k'), ['say "hi"', 'plain']);
    });

    test('a separator longer than one character is refused', () {
      // The inline grammar is single-character, and trimming already covers
      // what a ', ' separator was reached for.
      final doc = FlatDocument.parse('k = a, b\n');

      expect(() => doc.getList('k', separator: ', '), throwsArgumentError);
      expect(doc.getList('k'), ['a', 'b']);
    });
  });

  group('data that contains itself is refused, not chased', () {
    // fromData recursed until the stack ran out. A StackOverflowError is not
    // catchable in any useful way, so a configuration loader handed a cyclic
    // structure could only die.

    test('a map containing itself', () {
      final map = <String, Object?>{};
      map['self'] = map;

      expect(() => FlatDocument.fromData(map), throwsArgumentError);
    });

    test('two maps containing each other', () {
      final a = <String, Object?>{};
      final b = <String, Object?>{'a': a};
      a['b'] = b;

      expect(() => FlatDocument.fromData(a), throwsArgumentError);
    });

    test('a list containing itself', () {
      // Lists reach the JSON fallback, which signalled this with a
      // JsonCyclicError — an Error, and so outside what any accessor promises.
      final list = <Object?>[];
      list.add(list);

      expect(() => FlatDocument.fromData({'items': list}), throwsArgumentError);
    });

    test('the same map used twice is sharing, not a cycle', () {
      final shared = <String, Object?>{'x': 1};

      expect(FlatDocument.fromData({'l': shared, 'r': shared}).toMap(), {
        'l.x': '1',
        'r.x': '1',
      });
    });

    test('deep but finite nesting is bounded rather than fatal', () {
      // Cycle detection covers the unbounded case. A finite structure still
      // recurses once per level and dies of StackOverflowError somewhere past
      // a few thousand — an Error, which nothing can usefully catch.
      Map<String, Object?> nest(int levels) {
        Object? node = 'leaf';
        for (var i = 0; i < levels; i++) {
          node = <String, Object?>{'n': node};
        }

        return {'root': node! as Map<String, Object?>};
      }

      // The default allows 64 nested maps; the 65th is one too many.
      expect(FlatDocument.fromData(nest(64)).length, 1);
      expect(() => FlatDocument.fromData(nest(65)), throwsArgumentError);

      expect(
        () => FlatDocument.fromData(nest(10000)),
        throwsArgumentError,
        reason: 'the depth that used to take the stack with it',
      );

      expect(
        FlatDocument.fromData(
          nest(200),
          options: const FlatDataOptions(maxDepth: 512),
        ).length,
        1,
      );
    });

    test('a deeply nested list is bounded too', () {
      // The depth parameter bounds the flattener's own recursion, and nothing
      // descends through it for a list: a composite item goes to jsonEncode,
      // which walks it recursively and met the end of the stack there.
      Object? node = <Object?>['leaf'];
      for (var i = 0; i < 10000; i++) {
        node = <Object?>[node];
      }

      for (final mode in FlatListMode.values) {
        expect(
          () => FlatDocument.fromData({
            'root': node,
          }, options: FlatDataOptions(listMode: mode)),
          throwsArgumentError,
          reason: 'in $mode',
        );
      }
    });

    test('maps and lists alternating are bounded as one depth', () {
      Object? node = 'leaf';
      for (var i = 0; i < 5000; i++) {
        node = i.isEven ? <Object?>[node] : <String, Object?>{'n': node};
      }

      expect(() => FlatDocument.fromData({'root': node}), throwsArgumentError);
    });

    test('a list inside the budget still encodes', () {
      Object? node = <Object?>['leaf'];
      for (var i = 0; i < 8; i++) {
        node = <Object?>[node];
      }

      expect(
        FlatDocument.fromData({
          'root': node,
        }, options: const FlatDataOptions(maxDepth: 32)).length,
        1,
      );
    });

    test('a shared subtree is refused for what it expands to', () {
      // Depth does not see this one, and neither does the size in memory.
      // JSON has no sharing, so a node holding the same child twice doubles
      // per level: forty levels is eighty objects here and 2^40 written out.
      // Walking it is what made this test hang for four minutes.
      Object? shared = <Object?>['leaf'];
      for (var i = 0; i < 40; i++) {
        shared = <Object?>[shared, shared];
      }

      expect(
        () => FlatDocument.fromData({'root': shared}),
        throwsArgumentError,
      );
    });

    test('sharing within the budget still encodes', () {
      Object? shared = <Object?>['leaf'];
      for (var i = 0; i < 10; i++) {
        shared = <Object?>[shared, shared];
      }

      // Two, because the default list mode writes one entry per item and the
      // outer list has two — the same subtree under each.
      expect(FlatDocument.fromData({'root': shared}).length, 2);
    });

    test('a long flat list is not mistaken for an expansion', () {
      // A million scalars is a big value, not an amplified one: the output is
      // the size of the input. The budget is about what sharing multiplies.
      final flat = [for (var i = 0; i < 100000; i++) i];

      expect(
        FlatDocument.fromData({
          'root': flat,
        }, options: const FlatDataOptions(listMode: FlatListMode.csv)).length,
        1,
      );
    });

    test('a custom object cannot smuggle a structure past the budgets', () {
      // The budgets only looked at maps and lists, so an ordinary object
      // passed as a leaf. jsonEncode then called its toJson, which may return
      // anything at all: the deep one died in the encoder, the wide one hung.
      expect(
        () => FlatDocument.fromData({'root': _DeepToJson()}),
        throwsArgumentError,
      );
      expect(
        () => FlatDocument.fromData({'root': _WideToJson()}),
        throwsArgumentError,
      );
      // Nested behind a map of its own, which is how it usually arrives.
      expect(
        () => FlatDocument.fromData({
          'root': {'inner': _DeepToJson()},
        }),
        throwsArgumentError,
      );
    });

    test('an ordinary custom object still encodes', () {
      expect(
        FlatDocument.fromData({'root': _SmallToJson()})['root'],
        '{"a":1}',
      );
    });

    test('a negative maxDepth is rejected where it is used', () {
      // A literal is caught by the constructor's assertion at compile time,
      // which a release build drops.
      final negative = int.parse('-1');

      expect(
        () => FlatDocument.fromData(const {
          'a': 1,
        }, options: FlatDataOptions(maxDepth: negative)),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });
  });

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

  group('strict and lenient name the same character', () {
    // They built their own positions from their own vocabularies, and drifted:
    // for a quoted value the strict path left out the offset of everything
    // trimmed from the left, so `  key = "open` was column 2 to one of them
    // and column 7 to the other. One issue, two ways of delivering it.
    const malformed = [
      'no equals here',
      '  no equals with indent',
      ' = orphan value',
      '\t= orphan after a tab',
      'a"b = quoted key',
      '  key = "open',
      '\t key = "closed" junk',
    ];

    for (final line in malformed) {
      test('«${line.replaceAll('\t', '\\t')}»', () {
        final reported = <FlatIssue>[];
        FlatDocument.parse(
          '$line\n',
          options: FlatParseOptions(onIssue: reported.add),
        );

        expect(reported, hasLength(1), reason: 'lenient found nothing');

        try {
          FlatDocument.parse(
            '$line\n',
            options: const FlatParseOptions(strict: true),
          );
          fail('strict mode accepted it');
        } on FlatParseException catch (e) {
          expect(e.issue, reported.single);
          // FormatException counts from zero, the displayed column from one.
          expect(e.offset, e.issue.column - 1);
        }
      });
    }
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

/// A value whose JSON form is far deeper than the value itself.
class _DeepToJson {
  Object? toJson() {
    Object? node = <Object?>['leaf'];
    for (var i = 0; i < 10000; i++) {
      node = <Object?>[node];
    }

    return node;
  }
}

/// A value that is shallow in memory and exponential once written out.
class _WideToJson {
  Object? toJson() {
    Object? shared = <Object?>['leaf'];
    for (var i = 0; i < 40; i++) {
      shared = <Object?>[shared, shared];
    }

    return shared;
  }
}

/// The ordinary case, which must keep working.
class _SmallToJson {
  Object? toJson() => {'a': 1};
}
