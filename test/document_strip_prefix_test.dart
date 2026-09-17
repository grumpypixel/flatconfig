import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatDocument.stripPrefix', () {
    test('strip_prefix_rewrites_keys', () {
      final doc = FlatDocument.parse('''
window.width = 1200
window.height = 800
theme = dark
''');

      final clean = doc.stripPrefix('window.');
      expect(clean.toMap().keys.toList(), ['width', 'height']);
      expect(clean['width'], '1200');
      expect(clean['height'], '800');
      expect(clean['theme'], isNull);
    });

    test('strip_prefix_order_preserved', () {
      final doc = FlatDocument.parse('''
window.b = 2
window.a = 1
window.c = 3
''');
      final clean = doc.stripPrefix('window.');
      expect(clean.keys.toList(), ['b', 'a', 'c']);
    });

    test('strip_prefix_missing_prefix_empty', () {
      final doc = FlatDocument.parse('''
a = 1
b = 2
''');
      final clean = doc.stripPrefix('window.');
      expect(clean.isEmpty, isTrue);
      expect(clean.toMap(), isEmpty);
    });

    test('strip_prefix_empty_prefix_clone_behavior', () {
      final doc = FlatDocument.parse('''
a = 1
b = 2
a = 3
''');
      final copy = doc.stripPrefix('');
      expect(copy.toMap(), doc.toMap());
      expect(identical(copy, doc), isFalse);
      expect(copy.entries.length, doc.entries.length);
    });

    test('strip_prefix_excludes_bare_key_and_similar_prefixes', () {
      final doc = FlatDocument.parse('''
window = legacy
window.width = 1200
windowx.width = 999
''');

      final clean = doc.stripPrefix('window.');

      expect(clean.toMap(), equals({'width': '1200'}));
      expect(clean['window'], isNull);
      expect(clean['windowx.width'], isNull);
    });

    test('strip_prefix_resolves_duplicates_latest_wins', () {
      final doc = FlatDocument.parse('''
window.mode = a
window.mode = b
window.size = small
window.size = large
''');

      final clean = doc.stripPrefix('window.');

      expect(clean.toMap(), equals({'mode': 'b', 'size': 'large'}));
    });

    test('strip_prefix_refuses_a_key_it_cannot_rename', () {
      // Every one of these is a valid key that strips to an invalid one: the
      // empty key, one starting with the comment prefix, one starting with
      // whitespace. Dropping them silently lost an entry the caller never
      // heard about, so the operation fails instead and names the key.
      for (final key in const ['window.', 'window.#secret', 'window. padded']) {
        final doc = FlatDocument([
          FlatEntry(key, 'value'),
          FlatEntry('window.width', '800'),
        ]);

        expect(
          () => doc.stripPrefix('window.'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'message',
              contains(key),
            ),
          ),
          reason: key,
        );
      }
    });

    test('strip_prefix_renames_everything_it_can', () {
      final doc = FlatDocument.parse('''
window.width = 800
window.height = 600
''');

      expect(doc.stripPrefix('window.').toMap(), {
        'width': '800',
        'height': '600',
      });
    });

    test('strip_prefix_preserves_resets', () {
      final doc = FlatDocument.parse('''
window.width =
window.height = 600
''');

      final clean = doc.stripPrefix('window.');
      expect(clean['width'], isNull);
      expect(clean['height'], '600');
    });
  });
}
