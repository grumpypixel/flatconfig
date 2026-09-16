import 'dart:convert';
import 'package:flatconfig/src/options.dart';
import 'package:test/test.dart';

void main() {
  group('Options copyWith coverage', () {
    test('FlatStreamWriteOptions.copyWith fallback and overrides', () {
      const original = FlatStreamWriteOptions(
        encoding: utf8,
        lineTerminator: '\n',
      );

      // Test fallback behavior
      final copy1 = original.copyWith();
      expect(copy1.encoding, utf8);
      expect(copy1.lineTerminator, '\n');

      // Test overrides
      final copy2 = original.copyWith(encoding: latin1, lineTerminator: '\r\n');
      expect(copy2.encoding, latin1);
      expect(copy2.lineTerminator, '\r\n');

      // Test partial overrides
      final copy3 = original.copyWith(encoding: latin1);
      expect(copy3.encoding, latin1);
      expect(copy3.lineTerminator, '\n'); // unchanged
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

    test('FlatEnvOptions.copyWith fallback and overrides', () {
      const original = FlatEnvOptions(
        prefix: 'APP_',
        caseSensitive: true,
        interpolate: true,
        keepEmptyValues: true,
        varPattern: r'\$\{([A-Za-z0-9_]+)\}',
        defaults: {'DEFAULT': 'value'},
        merge: {'MERGE': 'value'},
      );

      // Test fallback behavior
      final copy1 = original.copyWith();
      expect(copy1.prefix, 'APP_');
      expect(copy1.caseSensitive, true);
      expect(copy1.interpolate, true);
      expect(copy1.keepEmptyValues, true);
      expect(copy1.varPattern, r'\$\{([A-Za-z0-9_]+)\}');
      expect(copy1.defaults, {'DEFAULT': 'value'});
      expect(copy1.merge, {'MERGE': 'value'});

      // Test overrides
      final copy2 = original.copyWith(
        prefix: 'DB_',
        caseSensitive: false,
        interpolate: false,
        keepEmptyValues: false,
        varPattern: r'\$([A-Z_]+)',
        defaults: {'NEW_DEFAULT': 'new'},
        merge: {'NEW_MERGE': 'new'},
      );
      expect(copy2.prefix, 'DB_');
      expect(copy2.caseSensitive, false);
      expect(copy2.interpolate, false);
      expect(copy2.keepEmptyValues, false);
      expect(copy2.varPattern, r'\$([A-Z_]+)');
      expect(copy2.defaults, {'NEW_DEFAULT': 'new'});
      expect(copy2.merge, {'NEW_MERGE': 'new'});

      // Test partial overrides
      final copy3 = original.copyWith(prefix: 'SYS_');
      expect(copy3.prefix, 'SYS_');
      expect(copy3.caseSensitive, true); // unchanged
      expect(copy3.interpolate, true); // unchanged
      expect(copy3.keepEmptyValues, true); // unchanged
      expect(copy3.varPattern, r'\$\{([A-Za-z0-9_]+)\}'); // unchanged
      expect(copy3.defaults, {'DEFAULT': 'value'}); // unchanged
      expect(copy3.merge, {'MERGE': 'value'}); // unchanged

      // Test empty defaults/merge
      final copy5 = original.copyWith(defaults: {}, merge: {});
      expect(copy5.defaults, <String, String>{});
      expect(copy5.merge, <String, String>{});
    });

    test('FlatEnvOptions default constructor values', () {
      const options = FlatEnvOptions();

      expect(options.prefix, null);
      expect(options.caseSensitive, true);
      expect(options.interpolate, true);
      expect(options.keepEmptyValues, true);
      expect(options.varPattern, r'\$\{([A-Za-z0-9_]+)\}');
      expect(options.defaults, const <String, String>{});
      expect(options.merge, const <String, String>{});
    });

    test('FlatEnvOptions custom constructor values', () {
      const options = FlatEnvOptions(
        prefix: 'TEST_',
        caseSensitive: false,
        interpolate: false,
        keepEmptyValues: false,
        varPattern: r'\$([A-Z]+)',
        defaults: {'A': '1'},
        merge: {'B': '2'},
      );

      expect(options.prefix, 'TEST_');
      expect(options.caseSensitive, false);
      expect(options.interpolate, false);
      expect(options.keepEmptyValues, false);
      expect(options.varPattern, r'\$([A-Z]+)');
      expect(options.defaults, {'A': '1'});
      expect(options.merge, {'B': '2'});
    });
  });
}
