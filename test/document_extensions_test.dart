// test/document_extensions_test.dart

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatDocumentExtensions', () {
    group('collapse', () {
      test('collapses duplicates, latest wins (default order firstOccurrence)',
          () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', 'x'),
          FlatEntry('a', '2'),
          FlatEntry('c', '3'),
          FlatEntry('a', '4'),
        ]);

        final collapsed = doc.collapse();
        expect(collapsed.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:4', // at first occurrence position of 'a'
          'b:x',
          'c:3',
        ]);
      });

      test('order: lastWrite anchors at last occurrence index', () {
        final doc = FlatDocument(const [
          FlatEntry('k', '1'),
          FlatEntry('x', 'a'),
          FlatEntry('k', '2'),
          FlatEntry('y', 'b'),
          FlatEntry('k', '3'),
        ]);

        final collapsed = doc.collapse(order: CollapseOrder.lastWrite);
        expect(collapsed.entries.map((e) => e.key).toList(), [
          'x',
          'y',
          'k', // anchored at last occurrence
        ]);
        expect(collapsed['k'], '3');
      });

      test('dropNulls removes explicit resets when final is null', () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('a', null),
          FlatEntry('b', null),
          FlatEntry('b', '2'),
        ]);

        final collapsed = doc.collapse(dropNulls: true);
        expect(collapsed.entries.map((e) => '${e.key}:${e.value}').toList(), [
          // 'a' final is null -> removed
          'b:2',
        ]);
      });

      test('multiValueKeys preserved fully and in-place', () {
        final doc = FlatDocument(const [
          FlatEntry('keybind', 'A'),
          FlatEntry('mode', '1'),
          FlatEntry('keybind', 'B'),
          FlatEntry('mode', '2'),
          FlatEntry('keybind', 'C'),
        ]);

        final collapsed = doc.collapse(multiValueKeys: {'keybind'});
        expect(collapsed.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'keybind:A',
          'mode:2',
          'keybind:B',
          'keybind:C',
        ]);
      });

      test('idempotent: collapsing twice yields same result', () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('a', '2'),
          FlatEntry('b', 'x'),
          FlatEntry('b', 'y'),
        ]);

        final once = doc.collapse();
        final twice = once.collapse();
        expect(twice.entries, once.entries);
      });

      test('handles empty key and unicode/quoted semantics unchanged', () {
        final doc = FlatDocument(const [
          FlatEntry('', 'value'),
          FlatEntry('greeting', 'Hey ya! 👋'),
          FlatEntry('', 'later'),
        ]);
        final collapsed = doc.collapse();
        expect(collapsed[''], 'later');
        expect(collapsed['greeting'], 'Hey ya! 👋');
      });

      test(
          'parity: collapse().toMap equals toMap when dropNulls=false',
          () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('mv', 'X'),
          FlatEntry('a', '2'),
          FlatEntry('mv', 'Y'),
          FlatEntry('b', null),
        ]);

        final collapsed = doc.collapse(multiValueKeys: {'mv'});
        expect(collapsed.toMap(), doc.toMap());
      });

      test('single-occurrence keys remain unchanged and in place', () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
          FlatEntry('a', '3'),
          FlatEntry('c', '4'),
        ]);
        final first = doc.collapse();
        final last = doc.collapse(order: CollapseOrder.lastWrite);

        expect(first.entries.map((e) => e.key).toList(), ['a', 'b', 'c']);
        expect(last.entries.map((e) => e.key).toList(), ['b', 'a', 'c']);
        expect(first['b'], '2');
        expect(last['b'], '2');
      });

      test('only multi-value document stays identical when declared', () {
        final doc = FlatDocument(const [
          FlatEntry('mv', 'A'),
          FlatEntry('mv', 'B'),
        ]);
        final collapsed = doc.collapse(multiValueKeys: {'mv'});
        expect(collapsed.entries, doc.entries);
      });

      test('all-null series removed when dropNulls=true', () {
        final doc = FlatDocument(const [
          FlatEntry('a', null),
          FlatEntry('a', null),
        ]);
        final collapsed = doc.collapse(dropNulls: true);
        expect(collapsed.entries, isEmpty);
      });

      test('predicate multi-value key works and ORs with set', () {
        final doc = FlatDocument(const [
          FlatEntry('mv1', 'A'),
          FlatEntry('k', '1'),
          FlatEntry('mv2', 'B'),
          FlatEntry('k', '2'),
        ]);
        final collapsed = doc.collapse(
          multiValueKeys: {'mv1'},
          isMultiValueKey: (k) => k == 'mv2',
        );
        expect(collapsed.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'mv1:A',
          'k:2',
          'mv2:B',
        ]);
      });

      test('anchor behavior with lastWrite around multi-values', () {
        final doc = FlatDocument(const [
          FlatEntry('k', '1'),
          FlatEntry('mv', 'A'),
          FlatEntry('k', '2'),
          FlatEntry('mv', 'B'),
          FlatEntry('x', 'Z'),
        ]);
        final collapsed = doc.collapse(
          order: CollapseOrder.lastWrite,
          multiValueKeys: {'mv'},
        );
        expect(collapsed.entries.map((e) => e.key).toList(), [
          'mv', // mv A
          'k', // anchored at index of last 'k' (between mv A and mv B)
          'mv', // mv B
          'x',
        ]);
        expect(collapsed['k'], '2');
      });

      test(
          'relative order of different keys reflects anchors (no sorting '
          'artifacts)', () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', 'x'),
          FlatEntry('a', '2'),
          FlatEntry('c', 'y'),
          FlatEntry('b', 'z'),
        ]);
        final collapsed = doc.collapse(order: CollapseOrder.lastWrite);
        expect(collapsed.entries.map((e) => e.key).toList(), [
          'a', // 'a' last at index 2, before 'c' and final 'b'
          'c',
          'b',
        ]);
        expect(collapsed['a'], '2');
        expect(collapsed['b'], 'z');
      });

      test('collapse result entries remain unmodifiable', () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('a', '2'),
        ]);
        final collapsed = doc.collapse();
        expect(
          () => collapsed.entries.add(const FlatEntry('x', 'y')),
          throwsUnsupportedError,
        );
      });

      test(
          'ignoreResets option preserves previous values when encountering null',
          () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('a', null), // reset
          FlatEntry('a', '3'),
          FlatEntry('b', '2'),
          FlatEntry('b', null), // reset
        ]);

        final collapsed = doc.collapse(ignoreResets: true);
        expect(collapsed.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:3', // final value, ignoring the reset
          'b:2', // previous value preserved, ignoring the reset
        ]);
      });

      test('ignoreResets with lastWrite order anchors correctly', () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
          FlatEntry('a', null), // reset
          FlatEntry('c', '3'),
          FlatEntry('a', '4'),
        ]);

        final collapsed = doc.collapse(
          ignoreResets: true,
          order: CollapseOrder.lastWrite,
        );
        expect(collapsed.entries.map((e) => e.key).toList(), [
          'b',
          'c',
          'a', // anchored at last occurrence (index 4)
        ]);
        expect(collapsed['a'], '4');
      });
    });
    group('merge', () {
      test('basic merge with override=true (default)', () {
        final doc1 = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('b', '3'),
          FlatEntry('c', '4'),
        ]);

        final merged = doc1.merge(doc2);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'b:2',
          'b:3', // overridden value from doc2
          'c:4',
        ]);
      });

      test('merge with override=false preserves existing entries', () {
        final doc1 = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('b', '3'),
          FlatEntry('c', '4'),
        ]);

        final merged = doc1.merge(doc2, override: false);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'b:2', // preserved from doc1, not overridden
          'c:4', // new entry from doc2
        ]);
      });

      test('merge empty document with non-empty', () {
        final empty = FlatDocument.empty();
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
        ]);

        final merged1 = empty.merge(doc);
        final merged2 = doc.merge(empty);

        expect(merged1.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'b:2',
        ]);

        expect(merged2.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'b:2',
        ]);
      });

      test('merge two empty documents', () {
        final empty1 = FlatDocument.empty();
        final empty2 = FlatDocument.empty();

        final merged = empty1.merge(empty2);

        expect(merged.entries, isEmpty);
        expect(merged.isEmpty, isTrue);
      });

      test('merge preserves order of entries', () {
        final doc1 = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', '2'),
          FlatEntry('c', '3'),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('d', '4'),
          FlatEntry('a', '5'),
          FlatEntry('e', '6'),
        ]);

        final merged = doc1.merge(doc2);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'b:2',
          'c:3',
          'd:4',
          'a:5', // overridden value
          'e:6',
        ]);
      });

      test('merge handles null values correctly', () {
        final doc1 = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', null),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('b', '2'),
          FlatEntry('c', null),
        ]);

        final merged = doc1.merge(doc2);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'b:null',
          'b:2', // overridden value
          'c:null',
        ]);
      });

      test('merge with override=false and null values', () {
        final doc1 = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('b', null),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('b', '2'),
          FlatEntry('c', null),
        ]);

        final merged = doc1.merge(doc2, override: false);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'b:null', // preserved from doc1
          'c:null', // new entry from doc2
        ]);
      });

      test('merge with multiple duplicate keys', () {
        final doc1 = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('a', '2'),
          FlatEntry('b', '3'),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('a', '4'),
          FlatEntry('a', '5'),
          FlatEntry('c', '6'),
        ]);

        final merged = doc1.merge(doc2);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'a:2',
          'b:3',
          'a:4',
          'a:5',
          'c:6',
        ]);
      });

      test('merge with override=false and multiple duplicate keys', () {
        final doc1 = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('a', '2'),
          FlatEntry('b', '3'),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('a', '4'),
          FlatEntry('a', '5'),
          FlatEntry('c', '6'),
        ]);

        final merged = doc1.merge(doc2, override: false);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'a:2',
          'b:3',
          'c:6', // only new keys are added
        ]);
      });

      test('merge returns new document without mutating originals', () {
        final doc1 = FlatDocument(const [
          FlatEntry('a', '1'),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('b', '2'),
        ]);

        final merged = doc1.merge(doc2);

        // Original documents should be unchanged
        expect(
            doc1.entries.map((e) => '${e.key}:${e.value}').toList(), ['a:1']);
        expect(
            doc2.entries.map((e) => '${e.key}:${e.value}').toList(), ['b:2']);

        // Merged document should be different
        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'a:1',
          'b:2',
        ]);

        // Should be different instances
        expect(identical(merged, doc1), isFalse);
        expect(identical(merged, doc2), isFalse);
      });

      test('merge with complex scenarios', () {
        final doc1 = FlatDocument(const [
          FlatEntry('database.host', 'localhost'),
          FlatEntry('database.port', '5432'),
          FlatEntry('app.debug', 'false'),
          FlatEntry('app.debug', 'true'), // duplicate key
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('database.port', '3306'), // override
          FlatEntry('app.name', 'MyApp'),
          FlatEntry('app.debug', 'false'), // override
          FlatEntry('cache.enabled', 'true'),
        ]);

        final merged = doc1.merge(doc2);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'database.host:localhost',
          'database.port:5432',
          'app.debug:false',
          'app.debug:true',
          'database.port:3306', // overridden
          'app.name:MyApp',
          'app.debug:false', // overridden
          'cache.enabled:true',
        ]);
      });

      test('merge with override=false and complex scenarios', () {
        final doc1 = FlatDocument(const [
          FlatEntry('database.host', 'localhost'),
          FlatEntry('database.port', '5432'),
          FlatEntry('app.debug', 'false'),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('database.port', '3306'), // should not override
          FlatEntry('app.name', 'MyApp'),
          FlatEntry('app.debug', 'true'), // should not override
          FlatEntry('cache.enabled', 'true'),
        ]);

        final merged = doc1.merge(doc2, override: false);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'database.host:localhost',
          'database.port:5432', // preserved from doc1
          'app.debug:false', // preserved from doc1
          'app.name:MyApp', // new from doc2
          'cache.enabled:true', // new from doc2
        ]);
      });

      test('merge preserves entry order within each document', () {
        final doc1 = FlatDocument(const [
          FlatEntry('z', '1'),
          FlatEntry('a', '2'),
          FlatEntry('m', '3'),
        ]);

        final doc2 = FlatDocument(const [
          FlatEntry('x', '4'),
          FlatEntry('b', '5'),
          FlatEntry('y', '6'),
        ]);

        final merged = doc1.merge(doc2);

        expect(merged.entries.map((e) => '${e.key}:${e.value}').toList(), [
          'z:1',
          'a:2',
          'm:3',
          'x:4',
          'b:5',
          'y:6',
        ]);
      });
    });

    group('debug', () {
      test('debugDump moved works as before (with/without indexes)', () {
        final doc = FlatDocument(const [
          FlatEntry('b', null),
          FlatEntry('a', '1'),
        ]);
        expect(doc.debugDump().split('\n'), ['[0] b = null', '[1] a = 1']);
        expect(doc.debugDump(includeIndexes: false).split('\n'),
            ['b = null', 'a = 1']);
      });

      test('toPrettyString supports sorting and alignment', () {
        final doc = FlatDocument(const [
          FlatEntry('bbb', '2'),
          FlatEntry('a', '1'),
        ]);
        final pretty = doc.toPrettyString(
            includeIndexes: false, sortByKey: true, alignColumns: true);
        expect(pretty.split('\n'), ['a   = 1', 'bbb = 2']);
      });

      test('toPrettyString keeps insertion order when not sorting', () {
        final doc = FlatDocument(const [
          FlatEntry('bbb', '2'),
          FlatEntry('a', '1'),
        ]);
        final pretty = doc.toPrettyString(
            includeIndexes: true, sortByKey: false, alignColumns: false);
        expect(pretty.split('\n'), ['[0] bbb = 2', '[1] a = 1']);
      });

      test('debugDump returns empty string for empty document', () {
        final empty = FlatDocument(const []);
        expect(empty.debugDump(), '');
        expect(empty.debugDump(includeIndexes: false), '');
      });

      test('toPrettyString returns empty string for empty document', () {
        final empty = FlatDocument(const []);
        expect(empty.toPrettyString(), '');
        expect(
            empty.toPrettyString(
                includeIndexes: false, sortByKey: true, alignColumns: true),
            '');
      });

      test('toPrettyString aligns columns with indexes and null values', () {
        final doc = FlatDocument(const [
          FlatEntry('a', '1'),
          FlatEntry('bbbb', null),
        ]);
        final pretty = doc.toPrettyString(
            includeIndexes: true, sortByKey: false, alignColumns: true);
        expect(pretty.split('\n'), ['[0] a    = 1', '[1] bbbb = null']);
      });

      test('toPrettyString sortByKey is stable for duplicate keys', () {
        final doc = FlatDocument(const [
          FlatEntry('k', '1'),
          FlatEntry('k', '2'),
          FlatEntry('a', 'x'),
        ]);
        final pretty = doc.toPrettyString(
            includeIndexes: false, sortByKey: true, alignColumns: false);
        expect(pretty.split('\n'), ['a = x', 'k = 1', 'k = 2']);
      });
    });
  });
}
