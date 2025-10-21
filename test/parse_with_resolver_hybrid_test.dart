import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('resolver: hybrid (file + memory)', () {
    test('tail after first include cannot override include keys (hybrid)',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('flatconfig_test_');
      try {
        final base = File(p.join(tempDir.path, 'base.conf'))
          ..writeAsStringSync('key = from-file\n');

        final resolver = CompositeIncludeResolver([
          FileIncludeResolver(),
        ]);

        final text = [
          'config-file = ${base.path}',
          'key = from-tail',
          'new = ok',
        ].join('\n');

        final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          text,
          resolver: resolver,
          originId: p.join(tempDir.path, 'virtual_main.conf'),
        );

        expect(doc['key'], 'from-file');
        expect(doc['new'], 'ok');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('relative include resolves against including file directory',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('flatconfig_test_');
      try {
        final sub = Directory(p.join(tempDir.path, 'sub'))..createSync();
        final base = File(p.join(sub.path, 'base.conf'))
          ..writeAsStringSync('config-file = colors.conf\n');
        File(p.join(sub.path, 'colors.conf')).writeAsStringSync('c = 1\n');

        final resolver = CompositeIncludeResolver([FileIncludeResolver()]);

        final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = ${base.path}',
          resolver: resolver,
          originId: p.join(tempDir.path, 'main.conf'),
        );

        expect(doc['c'], '1');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('composite resolver priority (first hit wins)', () async {
      final tempDir = await Directory.systemTemp.createTemp('flatconfig_test_');
      try {
        final cfg = File(p.join(tempDir.path, 'x.conf'))
          ..writeAsStringSync('k = file\n');

        // memory ohne prefix -> kann denselben Target-Namen liefern
        final mem = MemoryIncludeResolver({'x.conf': 'k = mem\n'});

        // Memory vor File => mem gewinnt
        var resolver = CompositeIncludeResolver([mem, FileIncludeResolver()]);
        var doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = ${p.relative(cfg.path, from: tempDir.path)}',
          resolver: resolver,
          originId: p.join(tempDir.path, 'root'),
        );
        expect(doc['k'], 'mem');

        // File vor Memory => file gewinnt
        resolver = CompositeIncludeResolver([FileIncludeResolver(), mem]);
        doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = ${p.relative(cfg.path, from: tempDir.path)}',
          resolver: resolver,
          originId: p.join(tempDir.path, 'root'),
        );
        expect(doc['k'], 'file');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('quoted file include path with spaces', () async {
      final tempDir = await Directory.systemTemp.createTemp('flatconfig_test_');
      try {
        final cfg = File(p.join(tempDir.path, 'spaced name.conf'))
          ..writeAsStringSync('x = y\n');
        final resolver = CompositeIncludeResolver([FileIncludeResolver()]);

        final text = 'config-file = "${cfg.path}"\n';

        final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          text,
          resolver: resolver,
          originId: p.join(tempDir.path, 'root'),
        );

        expect(doc['x'], 'y');
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
    test('file base includes + memory override', () async {
      final tempDir = await Directory.systemTemp.createTemp('flatconfig_test_');
      try {
        final base = File(p.join(tempDir.path, 'base.conf'))
          ..writeAsStringSync('name = Base\nconfig-file = colors.conf\n');
        File(p.join(tempDir.path, 'colors.conf')).writeAsStringSync(
          'primary = blue\n',
        );

        final mem = MemoryIncludeResolver({
          'mem:hotfix.conf': 'primary = mint\n',
        }, prefix: 'mem:');

        final resolver = CompositeIncludeResolver([
          FileIncludeResolver(),
          mem,
        ]);

        final text = [
          'config-file = ${base.path}',
          'config-file = mem:hotfix.conf',
        ].join('\n');

        final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          text,
          resolver: resolver,
          originId: p.join(tempDir.path, 'virtual_main.conf'),
        );

        expect(doc['name'], 'Base');
        expect(doc['primary'], 'mint'); // memory override wins later
      } finally {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('hybrid: reset in main does not block later include reassignment',
        () async {
      final temp = await Directory.systemTemp.createTemp('flatconfig_test_');
      try {
        final base = File(p.join(temp.path, 'base.conf'))
          ..writeAsStringSync('x = from-file\n');

        final mem = MemoryIncludeResolver({
          'mem:later.conf': 'x = from-mem\n',
        }, prefix: 'mem:');

        final resolver = CompositeIncludeResolver([FileIncludeResolver(), mem]);

        final text = [
          'config-file = ${base.path}', // x=from-file
          'x =', // reset to empty string (non-blocking)
          'config-file = mem:later.conf', // x=from-mem (later include wins)
        ].join('\n');

        final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
          text,
          resolver: resolver,
          originId: p.join(temp.path, 'root'),
        );

        expect(doc['x'], 'from-mem');
      } finally {
        await temp.delete(recursive: true);
      }
    });
  });
}
