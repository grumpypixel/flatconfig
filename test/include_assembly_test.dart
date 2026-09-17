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

      expect(collected.includeTargets, isEmpty);
      expect(collected.preIncludeEntries, doc.entries);
      expect(collected.postIncludeEntries, isEmpty);
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
      expect(collected.postIncludeEntries, [FlatEntry('y', 'tail')]);
    });

    test('a directive that names nothing is neither target nor boundary', () {
      // Every spelling has to agree, and they have to agree with the boundary:
      // a line that resolves nothing must not start the tail, or the entries
      // after it belong to the head and the tail at once.
      //
      // These are values as the parser hands them over, which is why `""` is
      // not among them: the parser unquotes it to the empty string. A value of
      // two literal quote characters can only be built in code, and it names a
      // file called `""` — quotes are removed here only behind a `?` marker,
      // which is the one case the parser cannot see through.
      for (final spelling in const ['', '   ', '?', '?""', '? ""']) {
        final doc = FlatDocument([
          FlatEntry('config-file', spelling.isEmpty ? null : spelling),
          FlatEntry('a', '1'),
        ]);

        final collected = collectIncludes(doc, const FlatIncludeOptions());

        expect(collected.includeTargets, isEmpty, reason: 'for «$spelling»');
        expect(collected.preIncludeEntries, [
          FlatEntry('a', '1'),
        ], reason: 'for «$spelling»');
        expect(
          collected.postIncludeEntries,
          isEmpty,
          reason: 'for «$spelling»',
        );
      }
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
