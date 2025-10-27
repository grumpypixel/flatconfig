import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatDocument.stripPrefix', () {
    test('strip_prefix_rewrites_keys', () {
      final doc = FlatConfig.parse('''
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
      final doc = FlatConfig.parse('''
window.b = 2
window.a = 1
window.c = 3
''');
      final clean = doc.stripPrefix('window.');
      expect(clean.keys.toList(), ['b', 'a', 'c']);
    });

    test('strip_prefix_missing_prefix_empty', () {
      final doc = FlatConfig.parse('''
a = 1
b = 2
''');
      final clean = doc.stripPrefix('window.');
      expect(clean.isEmpty, isTrue);
      expect(clean.toMap(), isEmpty);
    });

    test('strip_prefix_empty_prefix_clone_behavior', () {
      final doc = FlatConfig.parse('''
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
      final doc = FlatConfig.parse('''
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
      final doc = FlatConfig.parse('''
window.mode = a
window.mode = b
window.size = small
window.size = large
''');

      final clean = doc.stripPrefix('window.');

      expect(clean.toMap(), equals({'mode': 'b', 'size': 'large'}));
    });

    test('strip_prefix_allows_empty_key_when_key_equals_prefix', () {
      final doc = FlatConfig.parse('''
window. = value
window.width = 800
''');

      final clean = doc.stripPrefix('window.');
      expect(clean.toMap(), equals({'': 'value', 'width': '800'}));
    });

    test('strip_prefix_preserves_resets', () {
      final doc = FlatConfig.parse('''
window.width =
window.height = 600
''');

      final clean = doc.stripPrefix('window.');
      expect(clean['width'], isNull);
      expect(clean['height'], '600');
    });
  });
}
