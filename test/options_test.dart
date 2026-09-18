import 'package:flatconfig/src/options.dart';
import 'package:test/test.dart';

void main() {
  group('Options copyWith coverage', () {
    test('FlatEnvOptions default constructor values', () {
      final options = FlatEnvOptions();

      expect(options.prefix, null);
      expect(options.caseSensitive, true);
      expect(options.interpolate, false);
      expect(options.missingVariable, MissingVariablePolicy.preserve);
      expect(options.multilineValue, MultilineValuePolicy.error);
      expect(options.keepEmptyValues, true);
      expect(options.varPattern, r'\$\{([A-Za-z0-9_]+)\}');
      expect(options.stripMatchedPrefix, false);
      expect(options.keySplitOn, null);
      expect(options.keyJoinWith, null);
      expect(options.lowercaseKeys, false);
      expect(options.defaults, const <String, String>{});
      expect(options.merge, const <String, String>{});
    });

    test('FlatEnvOptions custom constructor values', () {
      final options = FlatEnvOptions(
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
