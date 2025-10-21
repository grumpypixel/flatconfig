import 'package:flatconfig/src/document.dart';
import 'package:flatconfig/src/ghostty_semantics.dart';
import 'package:flatconfig/src/options.dart';
import 'package:test/test.dart';

void main() {
  group('processDocumentWithGhosttySemantics', () {
    test('no includes → all entries are pre-include; tail is empty', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);

      const options = FlatParseOptions();
      final result = processDocumentWithGhosttySemantics(
        doc,
        options,
        const <String>{},
      );

      expect(result.seenAnyInclude, isFalse);
      expect(result.includeValues, isEmpty);
      expect(result.preIncludeEntries, doc.entries);
      expect(result.filteredTailEntries, isEmpty);

      // Build final document to ensure order is preserved (pre only)
      final finalDoc = buildGhosttyDocument(
        result.preIncludeEntries,
        const [],
        result.filteredTailEntries,
      );
      expect(finalDoc.entries, doc.entries);
    });

    test('with includes → collect values; filter tail by include keys', () {
      // Simulate a file where an include appears, then later entries.
      final doc = FlatDocument(const [
        FlatEntry('x', 'root'),
        FlatEntry('config-file', 'inc1'),
        FlatEntry('config-file', '  inc2  '),
        FlatEntry('x', 'should-be-filtered'), // overridden by include keys
        FlatEntry('y', 'allowed'),
      ]);

      const options = FlatParseOptions();
      // Keys that would be produced by the resolved includes
      const keysFromIncludes = {'x'};

      final result = processDocumentWithGhosttySemantics(
        doc,
        options,
        keysFromIncludes,
      );

      expect(result.seenAnyInclude, isTrue);
      expect(result.includeValues, ['inc1', 'inc2']);
      expect(result.preIncludeEntries, [const FlatEntry('x', 'root')]);
      expect(result.filteredTailEntries, [const FlatEntry('y', 'allowed')]);

      // Final assembled document order: pre, includes, filtered tail
      final includeEntries = const [
        FlatEntry('x', 'from-include-1'),
        FlatEntry('x', 'from-include-2'),
      ];
      final finalDoc = buildGhosttyDocument(
        result.preIncludeEntries,
        includeEntries,
        result.filteredTailEntries,
      );

      expect(
          finalDoc.valuesOf('x'), ['root', 'from-include-1', 'from-include-2']);
      expect(finalDoc['y'], 'allowed');
    });
  });
}
