import 'dart:convert';
import 'package:flatconfig/src/options.dart';
import 'package:test/test.dart';

void main() {
  group('Options copyWith coverage', () {
    test('FlatStreamWriteOptions.copyWith fallback and overrides', () {
      const original = FlatStreamWriteOptions(
        encoding: utf8,
        lineTerminator: '\n',
        ensureTrailingNewline: false,
      );

      // Test fallback behavior
      final copy1 = original.copyWith();
      expect(copy1.encoding, utf8);
      expect(copy1.lineTerminator, '\n');
      expect(copy1.ensureTrailingNewline, false);

      // Test overrides
      final copy2 = original.copyWith(
        encoding: latin1,
        lineTerminator: '\r\n',
        ensureTrailingNewline: true,
      );
      expect(copy2.encoding, latin1);
      expect(copy2.lineTerminator, '\r\n');
      expect(copy2.ensureTrailingNewline, true);

      // Test partial overrides
      final copy3 = original.copyWith(encoding: latin1);
      expect(copy3.encoding, latin1);
      expect(copy3.lineTerminator, '\n'); // unchanged
      expect(copy3.ensureTrailingNewline, false); // unchanged
    });

    test('FlatEncodeOptions.copyWith fallback and overrides', () {
      const original = FlatEncodeOptions(
        escapeQuoted: false,
        quoteIfWhitespace: true,
        alwaysQuote: false,
        commentPrefix: '#',
      );

      // Test fallback behavior
      final copy1 = original.copyWith();
      expect(copy1.escapeQuoted, false);
      expect(copy1.quoteIfWhitespace, true);
      expect(copy1.alwaysQuote, false);
      expect(copy1.commentPrefix, '#');

      // Test overrides
      final copy2 = original.copyWith(
        escapeQuoted: true,
        quoteIfWhitespace: false,
        alwaysQuote: true,
        commentPrefix: ';',
      );
      expect(copy2.escapeQuoted, true);
      expect(copy2.quoteIfWhitespace, false);
      expect(copy2.alwaysQuote, true);
      expect(copy2.commentPrefix, ';');

      // Test partial overrides
      final copy3 = original.copyWith(escapeQuoted: true);
      expect(copy3.escapeQuoted, true);
      expect(copy3.quoteIfWhitespace, true); // unchanged
      expect(copy3.alwaysQuote, false); // unchanged
      expect(copy3.commentPrefix, '#'); // unchanged
    });
  });
}
