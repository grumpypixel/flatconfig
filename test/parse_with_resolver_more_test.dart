import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('parse_with_resolver additional cases', () {
    test('empty input yields empty document', () {
      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        '',
        resolver: MemoryIncludeResolver(const {}),
        originId: 'mem:root',
      );
      expect(doc.length, 0);
    });

    test('ignores empty include values', () {
      final text = [
        'config-file = ',
        'a = 1',
        'config-file =   ',
      ].join('\n');
      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: MemoryIncludeResolver(const {}),
        originId: 'mem:root',
      );
      expect(doc['a'], '1');
    });

    test('optional missing include is ignored, required throws', () {
      final textOpt = 'config-file = ?mem:missing\n';
      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        textOpt,
        resolver: MemoryIncludeResolver(const {}),
        originId: 'mem:root',
      );
      expect(doc.length, 0);

      final textReq = 'config-file = mem:missing\n';
      expect(
        () => FlatConfigResolverIncludes.parseStringWithIncludes(
          textReq,
          resolver: MemoryIncludeResolver(const {}),
          originId: 'mem:root',
        ),
        throwsA(isA<MissingIncludeException>()),
      );
    });

    test('quoted include with escapes resolves (Memory resolver)', () {
      final mem = MemoryIncludeResolver({
        r'mem:C:\X.conf': 'k = v\n',
      }, prefix: 'mem:');
      final text = 'config-file = "mem:C:\\X.conf"\n';
      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );
      expect(doc['k'], 'v');
    });

    test('cycle detection with same unit id', () {
      final mem = MemoryIncludeResolver({
        'mem:a': 'config-file = mem:b\n',
        'mem:b': 'config-file = mem:a\n',
      }, prefix: 'mem:');
      expect(
        () => FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = mem:a\n',
          resolver: mem,
          originId: 'mem:root',
        ),
        throwsA(isA<CircularIncludeException>()),
      );
    });

    test('pre-include entries kept; include overrides earlier keys', () {
      final mem = MemoryIncludeResolver({
        'mem:i': 'k = from-include\n',
      }, prefix: 'mem:');

      final text = [
        'k = before',
        'config-file = mem:i',
        'k = tail',
      ].join('\n');

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      expect(doc.valuesOf('k'), ['before', 'from-include']);
      expect(doc['k'], 'from-include');
    });

    test('unquoted backslashes in include path are decoded', () {
      // Test that unquoted backslashes in include paths are properly decoded
      // The text contains literal backslashes that should be unescaped
      final text = 'config-file = mem:C\\foo\\bar.conf\n';

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: MemoryIncludeResolver({
          // The path should match exactly what's in the text after unescaping
          'mem:C\\foo\\bar.conf': 'x = y\n',
        }, prefix: 'mem:'),
        originId: 'mem:root',
      );

      expect(doc['x'], 'y');
    });

    test('max include depth exceeded throws', () {
      final mem = MemoryIncludeResolver({
        'mem:a': 'k = v\n',
      }, prefix: 'mem:');

      expect(
        () => FlatConfigResolverIncludes.parseStringWithIncludes(
          'config-file = mem:a\n',
          resolver: mem,
          originId: 'mem:root',
          options: const FlatParseOptions(maxIncludeDepth: 0),
        ),
        throwsA(isA<MaxIncludeDepthExceededException>()),
      );
    });

    test('explicit cache hit returns cached document and skips parsing', () {
      final cache = <String, FlatDocument>{
        'mem:root': FlatDocument.single('cached', value: 'yes'),
      };

      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        'a = 1\n',
        resolver: MemoryIncludeResolver(const {}),
        originId: 'mem:root',
        cache: cache,
      );

      expect(doc['cached'], 'yes');
      expect(doc['a'], isNull);
    });

    test('quoted include path with quotes is properly unquoted', () {
      final mem = MemoryIncludeResolver({
        'mem:quoted path.conf': 'k = v\n',
      }, prefix: 'mem:');

      // Double quoted path - parser strips outer quotes, leaving inner quotes
      // This triggers line 175 in parse_with_resolver.dart
      final text = 'config-file = "\\"quoted path.conf\\""\n';
      final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
        text,
        resolver: mem,
        originId: 'mem:root',
        options: const FlatParseOptions(decodeEscapesInQuoted: true),
      );

      expect(doc['k'], 'v');
    });
  });
}
