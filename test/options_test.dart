import 'package:flatconfig/src/options.dart';
import 'package:test/test.dart';

void main() {
  group('Options copyWith coverage', () {
    test('FlatEnvOptions default constructor values', () {
      final options = FlatEnvOptions();

      expect(options.prefix, null);
      expect(options.caseSensitive, true);
      expect(options.interpolation, null);
      expect(options.multilineValue, MultilineValuePolicy.error);
      expect(options.keepEmptyValues, true);
      expect(options.keys, null);
      expect(options.lowercaseKeys, false);
      expect(options.defaults, const <String, String>{});
      expect(options.merge, const <String, String>{});
    });

    test('EnvInterpolation default values', () {
      const interpolation = EnvInterpolation();

      expect(interpolation.pattern, r'\$\{([A-Za-z0-9_]+)\}');
      expect(interpolation.pattern, EnvInterpolation.defaultPattern);
      expect(interpolation.onMissing, MissingVariablePolicy.preserve);
    });

    test('EnvKeySplit joins with the key separator by default', () {
      expect(const EnvKeySplit('_').joinWith, null);
      expect(const EnvKeySplit('_').joiner, '.');
      expect(const EnvKeySplit('_', joinWith: '-').joiner, '-');
    });

    test('EnvPrefix carries whether the prefix is stripped', () {
      expect(const EnvPrefix.keep('APP_').strip, false);
      expect(const EnvPrefix.strip('APP_').strip, true);
      expect(const EnvPrefix.keep('APP_').value, 'APP_');
    });

    test('FlatEnvOptions custom constructor values', () {
      final options = FlatEnvOptions(
        prefix: const EnvPrefix.keep('TEST_'),
        caseSensitive: false,
        keepEmptyValues: false,
        defaults: {'A': '1'},
        merge: {'B': '2'},
        interpolation: const EnvInterpolation(pattern: r'\$([A-Z]+)'),
      );

      expect(options.prefix, const EnvPrefix.keep('TEST_'));
      expect(options.caseSensitive, false);
      expect(options.keepEmptyValues, false);
      expect(options.interpolation?.pattern, r'\$([A-Z]+)');
      expect(options.defaults, {'A': '1'});
      expect(options.merge, {'B': '2'});
    });
  });
}
