import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolver: in-memory', () {
    test('tail cannot override include keys (in-memory)', () {
      final mem =
          MemoryIncludeResolver({'mem:i.conf': 'k = v\n'}, prefix: 'mem:');
      final text = 'config-file = mem:i.conf\nk = after\n';

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      expect(doc['k'], 'v');
    });

    test('explicit reset across include boundary (unquoted) does not override',
        () {
      final mem = MemoryIncludeResolver({'mem:i.conf': 'theme = dark\n'},
          prefix: 'mem:');
      final text = 'config-file = mem:i.conf\ntheme =\n';

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      // Ghostty semantics: tail cannot override include-set keys (resets included)
      expect(doc['theme'], 'dark');
    });

    test('composite priority (first hit wins) without prefix', () async {
      final temp = await Directory.systemTemp.createTemp('flatconfig_test_');
      try {
        final cfg = File(p.join(temp.path, 'x.conf'))
          ..writeAsStringSync('k = file\n');
        final abs = cfg.path;
        final mem = MemoryIncludeResolver({abs: 'k = mem\n'}); // no prefix

        var resolver = CompositeIncludeResolver([mem, FileIncludeResolver()]);
        var doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = $abs',
          resolver: resolver,
          originId: 'root',
        );
        expect(doc['k'], 'mem');

        resolver = CompositeIncludeResolver([FileIncludeResolver(), mem]);
        doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = $abs',
          resolver: resolver,
          originId: 'root',
        );
        expect(doc['k'], 'file');
      } finally {
        await temp.delete(recursive: true);
      }
    });
    test('tail after first include cannot override include keys', () {
      final mem = MemoryIncludeResolver({
        'mem:i.conf': 'key = from-include\n',
      }, prefix: 'mem:');

      final text = [
        'config-file = mem:i.conf',
        'key = from-tail',
        'new = ok',
      ].join('\n');

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      expect(doc['key'], 'from-include');
      expect(doc['new'], 'ok');
    });

    test('tail reset across include boundary does not override include', () {
      final mem = MemoryIncludeResolver({
        'mem:i.conf': 'theme = dark\n',
      }, prefix: 'mem:');

      final text = [
        'config-file = mem:i.conf',
        'theme = ""',
      ].join('\n');

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      // Ghostty semantics: tail cannot override include-set keys
      expect(doc['theme'], 'dark');
    });

    test('later include wins over earlier include', () {
      final mem = MemoryIncludeResolver({
        'mem:a': 'x = 1\n',
        'mem:b': 'x = 2\n',
      }, prefix: 'mem:');

      final text = [
        'config-file = mem:a',
        'config-file = mem:b',
      ].join('\n');

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      expect(doc['x'], '2');
    });

    test('quoted include path with escapes', () {
      final mem = MemoryIncludeResolver({
        r'mem:C:\foo\bar.conf': 'k = v\n',
      }, prefix: 'mem:');

      final text = 'config-file = "mem:C:\\\\foo\\\\bar.conf"\n';

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      expect(doc['k'], 'v');
    });
    test('basic includes, optional override, order', () {
      final resolver = MemoryIncludeResolver({
        'mem:base.conf':
            'theme = dark\nname = Core\nconfig-file = mem:colors.conf\n',
        'mem:colors.conf': 'primary = mint\naccent = teal\n',
        'mem:user.conf': 'name = Sascha\n',
      }, prefix: 'mem:');

      final mainText = [
        'config-file = mem:base.conf',
        'config-file = ?mem:user.conf',
        'version = 1.2.3',
      ].join('\n');

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        mainText,
        resolver: resolver,
        originId: 'mem:main.conf',
      );

      expect(doc['theme'], 'dark');
      expect(doc['name'], 'Sascha');
      expect(doc['primary'], 'mint');
      expect(doc['accent'], 'teal');
      expect(doc['version'], '1.2.3');
    });

    test('optional missing is ignored; required missing throws', () {
      final resolver = MemoryIncludeResolver({
        'mem:base.conf': 'config-file = ?mem:maybe.conf\nkey = value\n',
      }, prefix: 'mem:');

      // optional missing does not throw
      final ok = FlatConfigResolverIncludes.parseStringWithIncludes(
        'config-file = mem:base.conf',
        resolver: resolver,
        originId: 'mem:main.conf',
      );
      expect(ok['key'], 'value');

      // required missing should throw
      expect(
        () => FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = mem:missing.conf',
          resolver: resolver,
          originId: 'mem:main.conf',
        ),
        throwsA(isA<MissingIncludeException>()),
      );
    });

    test('cycle detection by id', () {
      final resolver = MemoryIncludeResolver({
        'mem:a': 'config-file = mem:b\n',
        'mem:b': 'config-file = mem:a\n',
      }, prefix: 'mem:');

      expect(
        () => FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = mem:a',
          resolver: resolver,
          originId: 'mem:root',
        ),
        throwsA(isA<CircularIncludeException>()),
      );
    });

    test('quoted include paths are unescaped', () {
      final resolver = MemoryIncludeResolver({
        'mem:spaced name.conf': 'x = 1\n',
      }, prefix: 'mem:');

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        'config-file = "mem:spaced name.conf"\n',
        resolver: resolver,
        originId: 'mem:root',
      );

      expect(doc['x'], '1');
    });

    test('explicit reset is non-blocking across include boundary', () {
      final mem = MemoryIncludeResolver({
        'mem:i.conf': 'theme = dark\n',
        'mem:later.conf': 'theme = light\n',
      }, prefix: 'mem:');

      final text = [
        'config-file = mem:i.conf', // sets theme=dark
        'theme =', // reset to empty string (non-blocking)
        'config-file = mem:later.conf', // may reassign theme=light (later include wins)
      ].join('\n');

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      expect(doc['theme'], 'light');
    });
  });
}
