import 'package:flatconfig/src/document.dart';
import 'package:flatconfig/src/include_assembly.dart';
import 'package:flatconfig/src/options.dart';
import 'package:test/test.dart';

/// Where an include's entries land is the whole semantics of an include, so
/// both policies are pinned here against a hand-built set of resolved groups
/// rather than through a resolver.
void main() {
  group('collectIncludes', () {
    test('without a directive everything precedes the first include', () {
      final doc = FlatDocument([FlatEntry('a', '1'), FlatEntry('b', '2')]);

      final collected = collectIncludes(doc, const FlatIncludeOptions());

      expect(collected.seenAnyInclude, isFalse);
      expect(collected.includeTargets, isEmpty);
      expect(collected.preIncludeEntries, doc.entries);
    });

    test('targets are trimmed and kept in document order', () {
      final doc = FlatDocument([
        FlatEntry('x', 'root'),
        FlatEntry('config-file', 'inc1'),
        FlatEntry('config-file', '  inc2  '),
        FlatEntry('y', 'tail'),
      ]);

      final collected = collectIncludes(doc, const FlatIncludeOptions());

      expect(collected.includeTargets, ['inc1', 'inc2']);
      expect(collected.preIncludeEntries, [FlatEntry('x', 'root')]);
    });

    test('a directive with no value names nothing and is not a target', () {
      final doc = FlatDocument([
        FlatEntry.reset('config-file'),
        FlatEntry('config-file', '   '),
        FlatEntry('a', '1'),
      ]);

      final collected = collectIncludes(doc, const FlatIncludeOptions());

      expect(collected.includeTargets, isEmpty);
      expect(collected.seenAnyInclude, isFalse);
      expect(collected.preIncludeEntries, [FlatEntry('a', '1')]);
    });
  });

  group('assembleIncludedDocument', () {
    final doc = FlatDocument([
      FlatEntry('x', 'root'),
      FlatEntry('config-file', 'inc1'),
      FlatEntry('x', 'below-the-include'),
      FlatEntry('y', 'allowed'),
    ]);
    final groups = [
      [FlatEntry('x', 'from-include')],
    ];

    test('ghostty: a line below an include cannot override it', () {
      final result = assembleIncludedDocument(
        doc,
        const FlatIncludeOptions(),
        groups,
      );

      expect(result.allValues('x'), ['root', 'from-include']);
      expect(result['x'], 'from-include');
      expect(result['y'], 'allowed');
    });

    test('lastWins: the include expands in place and the line below wins', () {
      final result = assembleIncludedDocument(
        doc,
        const FlatIncludeOptions(mergePolicy: IncludeMergePolicy.lastWins),
        groups,
      );

      expect(result.allValues('x'), [
        'root',
        'from-include',
        'below-the-include',
      ]);
      expect(result['x'], 'below-the-include');
      expect(result['y'], 'allowed');
    });

    test('lastWins keeps each group at its own directive', () {
      final twoIncludes = FlatDocument([
        FlatEntry('config-file', 'first'),
        FlatEntry('between', 'kept'),
        FlatEntry('config-file', 'second'),
      ]);

      final result = assembleIncludedDocument(
        twoIncludes,
        const FlatIncludeOptions(mergePolicy: IncludeMergePolicy.lastWins),
        [
          [FlatEntry('a', 'from-first')],
          [FlatEntry('b', 'from-second')],
        ],
      );

      expect(result.entries.map((e) => e.key), ['a', 'between', 'b']);
    });

    test('an empty group leaves no trace, under either policy', () {
      final withOptional = FlatDocument([
        FlatEntry('config-file', '?missing'),
        FlatEntry('a', '1'),
      ]);

      for (final policy in IncludeMergePolicy.values) {
        final result = assembleIncludedDocument(
          withOptional,
          FlatIncludeOptions(mergePolicy: policy),
          [const []],
        );

        expect(result.entries, [FlatEntry('a', '1')], reason: policy.name);
      }
    });

    test('the directive itself never survives into the result', () {
      for (final policy in IncludeMergePolicy.values) {
        final result = assembleIncludedDocument(
          doc,
          FlatIncludeOptions(mergePolicy: policy),
          groups,
        );

        expect(result.containsKey('config-file'), isFalse, reason: policy.name);
      }
    });
  });
}
