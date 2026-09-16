@TestOn('vm')
library include_cache_test;

import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

/// A resolver that records which units it was asked for.
final class _CountingResolver extends SyncIncludeResolver {
  _CountingResolver(this._units);

  final Map<String, String> _units;
  final List<String> requested = [];

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    requested.add(request.target);
    final content = _units[request.target];

    return content == null
        ? null
        : IncludeUnit(id: request.target, content: content);
  }
}

void main() {
  group('a parse never reuses what another parse produced', () {
    const source = 'config-file = theme.conf\n';
    final resolver = MemoryIncludeResolver({
      'theme.conf':
          r'path = "C:\\temp"'
          '\n',
    });

    FlatDocument parse(FlatParseOptions options) =>
        FlatConfigResolverIncludes.parseStringWithIncludesSync(
          source,
          resolver: resolver,
          originId: 'mem:root',
          options: options,
        );

    test('a later call sees its own parse options, not the earlier ones', () {
      expect(parse(const FlatParseOptions())['path'], r'C:\temp');
      expect(
        parse(const FlatParseOptions(decodeEscapesInQuoted: false))['path'],
        r'C:\\temp',
      );
      expect(parse(const FlatParseOptions())['path'], r'C:\temp');
    });

    test('the same origin id with different text yields different text', () {
      FlatDocument parseText(String text) =>
          FlatConfigResolverIncludes.parseStringWithIncludesSync(
            text,
            resolver: resolver,
            originId: 'mem:root',
          );

      expect(parseText('a = 1\n')['a'], '1');
      expect(parseText('b = 2\n').lookup('a'), isA<FlatAbsent>());
      expect(parseText('b = 2\n')['b'], '2');
    });

    test('a changed include key changes what counts as an include', () {
      final byDefault = FlatConfigResolverIncludes.parseStringWithIncludesSync(
        source,
        resolver: resolver,
        originId: 'mem:root',
      );
      final byOtherKey = FlatConfigResolverIncludes.parseStringWithIncludesSync(
        source,
        resolver: resolver,
        originId: 'mem:root',
        includeOptions: const FlatIncludeOptions(includeKey: 'source'),
      );

      expect(byDefault['path'], isNotNull);
      expect(byOtherKey['config-file'], 'theme.conf');
      expect(byOtherKey.lookup('path'), isA<FlatAbsent>());
    });
  });

  group('within one parse, a unit reached twice is resolved once', () {
    test('a diamond asks the resolver once per distinct unit', () {
      final resolver = _CountingResolver({
        'left.conf': 'config-file = shared.conf\nleft = yes\n',
        'right.conf': 'config-file = shared.conf\nright = yes\n',
        'shared.conf': 'shared = yes\n',
      });

      final doc = FlatConfigResolverIncludes.parseStringWithIncludesSync(
        'config-file = left.conf\nconfig-file = right.conf\n',
        resolver: resolver,
        originId: 'mem:root',
      );

      expect(doc['left'], 'yes');
      expect(doc['right'], 'yes');
      expect(doc['shared'], 'yes');

      // Both branches name shared.conf, and both are answered, but the second
      // one is served from the traversal rather than parsed again.
      expect(resolver.requested, [
        'left.conf',
        'shared.conf',
        'right.conf',
        'shared.conf',
      ]);
    });
  });

  group('a file edited between calls is picked up', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flatconfig_cache_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('the second parse reads the new content', () async {
      final shared = File('${tempDir.path}/shared.conf');
      await shared.writeAsString('theme = dark\n');

      final main = File('${tempDir.path}/main.conf');
      await main.writeAsString('config-file = shared.conf\n');

      expect((await main.parseWithIncludes())['theme'], 'dark');

      await shared.writeAsString('theme = light\n');

      expect((await main.parseWithIncludes())['theme'], 'light');
    });
  });
}
