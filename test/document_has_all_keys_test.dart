import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatDocument.hasAllKeys', () {
    test('returns true when all keys exist with non-null values', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
        FlatEntry('c', '3'),
      ]);

      expect(doc.hasAllKeys(['a', 'b', 'c']), isTrue);
    });

    test('returns false when any key is missing', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
        FlatEntry('b', '2'),
      ]);

      expect(doc.hasAllKeys(['a', 'b', 'c']), isFalse);
      expect(doc.hasAllKeys(['c']), isFalse);
    });

    test('null-valued keys fail by default (ignoreNulls: true)', () {
      final doc = FlatDocument(const [
        FlatEntry('present-null', null),
      ]);

      expect(doc.hasAllKeys(['present-null']), isFalse);
    });

    test('null-valued keys pass when ignoreNulls is false', () {
      final doc = FlatDocument(const [
        FlatEntry('present-null', null),
      ]);

      expect(
        doc.hasAllKeys(['present-null'], ignoreNulls: false),
        isTrue,
      );
    });

    test('empty string value counts as present (not null)', () {
      final doc = FlatDocument(const [
        FlatEntry('empty', ''),
      ]);

      expect(doc.hasAllKeys(['empty']), isTrue);
      expect(doc.hasAllKeys(['empty'], ignoreNulls: false), isTrue);
    });

    test('caseSensitive: true (default) respects case differences', () {
      final doc = FlatDocument(const [
        FlatEntry('Host', 'localhost'),
      ]);

      expect(doc.hasAllKeys(['host']), isFalse);
      expect(doc.hasAllKeys(['Host']), isTrue);
    });

    test('caseSensitive: false matches keys ignoring case', () {
      final doc = FlatDocument(const [
        FlatEntry('Host', 'localhost'),
        FlatEntry('PORT', '8080'),
      ]);

      expect(
        doc.hasAllKeys(['host', 'port'], caseSensitive: false),
        isTrue,
      );
    });

    test('case-insensitive map uses last write for duplicates', () {
      final doc = FlatDocument(const [
        FlatEntry('port', '8080'),
        // Later entry with same lowercase key but different case + null value
        FlatEntry('PORT', null),
      ]);

      // Default ignoreNulls -> false because last write is null
      expect(
        doc.hasAllKeys(['port'], caseSensitive: false),
        isFalse,
      );

      // When ignoreNulls is false, presence with null is acceptable
      expect(
        doc.hasAllKeys(['port'], caseSensitive: false, ignoreNulls: false),
        isTrue,
      );
    });

    test('empty keys iterable returns true (vacuous truth)', () {
      final doc = FlatDocument(const [
        FlatEntry('a', '1'),
      ]);

      expect(doc.hasAllKeys([]), isTrue);
    });

    test('duplicates: last write wins; last is null', () {
      final doc = FlatConfig.parse('''
k = v1
k =
''');

      // toMap() has k -> null
      expect(
        doc.hasAllKeys(['k']),
        isFalse,
        reason: 'ignoreNulls=true (default), null not accepted',
      );
      expect(
        doc.hasAllKeys(['k'], ignoreNulls: false),
        isTrue,
        reason: 'ignoreNulls=false accepts null',
      );
    });

    test('case-insensitive with null handling', () {
      final doc = FlatConfig.parse('''
HOST =
''');

      // null → treated as missing with ignoreNulls=true
      expect(
        doc.hasAllKeys(['host'], caseSensitive: false),
        isFalse,
      );

      // null accepted when ignoreNulls=false
      expect(
        doc.hasAllKeys(['host'], caseSensitive: false, ignoreNulls: false),
        isTrue,
      );
    });

    test('mixed: some present, some null, some missing', () {
      final doc = FlatConfig.parse('''
a = 1
b =
''');

      expect(
        doc.hasAllKeys(['a', 'b', 'c']),
        isFalse,
        reason: 'c missing, b null',
      );
      expect(
        doc.hasAllKeys(['a', 'b'], ignoreNulls: false),
        isTrue,
        reason: 'a present, b present(null) and ignoreNulls=false',
      );
    });

    test('keys list may contain duplicates (should still succeed)', () {
      final doc = FlatConfig.parse('a = 1');
      expect(doc.hasAllKeys(['a', 'a', 'a']), isTrue);
    });

    test('empty string key: present vs. missing', () {
      final withEmpty = FlatDocument(const [
        FlatEntry('', 'x'),
      ]);
      expect(withEmpty.hasAllKeys(['']), isTrue);

      final withoutEmpty = FlatDocument(const [
        FlatEntry('a', '1'),
      ]);
      expect(withoutEmpty.hasAllKeys(['']), isFalse);
    });

    test(
        'case-insensitive collision: earlier non-null, later null (last write wins)',
        () {
      final doc = FlatDocument(const [
        FlatEntry('Port', '8080'),
        FlatEntry('PORT', null), // later null
      ]);

      // ignoreNulls=true → false (null counts as not present)
      expect(doc.hasAllKeys(['port'], caseSensitive: false), isFalse);

      // ignoreNulls=false → true (null accepted as present)
      expect(
        doc.hasAllKeys(['port'], caseSensitive: false, ignoreNulls: false),
        isTrue,
      );
    });

    test(
        'case-insensitive collision: earlier null, later non-null (last write wins)',
        () {
      final doc = FlatDocument(const [
        FlatEntry('PORT', null),
        FlatEntry('port', '8080'), // later non-null
      ]);

      expect(doc.hasAllKeys(['PORT'], caseSensitive: false), isTrue);
    });

    test('empty value "" is not null and counts as present by default', () {
      final doc = FlatDocument(const [FlatEntry('k', '')]);
      expect(doc.hasAllKeys(['k']), isTrue);
    });

    test('whitespace-only value is present after parsing quoted vs. unquoted',
        () {
      final quoted = FlatConfig.parse('k = "   "'); // preserved whitespace
      expect(quoted.hasAllKeys(['k']), isTrue);

      final unquoted = FlatConfig.parse('k =   '); // becomes null reset
      expect(unquoted.hasAllKeys(['k']), isFalse);
      expect(unquoted.hasAllKeys(['k'], ignoreNulls: false), isTrue);
    });
  });
}
