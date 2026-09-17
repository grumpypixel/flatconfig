import 'package:flatconfig/flatconfig_includes.dart';
import 'package:test/test.dart';

void main() {
  group('parse_with_resolver additional cases', () {
    test('empty input yields empty document', () {
      final doc = parseWithIncludesSync(
        '',
        resolver: MemoryIncludeResolver(const {}),
        originId: 'mem:root',
      );
      expect(doc.length, 0);
    });

    test('ignores empty include values', () {
      final text = ['config-file = ', 'a = 1', 'config-file =   '].join('\n');
      final doc = parseWithIncludesSync(
        text,
        resolver: MemoryIncludeResolver(const {}),
        originId: 'mem:root',
      );
      expect(doc['a'], '1');
    });

    test('optional missing include is ignored, required throws', () {
      final textOpt = 'config-file = ?mem:missing\n';
      final doc = parseWithIncludesSync(
        textOpt,
        resolver: MemoryIncludeResolver(const {}),
        originId: 'mem:root',
      );
      expect(doc.length, 0);

      final textReq = 'config-file = mem:missing\n';
      expect(
        () => parseWithIncludesSync(
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
      final doc = parseWithIncludesSync(
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
        () => parseWithIncludesSync(
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

      final text = ['k = before', 'config-file = mem:i', 'k = tail'].join('\n');

      final doc = parseWithIncludesSync(
        text,
        resolver: mem,
        originId: 'mem:root',
      );

      expect(doc.allValues('k'), ['before', 'from-include']);
      expect(doc['k'], 'from-include');
    });

    test('unquoted backslashes in include path are decoded', () {
      // Test that unquoted backslashes in include paths are properly decoded
      // The text contains literal backslashes that should be unescaped
      final text = 'config-file = mem:C\\foo\\bar.conf\n';

      final doc = parseWithIncludesSync(
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
      final mem = MemoryIncludeResolver({'mem:a': 'k = v\n'}, prefix: 'mem:');

      expect(
        () => parseWithIncludesSync(
          'config-file = mem:a\n',
          resolver: mem,
          originId: 'mem:root',
          includeOptions: const FlatIncludeOptions(maxIncludeDepth: 0),
        ),
        throwsA(isA<MaxIncludeDepthExceededException>()),
      );
    });

    test('a name that really contains quotes keeps them', () {
      // The parser removes the outer layer and decodes \" to ", so the value
      // is a filename whose first and last characters are quotes. Stripping
      // those too asked for a different file, and this test used to expect it.
      final mem = MemoryIncludeResolver({
        'mem:"quoted path.conf"': 'k = v\n',
      }, prefix: 'mem:');

      final doc = parseWithIncludesSync(
        'config-file = "\\"quoted path.conf\\""\n',
        resolver: mem,
        originId: 'mem:root',
        options: const FlatParseOptions(decodeEscapesInQuoted: true),
      );

      expect(doc['k'], 'v');
    });

    test('the optional marker does not change which file is named', () {
      // With the marker the parser sees no quoted value at all, so the quotes
      // are this layer's to remove. Both spellings must still name one file.
      final mem = MemoryIncludeResolver({
        'mem:quoted path.conf': 'k = v\n',
      }, prefix: 'mem:');

      for (final directive in const [
        'config-file = "quoted path.conf"',
        'config-file = ?"quoted path.conf"',
      ]) {
        expect(
          parseWithIncludesSync(
            '$directive\n',
            resolver: mem,
            originId: 'mem:root',
          )['k'],
          'v',
          reason: directive,
        );
      }
    });
  });
}
