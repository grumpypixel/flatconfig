import 'package:flatconfig/src/exceptions.dart';
import 'package:flatconfig/src/issue.dart';
import 'package:test/test.dart';

void main() {
  group('FlatParseException', () {
    // One type carrying the issue, so the message, the line, the column and
    // the kind all come from the same place the lenient path reports.
    const cases = <FlatIssueKind, String>{
      FlatIssueKind.unterminatedQuote: 'key = "unclosed',
      FlatIssueKind.trailingAfterQuote: 'key = "value" extra',
      FlatIssueKind.missingEquals: 'just a key',
      FlatIssueKind.emptyKey: ' = value',
      FlatIssueKind.invalidKey: 'a"b = v',
    };

    var line = 1;
    cases.forEach((kind, raw) {
      final at = line++;

      test('it reports a ${kind.name} where the issue says', () {
        final issue = FlatIssue(kind: kind, line: at, column: 7, rawLine: raw);
        final ex = FlatParseException(issue);

        expect(ex.kind, kind);
        expect(ex.issue, issue);
        expect(ex.lineNumber, at);
        expect(ex.rawLine, raw);
        expect(ex.message, contains(issue.message));
        expect(ex.message, contains('line $at'));
        // FormatException counts from zero, the displayed column from one.
        expect(ex.offset, 6);
        expect(ex.source, raw);
      });
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
