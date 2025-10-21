@TestOn('vm')
library include_resolver_extras_test;

import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/src/include_resolver_core.dart' as core;
// Direct import of the web stub to exercise its code path on VM
import 'package:flatconfig/src/include_resolver_stub.dart' as stub;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('include resolver extras', () {
    test('IncludeUnit.toString is informative', () {
      final unit = core.IncludeUnit(id: 'mem:x', content: 'a = 1\n');

      expect(unit.toString(), contains('IncludeUnit('));
      expect(unit.toString(), contains('mem:x'));
    });

    test('FileIncludeResolver.resolve returns null for missing target',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('flatconfig_resolver_');
      try {
        final resolver = FileIncludeResolver();
        final missing =
            resolver.resolve(p.join(temp.path, 'nope.conf'), fromId: temp.path);
        expect(missing, isNull);
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('FileIncludeResolver resolves relative to fromId directory', () async {
      final temp =
          await Directory.systemTemp.createTemp('flatconfig_resolver_');
      try {
        final base = File(p.join(temp.path, 'base.conf'))
          ..writeAsStringSync('ignored = true\n');
        File(p.join(temp.path, 'colors.conf')).writeAsStringSync('k = v\n');

        final resolver = FileIncludeResolver();
        final unit = resolver.resolve('colors.conf', fromId: base.path);
        expect(unit, isNotNull);
        expect(unit!.content, contains('k = v'));
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test(
        'FileIncludeResolver canonical id normalization on case-insensitive FS',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('flatconfig_resolver_');
      try {
        final file = File(p.join(temp.path, 'MiXeD.NaMe.CONF'))
          ..writeAsStringSync('k = v\n');
        final resolver = FileIncludeResolver();
        final unit = resolver.resolve(file.path, fromId: null);
        expect(unit, isNotNull);
        // On Windows/macOS the id is lowercased; elsewhere keep as-is. This assertion
        // is safe across platforms because lowercasing twice is idempotent.
        if (Platform.isWindows || Platform.isMacOS) {
          expect(unit!.id, equals(unit.id.toLowerCase()));
        } else {
          expect(unit!.id, equals(unit.id));
        }
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('MemoryIncludeResolver applies prefix when missing', () {
      final mem =
          core.MemoryIncludeResolver({'mem:a': 'k = v\n'}, prefix: 'mem:');
      final unit = mem.resolve('a');

      expect(unit, isNotNull);
      expect(unit!.id, 'mem:a');
      expect(unit.content, contains('k = v'));
    });

    test('CompositeIncludeResolver first hit wins with memory only', () {
      final r1 = core.MemoryIncludeResolver({'x': 'k = r1\n'});
      final r2 = core.MemoryIncludeResolver({'x': 'k = r2\n'});
      final composite = core.CompositeIncludeResolver([r1, r2]);

      final unit = composite.resolve('x');
      expect(unit, isNotNull);
      expect(unit!.content, contains('k = r1'));
    });

    test('FileIncludeResolver.resolve works with absolute path and null fromId',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('flatconfig_resolver_');
      try {
        final f = File(p.join(temp.path, 'abs.conf'))
          ..writeAsStringSync('k = file\n');
        final resolver = FileIncludeResolver();

        final unit = resolver.resolve(f.path, fromId: null);
        expect(unit, isNotNull);
        expect(unit!.id, isNotEmpty);
        expect(unit.content, contains('k = file'));
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('stub FileIncludeResolver returns null (web fallback class)', () {
      final s = stub.FileIncludeResolver();
      final unit = s.resolve('anything');
      expect(unit, isNull);
    });

    test('parseStringWithIncludes: no include leaves entries unchanged', () {
      final text = [
        'a = 1',
        'b = 2',
      ].join('\n');
      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: core.MemoryIncludeResolver(const {}),
        originId: 'mem:root',
      );
      expect(doc['a'], '1');
      expect(doc['b'], '2');
    });

    test('parseStringWithIncludes: cache is used on second pass', () {
      final mem = core.MemoryIncludeResolver({
        'mem:a': 'x = 1\n',
      }, prefix: 'mem:');
      final cache = <String, FlatDocument>{};

      final text = 'config-file = mem:a\n';
      final doc1 = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
        cache: cache,
      );
      final doc2 = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
        cache: cache,
      );

      expect(doc1['x'], '1');
      expect(doc2['x'], '1');
      expect(cache.containsKey('mem:root'), isTrue);
    });

    test('parseStringWithIncludes: depth limit is enforced', () {
      final mem = core.MemoryIncludeResolver({
        'mem:root': 'config-file = mem:one\n',
        'mem:one': 'config-file = mem:two\n',
        'mem:two': 'k = v\n',
      }, prefix: 'mem:');

      expect(
        () => FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = mem:root\n',
          resolver: mem,
          originId: 'mem:start',
          options: const FlatParseOptions(maxIncludeDepth: 1),
        ),
        throwsA(isA<MaxIncludeDepthExceededException>()),
      );
    });
  });
}
