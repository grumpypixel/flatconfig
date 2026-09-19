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
          options: FlatEnvOptions(prefix: const EnvPrefix.keep('APP_')),
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
          options: FlatEnvOptions(
            prefix: const EnvPrefix.keep('APP_'),
            caseSensitive: false,
          ),
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
            options: FlatEnvOptions(
              prefix: const EnvPrefix.keep('app_'),
              caseSensitive: false,
            ),
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
          options: FlatEnvOptions(prefix: const EnvPrefix.keep('APP_')),
        );

        expect(doc.isEmpty, isTrue);
      });

      test('no prefix takes every key', () {
        final env = {'HOST': 'localhost', 'PORT': '8080'};

        expect(FlatDocument.fromEnvironment(env).length, 2);
        expect(
          FlatDocument.fromEnvironment(env, options: FlatEnvOptions()).length,
          2,
        );
      });

      test('an empty prefix is refused rather than read as none', () {
        // There is one way to say "take everything", and it is to leave the
        // prefix unset. A literal empty one would be caught by the assertion
        // while compiling; computing it defers that to run time, where a
        // debug build asserts and a release build reaches checkUsable.
        final empty = String.fromCharCodes(const <int>[]);

        expect(
          () => FlatEnvOptions(prefix: EnvPrefix.keep(empty)),
          throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
        );
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
          options: FlatEnvOptions(interpolation: const EnvInterpolation()),
        );

        expect(doc['URL'], equals('https://api.example.com:8080'));
      });

      test('a missing variable is left in place by default', () {
        // 'https://:' looks like a URL and fails somewhere else entirely.
        // The unresolved placeholder points at the typo.
        final env = {'URL': 'https://\${HOST}:\${PORT}'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolation: const EnvInterpolation()),
        );

        expect(doc['URL'], equals('https://\${HOST}:\${PORT}'));
      });

      test('a missing variable can be emptied, the way a shell does', () {
        final env = {'URL': 'https://\${HOST}:\${PORT}'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            interpolation: const EnvInterpolation(
              onMissing: MissingVariablePolicy.empty,
            ),
          ),
        );

        expect(doc['URL'], equals('https://:'));
      });

      test('a missing variable can be an error naming it', () {
        final env = {'URL': 'https://\${HOST}/api'};

        expect(
          () => FlatDocument.fromEnvironment(
            env,
            options: FlatEnvOptions(
              interpolation: const EnvInterpolation(
                onMissing: MissingVariablePolicy.error,
              ),
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.invalidValue} ${e.message}',
              'names both sides',
              allOf(contains('HOST'), contains('URL')),
            ),
          ),
        );
      });

      test('handles multiple placeholders in same value', () {
        final env = {
          'FIRST': 'Hello',
          'SECOND': 'World',
          'GREETING': '\${FIRST} \${SECOND}!',
        };

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolation: const EnvInterpolation()),
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
          options: FlatEnvOptions(interpolation: const EnvInterpolation()),
        );

        expect(doc['MESSAGE'], equals('John and John went to the store'));
      });

      test('does not interpolate when interpolate is false', () {
        final env = {'HOST': 'localhost', 'URL': 'https://\${HOST}'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(),
        );

        expect(doc['URL'], equals('https://\${HOST}'));
      });

      test('skips interpolation on null values', () {
        final env = {'HOST': 'localhost'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            defaults: {'EMPTY': ''},
            interpolation: const EnvInterpolation(),
          ),
        );

        // Should not throw, just skip empty values
        expect(doc['EMPTY'], equals(''));
      });

      test('handles values without placeholders', () {
        final env = {'HOST': 'localhost', 'PORT': '8080'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(interpolation: const EnvInterpolation()),
        );

        expect(doc['HOST'], equals('localhost'));
        expect(doc['PORT'], equals('8080'));
      });

      test('interpolates from merged environment (defaults + env + merge)', () {
        final env = {'PORT': '8080'};

        final doc = FlatDocument.fromEnvironment(
          env,
          options: FlatEnvOptions(
            defaults: {'HOST': 'localhost'},
            merge: {'URL': 'http://\${HOST}:\${PORT}'},
            interpolation: const EnvInterpolation(),
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
        expect(
          () => FlatDocument.fromEnvironment({'KEY': 'a\nb'}),
          throwsA(
            isA<ArgumentError>().having(
              (e) => '${e.invalidValue} ${e.message}',
              'names the variable',
              allOf(contains('KEY'), contains('line break')),
            ),
          ),
        );
      });

      test('or skips it, keeping the rest', () {
        // A process whose environment carries a PEM key it never reads should
        // not be stopped by it.
        final doc = FlatDocument.fromEnvironment({
          'PEM': '-----BEGIN\nMII\n-----END',
          'PORT': '8080',
        }, options: FlatEnvOptions(multilineValue: MultilineValuePolicy.skip));

        expect(doc.containsKey('PEM'), isFalse);
        expect(doc['PORT'], '8080');
      });

      test('a skipped value cannot leak through interpolation', () {
        final doc = FlatDocument.fromEnvironment(
          {'PEM': 'a\nb', 'COPY': r'${PEM}'},
          options: FlatEnvOptions(
            multilineValue: MultilineValuePolicy.skip,
            interpolation: const EnvInterpolation(),
          ),
        );

        expect(doc.containsKey('PEM'), isFalse);
        expect(doc['COPY'], r'${PEM}');
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
          options: FlatEnvOptions(prefix: const EnvPrefix.keep('APP_')),
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
          options: FlatEnvOptions(interpolation: const EnvInterpolation()),
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
          options: FlatEnvOptions(interpolation: const EnvInterpolation()),
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
            interpolation: const EnvInterpolation(
              pattern: r'\$([A-Za-z0-9_]+)',
            ),
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
          options: FlatEnvOptions(
            prefix: const EnvPrefix.keep('APP_'),
            interpolation: const EnvInterpolation(),
          ),
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
          options: FlatEnvOptions(interpolation: const EnvInterpolation()),
        );

        expect(doc['API_BASE_URL'], equals('https://api.example.com:443/v1'));
        expect(doc['API_HEADERS'], equals('Authorization: Bearer secret123'));
      });
    });

    group('key transformation', () {
      test('a screaming prefix becomes ordinary configuration keys', () {
        final doc = FlatDocument.fromEnvironment(
          {
            'APP_WINDOW_WIDTH': '1280',
            'APP_WINDOW_HEIGHT': '720',
            'OTHER_VAR': 'ignored',
          },
          options: FlatEnvOptions(
            prefix: const EnvPrefix.strip('APP_'),
            lowercaseKeys: true,
            keys: const EnvKeySplit('_', joinWith: '.'),
          ),
        );

        expect(doc.toMap(), {'window.width': '1280', 'window.height': '720'});
      });

      test('keyJoinWith defaults to the key separator', () {
        final doc = FlatDocument.fromEnvironment({
          'A_B': '1',
        }, options: FlatEnvOptions(keys: const EnvKeySplit('_')));

        expect(doc.containsKey('A.B'), isTrue);
      });

      test('each step is independent of the others', () {
        const env = {'APP_A_B': '1'};

        expect(
          FlatDocument.fromEnvironment(
            env,
            options: FlatEnvOptions(prefix: const EnvPrefix.strip('APP_')),
          ).containsKey('A_B'),
          isTrue,
        );
        expect(
          FlatDocument.fromEnvironment(
            env,
            options: FlatEnvOptions(lowercaseKeys: true),
          ).containsKey('app_a_b'),
          isTrue,
        );
      });

      test('defaults and merge are rewritten too', () {
        // Otherwise a default could not override the variable it defaults for.
        final doc = FlatDocument.fromEnvironment(
          {'APP_PORT': '3000'},
          options: FlatEnvOptions(
            prefix: const EnvPrefix.strip('APP_'),
            lowercaseKeys: true,
            defaults: {'APP_HOST': 'localhost'},
            merge: {'APP_DEBUG': 'true'},
          ),
        );

        expect(doc.toMap(), {
          'host': 'localhost',
          'port': '3000',
          'debug': 'true',
        });
      });

      test('a placeholder names the variable, not the rewritten key', () {
        // The rewrite runs last, so \${APP_HOST} still resolves.
        final doc = FlatDocument.fromEnvironment(
          {'APP_HOST': 'example.com', 'APP_URL': r'https://${APP_HOST}/api'},
          options: FlatEnvOptions(
            prefix: const EnvPrefix.strip('APP_'),
            lowercaseKeys: true,
            interpolation: const EnvInterpolation(),
          ),
        );

        expect(doc['url'], 'https://example.com/api');
      });

      test('a join string that cannot appear in a key is rejected early', () {
        // At construction, before any variable is read: the option is wrong
        // whatever the environment happens to contain.
        expect(
          () => FlatEnvOptions(keys: const EnvKeySplit('_', joinWith: '=')),
          throwsArgumentError,
        );
      });

      test('a rewrite producing an invalid key names the variable', () {
        // Stripping the prefix off a variable that is nothing but the prefix
        // leaves an empty key. The options are fine here; this particular
        // variable is what cannot survive them, so the error says which.
        expect(
          () => FlatDocument.fromEnvironment({
            'APP_': '1',
          }, options: FlatEnvOptions(prefix: const EnvPrefix.strip('APP_'))),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'message',
              contains('APP_'),
            ),
          ),
        );
      });

      test('lowercasing can collide, and the later key wins', () {
        final doc = FlatDocument.fromEnvironment({
          'KEY': 'first',
          'key': 'second',
        }, options: FlatEnvOptions(lowercaseKeys: true));

        expect(doc['key'], 'second');
      });

      test('a prefix carries whether it is stripped', () {
        // Stripping without a prefix, and joining without splitting, used to
        // be writable and had to be answered with an ArgumentError. Both now
        // travel with the thing they depend on, so neither can be said.
        const env = {'APP_WINDOW_WIDTH': '640'};

        expect(
          FlatDocument.fromEnvironment(
            env,
            options: FlatEnvOptions(prefix: const EnvPrefix.keep('APP_')),
          ).keys,
          ['APP_WINDOW_WIDTH'],
        );
        expect(
          FlatDocument.fromEnvironment(
            env,
            options: FlatEnvOptions(prefix: const EnvPrefix.strip('APP_')),
          ).keys,
          ['WINDOW_WIDTH'],
        );
      });

      test(
        'a split key joins with the key separator unless told otherwise',
        () {
          const env = {'WINDOW_WIDTH': '640'};

          expect(
            FlatDocument.fromEnvironment(
              env,
              options: FlatEnvOptions(keys: const EnvKeySplit('_')),
            ).keys,
            ['WINDOW.WIDTH'],
          );
          expect(
            FlatDocument.fromEnvironment(
              env,
              options: FlatEnvOptions(
                keys: const EnvKeySplit('_', joinWith: '-'),
              ),
            ).keys,
            ['WINDOW-WIDTH'],
          );
        },
      );
    });
  });
}
