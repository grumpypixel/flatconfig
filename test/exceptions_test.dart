// test/exceptions_test.dart

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
