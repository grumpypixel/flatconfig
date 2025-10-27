import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatDocument.slice', () {
    test('slice_matches_only_prefix', () {
      final doc = FlatConfig.parse('''
window.width = 1200
window.height = 800
theme = dark
''');

      final win = doc.slice('window.');
      expect(win.toMap().keys.toList(), ['window.width', 'window.height']);
      expect(win['window.width'], '1200');
      expect(win['window.height'], '800');
      expect(win['theme'], isNull);
    });

    test('slice_preserves_order', () {
      final doc = FlatConfig.parse('''
window.b = 2
window.a = 1
window.c = 3
''');
      final win = doc.slice('window.');
      expect(win.keys.toList(), ['window.b', 'window.a', 'window.c']);
    });

    test('slice_empty_prefix_clones', () {
      final doc = FlatConfig.parse('''
a = 1
b = 2
a = 3
''');
      final copy = doc.slice('');
      // Same latest view
      expect(copy.toMap(), doc.toMap());
      // Not identical instance
      expect(identical(copy, doc), isFalse);
      // Duplicates preserved when cloning
      expect(copy.entries.length, doc.entries.length);
    });

    test('slice_missing_prefix_returns_empty', () {
      final doc = FlatConfig.parse('''
a = 1
b = 2
''');
      final sub = doc.slice('window.');
      expect(sub.isEmpty, isTrue);
      expect(sub.toMap(), isEmpty);
    });

    test('slice_does_not_mutate_source', () {
      final doc = FlatConfig.parse('''
window.width = 1200
theme = dark
''');
      final win = doc.slice('window.');
      expect(doc['theme'], 'dark');
      expect(win['theme'], isNull);
    });

    test('slice_excludes_bare_key_and_similar_prefixes', () {
      final doc = FlatConfig.parse('''
window = legacy
window.width = 800
windowx.width = 999
''');

      final win = doc.slice('window.');
      expect(win.toMap(), equals({'window.width': '800'}));
      expect(win['window'], isNull);
      expect(win['windowx.width'], isNull);
    });

    test('slice_latest_view_resolves_duplicates', () {
      final doc = FlatConfig.parse('''
window.width = 800
window.width = 1024
window.height = 600
window.height = 768
''');

      final win = doc.slice('window.');
      expect(win.toMap(),
          equals({'window.width': '1024', 'window.height': '768'}));
    });
  });
}
