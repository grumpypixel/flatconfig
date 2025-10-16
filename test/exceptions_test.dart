import 'package:flatconfig/src/exceptions.dart';
import 'package:test/test.dart';

void main() {
  group('FlatParseException', () {
    test('UnterminatedQuoteException creates with correct message', () {
      final ex = UnterminatedQuoteException(5, 'key = "unclosed');
      expect(ex.lineNumber, 5);
      expect(ex.rawLine, 'key = "unclosed');
      expect(ex.message, contains('Unterminated quoted value'));
      expect(ex.message, contains('line 5'));
    });

    test('TrailingCharactersAfterQuoteException creates with correct message',
        () {
      final ex =
          TrailingCharactersAfterQuoteException(3, 'key = "value" extra');
      expect(ex.lineNumber, 3);
      expect(ex.rawLine, 'key = "value" extra');
      expect(ex.message, contains('Trailing characters after quoted value'));
      expect(ex.message, contains('line 3'));
    });

    test('MissingEqualsException creates with correct message', () {
      final ex = MissingEqualsException(2, 'just a key');
      expect(ex.lineNumber, 2);
      expect(ex.rawLine, 'just a key');
      expect(ex.message, contains("Missing '='"));
      expect(ex.message, contains('line 2'));
    });

    test('EmptyKeyException creates with correct message', () {
      final ex = EmptyKeyException(1, ' = value');
      expect(ex.lineNumber, 1);
      expect(ex.rawLine, ' = value');
      expect(ex.message, contains('Empty key'));
      expect(ex.message, contains('line 1'));
    });
  });

  group('ConfigIncludeException', () {
    test('creates with message and filePath', () {
      final ex = ConfigIncludeException('Test error', '/path/to/file.conf');
      expect(ex.message, 'Test error');
      expect(ex.filePath, '/path/to/file.conf');
      expect(ex.includePath, isNull);
    });

    test('creates with message, filePath and includePath', () {
      final ex = ConfigIncludeException(
        'Test error',
        '/path/to/file.conf',
        includePath: '/path/to/include.conf',
      );
      expect(ex.message, 'Test error');
      expect(ex.filePath, '/path/to/file.conf');
      expect(ex.includePath, '/path/to/include.conf');
    });
  });

  group('MaxIncludeDepthExceededException', () {
    test('creates with correct message and properties', () {
      final ex = MaxIncludeDepthExceededException('/path/to/file.conf', 5, 4);
      expect(ex.filePath, '/path/to/file.conf');
      expect(ex.depth, 5);
      expect(ex.maxDepth, 4);
      expect(ex.message, contains('Maximum include depth exceeded'));
      expect(ex.message, contains('depth=5'));
      expect(ex.message, contains('max=4'));
    });

    test('toString returns correct format', () {
      final ex = MaxIncludeDepthExceededException('/path', 3, 2);
      expect(
        ex.toString(),
        'MaxIncludeDepthExceededException: depth=3 (max=2) at "/path"',
      );
    });
  });

  group('CircularIncludeException', () {
    test('creates with correct message and properties', () {
      final ex = CircularIncludeException(
        '/path/to/main.conf',
        '/path/to/circular.conf',
      );
      expect(ex.includingFile, '/path/to/main.conf');
      expect(ex.canonicalPath, '/path/to/circular.conf');
      expect(ex.filePath, '/path/to/main.conf');
      expect(ex.includePath, '/path/to/circular.conf');
      expect(ex.message, contains('Circular include detected'));
      expect(ex.message, contains('/path/to/circular.conf'));
      expect(ex.message, contains('/path/to/main.conf'));
    });

    test('toString returns correct format', () {
      final ex = CircularIncludeException(
        '/path/to/main.conf',
        '/path/to/circular.conf',
      );
      expect(
        ex.toString(),
        'CircularIncludeException: cycle at "/path/to/circular.conf" (included by "/path/to/main.conf")',
      );
    });
  });

  group('MissingIncludeException', () {
    test('creates with correct message and properties', () {
      final ex = MissingIncludeException(
        '/path/to/main.conf',
        '/path/to/missing.conf',
      );
      expect(ex.includingFile, '/path/to/main.conf');
      expect(ex.missingPath, '/path/to/missing.conf');
      expect(ex.filePath, '/path/to/main.conf');
      expect(ex.includePath, '/path/to/missing.conf');
      expect(ex.message, contains('Required include file not found'));
      expect(ex.message, contains('/path/to/missing.conf'));
      expect(ex.message, contains('/path/to/main.conf'));
    });

    test('toString returns correct format', () {
      final ex = MissingIncludeException(
        '/path/to/main.conf',
        '/path/to/missing.conf',
      );
      expect(
        ex.toString(),
        'MissingIncludeException: "/path/to/missing.conf" (required by "/path/to/main.conf")',
      );
    });
  });

  group('FormatException extensions', () {
    test('copyWithMessage preserves source and offset', () {
      final original = FormatException('original', 'source', 10);
      final copy = original.copyWithMessage('new message');
      expect(copy.message, 'new message');
      expect(copy.source, 'source');
      expect(copy.offset, 10);
    });

    test('explain adds key context', () {
      final original = FormatException('Expected int', 'source', 5);
      final explained = original.explain(key: 'age', got: 'abc');
      expect(explained.message, 'Expected int for "age" (got: \'abc\')');
      expect(explained.source, 'source');
      expect(explained.offset, 5);
    });

    test('explain without got value', () {
      final original = FormatException('Missing key', 'source', 0);
      final explained = original.explain(key: 'required');
      expect(explained.message, 'Missing key for "required"');
    });
  });
}
