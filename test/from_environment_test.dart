import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  group('FlatConfig.fromEnvironment', () {
    group('basic loading', () {
      test('loads simple env map into FlatDocument', () {
        final env = {'HOST': 'localhost', 'PORT': '8080', 'DEBUG': 'true'};

        final doc = FlatDocument.fromEnvironment(env);

        expect(doc['HOST'], equals('localhost'));
        expect(doc['PORT'], equals('8080'));
        expect(doc['DEBUG'], equals('true'));
        expect(doc.length, equals(3));
      });

      test('handles empty env map', () {
        final doc = FlatDocument.fromEnvironment({});

        expect(doc.isEmpty, isTrue);
        expect(doc.length, equals(0));
      });

      test('preserves key order', () {
        final env = {'ZULU': 'z', 'ALPHA': 'a', 'MIKE': 'm'};

        final doc = FlatDocument.fromEnvironment(env);
        final keys = doc.keys.toList();

        expect(keys, equals(['ZULU', 'ALPHA', 'MIKE']));
      });

      test('returns FlatDocument compatible with all APIs', () {
        final env = {'KEY1': 'value1', 'KEY2': 'value2'};
        final doc = FlatDocument.fromEnvironment(env);

        // Test that it works with standard FlatDocument methods
        expect(doc.toMap(), equals({'KEY1': 'value1', 'KEY2': 'value2'}));
        expect(doc.containsKey('KEY1'), isTrue);
        expect(doc.containsKey('KEY3'), isFalse);
        expect(doc['KEY1'], equals('value1'));
      });
    });

    group('prefix filtering', () {
      test('includes only keys starting with prefix (case-sensitive)', () {
        final env = {
          'APP_HOST': 'api.example.com',
          'APP_PORT': '8080',
          'DB_HOST': 'localhost',
          'OTHER': 'value',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(prefix: 'APP_'),
        );

        expect(
          doc.toMap(),
          equals({'APP_HOST': 'api.example.com', 'APP_PORT': '8080'}),
        );
      });

      test('includes keys with case-insensitive prefix matching', () {
        final env = {
          'app_host': 'localhost',
          'APP_PORT': '8080',
          'App_Debug': 'true',
          'OTHER': 'ignored',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(prefix: 'APP_', caseSensitive: false),
        );

        expect(
          doc.toMap(),
          equals({
            'app_host': 'localhost',
            'APP_PORT': '8080',
            'App_Debug': 'true',
          }),
        );
      });

      test(
        'preserves original key case even with case-insensitive matching',
        () {
          final env = {'aPp_HoSt': 'localhost', 'APP_PORT': '8080'};

          final doc = FlatDocument.fromEnvironment(
            env,
            options: FlatEnvOptions(prefix: 'app_', caseSensitive: false),
          );

          final keys = doc.keys.toList();
          expect(keys, contains('aPp_HoSt'));
          expect(keys, contains('APP_PORT'));
        },
      );

      test('returns empty document when no keys match prefix', () {
        final env = {'HOST': 'localhost', 'PORT': '8080'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(prefix: 'APP_'),
        );

        expect(doc.isEmpty, isTrue);
      });

      test('handles empty prefix as no filtering', () {
        final env = {'HOST': 'localhost', 'PORT': '8080'};

        final doc1 = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(prefix: ''),
        );
        final doc2 = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(prefix: null),
        );

        expect(doc1.length, equals(2));
        expect(doc2.length, equals(2));
      });
    });

    group('interpolation', () {
      test(r'replaces ${VAR} placeholders with values', () {
        final env = {
          'HOST': 'api.example.com',
          'PORT': '8080',
          'URL': 'https://\${HOST}:\${PORT}',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true),
        );

        expect(doc['URL'], equals('https://api.example.com:8080'));
      });

      test('replaces missing variables with empty string', () {
        final env = {'URL': 'https://\${HOST}:\${PORT}'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true),
        );

        expect(doc['URL'], equals('https://:'));
      });

      test('handles multiple placeholders in same value', () {
        final env = {
          'FIRST': 'Hello',
          'SECOND': 'World',
          'GREETING': '\${FIRST} \${SECOND}!',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true),
        );

        expect(doc['GREETING'], equals('Hello World!'));
      });

      test('handles same placeholder multiple times', () {
        final env = {
          'NAME': 'John',
          'MESSAGE': '\${NAME} and \${NAME} went to the store',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true),
        );

        expect(doc['MESSAGE'], equals('John and John went to the store'));
      });

      test('does not interpolate when interpolate is false', () {
        final env = {'HOST': 'localhost', 'URL': 'https://\${HOST}'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: false),
        );

        expect(doc['URL'], equals('https://\${HOST}'));
      });

      test('skips interpolation on null values', () {
        final env = {'HOST': 'localhost'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true, defaults: {'EMPTY': ''}),
        );

        // Should not throw, just skip empty values
        expect(doc['EMPTY'], equals(''));
      });

      test('handles values without placeholders', () {
        final env = {'HOST': 'localhost', 'PORT': '8080'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true),
        );

        expect(doc['HOST'], equals('localhost'));
        expect(doc['PORT'], equals('8080'));
      });

      test('interpolates from merged environment (defaults + env + merge)', () {
        final env = {'PORT': '8080'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            interpolate: true,
            defaults: {'HOST': 'localhost'},
            merge: {'URL': 'http://\${HOST}:\${PORT}'},
          ),
        );

        expect(doc['URL'], equals('http://localhost:8080'));
      });
    });

    group('precedence (defaults → env → merge)', () {
      test('env overrides defaults', () {
        final env = {'PORT': '3000'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            defaults: {'HOST': 'localhost', 'PORT': '8080'},
          ),
        );

        expect(doc['HOST'], equals('localhost')); // from defaults
        expect(doc['PORT'], equals('3000')); // from env (overrides default)
      });

      test('merge overrides both env and defaults', () {
        final env = {'PORT': '3000', 'DEBUG': 'false'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            defaults: {'HOST': 'localhost', 'PORT': '8080'},
            merge: {'PORT': '9000', 'ENV': 'prod'},
          ),
        );

        expect(doc['HOST'], equals('localhost')); // from defaults
        expect(doc['PORT'], equals('9000')); // from merge (overrides env)
        expect(doc['DEBUG'], equals('false')); // from env
        expect(doc['ENV'], equals('prod')); // from merge
      });

      test('handles empty defaults map', () {
        final env = {'KEY': 'value'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(defaults: {}),
        );

        expect(doc['KEY'], equals('value'));
      });

      test('handles empty merge map', () {
        final env = {'KEY': 'value'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(merge: {}),
        );

        expect(doc['KEY'], equals('value'));
      });

      test('applies all three sources correctly', () {
        final env = {'B': 'env-b'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            defaults: {'A': 'default-a', 'B': 'default-b', 'C': 'default-c'},
            merge: {'C': 'merge-c', 'D': 'merge-d'},
          ),
        );

        expect(doc['A'], equals('default-a')); // only in defaults
        expect(doc['B'], equals('env-b')); // env overrides default
        expect(doc['C'], equals('merge-c')); // merge overrides default
        expect(doc['D'], equals('merge-d')); // only in merge
      });
    });

    group('empty values', () {
      test('keeps empty string values when keepEmptyValues is true', () {
        final env = {'KEY1': 'value', 'KEY2': '', 'KEY3': 'another'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(keepEmptyValues: true),
        );

        expect(
          doc.toMap(),
          equals({'KEY1': 'value', 'KEY2': '', 'KEY3': 'another'}),
        );
      });

      test('drops empty string values when keepEmptyValues is false', () {
        final env = {'KEY1': 'value', 'KEY2': '', 'KEY3': 'another'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(keepEmptyValues: false),
        );

        expect(doc.toMap(), equals({'KEY1': 'value', 'KEY3': 'another'}));
      });

      test(
        'drops empty values from defaults and merge when keepEmptyValues is false',
        () {
          final env = {'B': ''};

          final doc = FlatDocument.fromEnvironment(
            env,
            options: FlatEnvOptions(
              keepEmptyValues: false,
              defaults: {'A': '', 'B': 'value'},
              merge: {'C': '', 'D': 'value'},
            ),
          );

          expect(doc.toMap(), equals({'D': 'value'}));
        },
      );

      test('treats whitespace as non-empty', () {
        final env = {'KEY1': ' ', 'KEY2': '\t'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(keepEmptyValues: false),
        );

        // Whitespace is not empty, so all keys are kept
        expect(doc.length, equals(2));
      });

      test('rejects a variable whose value contains a newline', () {
        // The format is line-based and cannot hold one. See Phase 2.10 for
        // whether the environment deserves a skip-instead-of-throw policy.
        expect(
          () => FlatDocument.fromEnvironment({'KEY': 'a\nb'}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('must not contain a line break'),
            ),
          ),
        );
      });
    });

    group('integration with FlatDocument extensions', () {
      test('works with stripPrefix() to remove prefix after loading', () {
        final env = {
          'APP_HOST': 'api.example.com',
          'APP_PORT': '8080',
          'APP_DEBUG': 'true',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(prefix: 'APP_'),
        );
        final clean = doc.stripPrefix('APP_');

        expect(
          clean.toMap(),
          equals({'HOST': 'api.example.com', 'PORT': '8080', 'DEBUG': 'true'}),
        );
      });

      test('works with collapse()', () {
        final env = {'KEY1': 'value1', 'KEY2': 'value2'};

        final doc = FlatDocument.fromEnvironment(env);
        final collapsed = doc.collapse();

        expect(collapsed['KEY1'], equals('value1'));
        expect(collapsed['KEY2'], equals('value2'));
      });

      test('works with concat()', () {
        final env1 = {'HOST': 'localhost'};
        final env2 = {'PORT': '8080'};

        final doc1 = FlatDocument.fromEnvironment(env1);
        final doc2 = FlatDocument.fromEnvironment(env2);
        final merged = doc1.concat(doc2);

        expect(merged.toMap(), equals({'HOST': 'localhost', 'PORT': '8080'}));
      });

      test('works with slice()', () {
        final env = {
          'APP_HOST': 'localhost',
          'APP_PORT': '8080',
          'DB_HOST': 'dbserver',
        };

        final doc = FlatDocument.fromEnvironment(env);
        final sliced = doc.slice('APP_');

        expect(
          sliced.toMap(),
          equals({'APP_HOST': 'localhost', 'APP_PORT': '8080'}),
        );
      });
    });

    group('edge cases', () {
      test('handles keys with special characters', () {
        final env = {
          'APP.HOST': 'localhost',
          'APP-PORT': '8080',
          'APP_DEBUG': 'true',
        };

        final doc = FlatDocument.fromEnvironment(env);

        expect(doc['APP.HOST'], equals('localhost'));
        expect(doc['APP-PORT'], equals('8080'));
        expect(doc['APP_DEBUG'], equals('true'));
      });

      test('handles values with special characters', () {
        final env = {
          'PATH': '/usr/bin:/usr/local/bin',
          'SPECIAL': 'value with = sign',
          'QUOTED': '"quoted value"',
        };

        final doc = FlatDocument.fromEnvironment(env);

        expect(doc['PATH'], equals('/usr/bin:/usr/local/bin'));
        expect(doc['SPECIAL'], equals('value with = sign'));
        expect(doc['QUOTED'], equals('"quoted value"'));
      });

      test('handles large number of keys', () {
        final env = <String, String>{};
        for (var i = 0; i < 1000; i++) {
          env['KEY_$i'] = 'value_$i';
        }

        final doc = FlatDocument.fromEnvironment(env);

        expect(doc.length, equals(1000));
        expect(doc['KEY_0'], equals('value_0'));
        expect(doc['KEY_999'], equals('value_999'));
      });

      test('handles Unicode characters', () {
        final env = {'GREETING': 'Hello 世界 🌍', 'EMOJI': '🚀💻🎉'};

        final doc = FlatDocument.fromEnvironment(env);

        expect(doc['GREETING'], equals('Hello 世界 🌍'));
        expect(doc['EMOJI'], equals('🚀💻🎉'));
      });

      test('handles circular reference in interpolation (no recursion)', () {
        // Single-pass interpolation means circular refs just produce
        // the placeholder text of the other variable
        final env = {'A': '\${B}', 'B': '\${A}'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true),
        );

        // A becomes the literal string "${A}" (from B's value)
        // B becomes the literal string "${B}" (from A's value)
        expect(doc['A'], equals('\${A}'));
        expect(doc['B'], equals('\${B}'));
      });

      test('handles malformed placeholder patterns', () {
        final env = {
          'HOST': 'localhost',
          'BAD1': '\${',
          'BAD2': '\${}',
          'BAD3': '\${HOST',
          'BAD4': 'HOST}',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true),
        );

        // These don't match the pattern, so they're kept as-is
        expect(doc['BAD1'], equals('\${'));
        expect(doc['BAD2'], equals('\${}'));
        expect(doc['BAD3'], equals('\${HOST'));
        expect(doc['BAD4'], equals('HOST}'));
      });

      test('custom varPattern works', () {
        final env = {'HOST': 'localhost', 'URL': '\$HOST/api'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            interpolate: true,
            varPattern: r'\$([A-Za-z0-9_]+)',
          ),
        );

        expect(doc['URL'], equals('localhost/api'));
      });
    });

    group('realistic scenarios', () {
      test('loading app configuration with prefix and stripPrefix', () {
        final env = {
          'APP_HOST': 'api.example.com',
          'APP_PORT': '8080',
          'APP_URL': 'https://\${APP_HOST}:\${APP_PORT}',
          'OTHER_VAR': 'ignored',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(prefix: 'APP_', interpolate: true),
        );
        final clean = doc.stripPrefix('APP_');

        expect(clean['HOST'], equals('api.example.com'));
        expect(clean['PORT'], equals('8080'));
        expect(clean['URL'], equals('https://api.example.com:8080'));
        expect(clean.containsKey('OTHER_VAR'), isFalse);
      });

      test('layering defaults, env, and overrides', () {
        final env = {'HOST': 'prod.example.com', 'PORT': '8080'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            defaults: {
              'HOST': 'localhost',
              'PORT': '3000',
              'DEBUG': 'true',
              'LOG_LEVEL': 'info',
            },
            merge: {'ENV': 'production', 'DEBUG': 'false'},
          ),
        );

        expect(doc['HOST'], equals('prod.example.com')); // from env
        expect(doc['PORT'], equals('8080')); // from env
        expect(doc['DEBUG'], equals('false')); // from merge
        expect(doc['LOG_LEVEL'], equals('info')); // from defaults
        expect(doc['ENV'], equals('production')); // from merge
      });

      test('combining multiple environment sources', () {
        // Simulate loading from multiple sources
        final systemEnv = {'HOME': '/home/user', 'SHELL': '/bin/bash'};
        final dotEnv = {'APP_HOST': 'localhost', 'APP_PORT': '3000'};
        final testOverrides = {'APP_PORT': '9999'};

        final doc1 = FlatDocument.fromEnvironment(systemEnv);
        final doc2 = FlatDocument.fromEnvironment(dotEnv);
        final doc3 = FlatDocument.fromEnvironment(testOverrides);

        final combined = doc1.concat(doc2).concat(doc3);

        expect(combined['HOME'], equals('/home/user'));
        expect(combined['SHELL'], equals('/bin/bash'));
        expect(combined['APP_HOST'], equals('localhost'));
        expect(combined['APP_PORT'], equals('9999')); // overridden
      });

      test('Flutter-style .env loading with interpolation', () {
        final env = {
          'API_KEY': 'secret123',
          'API_HOST': 'api.example.com',
          'API_PORT': '443',
          'API_BASE_URL': 'https://\${API_HOST}:\${API_PORT}/v1',
          'API_HEADERS': 'Authorization: Bearer \${API_KEY}',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolate: true),
        );

        expect(doc['API_BASE_URL'], equals('https://api.example.com:443/v1'));
        expect(doc['API_HEADERS'], equals('Authorization: Bearer secret123'));
      });
    });
  });
}
