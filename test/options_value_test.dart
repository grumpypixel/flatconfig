import 'dart:convert';
import 'dart:io';

import 'package:flatconfig/flatconfig_io.dart';
import 'package:test/test.dart';

/// Tests for the options classes as value types.
///
/// They used to be bags of fields: `copyWith` could not clear a nullable one,
/// two identical configurations compared unequal, printing one said
/// `Instance of 'FlatEnvOptions'`, and the two maps stayed owned by the caller.

void main() {
  group('copyWith can clear a nullable field, not just set it', () {
    test('onIssue survives an unrelated copyWith', () {
      void handler(FlatIssue _) {}
      final base = FlatParseOptions(onIssue: handler);

      expect(base.copyWith(strict: true).onIssue, same(handler));
    });

    test('passing null clears it', () {
      // `onIssue ?? this.onIssue` could not express this: null meant "absent".
      final base = FlatParseOptions(onIssue: (_) {});

      expect(base.copyWith(onIssue: null).onIssue, isNull);
    });

    test('the same holds for FlatEnvOptions.prefix', () {
      final base = FlatEnvOptions(prefix: 'APP_');

      expect(base.copyWith(caseSensitive: false).prefix, 'APP_');
      expect(base.copyWith(prefix: null).prefix, isNull);
      expect(base.copyWith(prefix: 'OTHER_').prefix, 'OTHER_');
    });

    test('a handler lambda still infers its argument type', () {
      // The sentinel has to keep the parameter's function type, or this stops
      // compiling and every caller has to write (FlatIssue i).
      final copied = const FlatParseOptions().copyWith(
        onIssue: (i) => expect(i.line, greaterThanOrEqualTo(0)),
      );

      expect(copied.onIssue, isNotNull);
    });
  });

  group('options hold their own copy of what they were given', () {
    test('mutating the caller\'s map does not change the options', () {
      final defaults = {'HOST': 'localhost'};
      final options = FlatEnvOptions(defaults: defaults);

      defaults['HOST'] = 'changed';
      defaults['EXTRA'] = 'new';

      expect(options.defaults, {'HOST': 'localhost'});
    });

    test('the exposed maps are unmodifiable', () {
      final options = FlatEnvOptions(defaults: {'A': '1'}, merge: {'B': '2'});

      expect(() => options.defaults['C'] = '3', throwsUnsupportedError);
      expect(() => options.merge.clear(), throwsUnsupportedError);
    });
  });

  group('equality', () {
    test('two identically configured options are equal', () {
      expect(
        const FlatParseOptions(strict: true),
        const FlatParseOptions(strict: true),
      );
      expect(
        const FlatEncodeOptions(alwaysQuote: true),
        const FlatEncodeOptions(alwaysQuote: true),
      );
      expect(const FlatStreamReadOptions(), const FlatStreamReadOptions());
      expect(
        const FlatIncludeOptions(includeKey: 'source'),
        const FlatIncludeOptions(includeKey: 'source'),
      );
      expect(
        const FlatStreamWriteOptions(lineTerminator: '\r\n'),
        const FlatStreamWriteOptions(lineTerminator: '\r\n'),
      );
      expect(FlatEnvOptions(prefix: 'A_'), FlatEnvOptions(prefix: 'A_'));
    });

    test('one differing field is enough to be unequal', () {
      expect(
        const FlatParseOptions(strict: true),
        isNot(const FlatParseOptions()),
      );
      expect(
        FlatEnvOptions(defaults: {'A': '1'}),
        isNot(FlatEnvOptions(defaults: {'A': '2'})),
      );
    });

    test('map contents count, not map identity or order', () {
      final a = FlatEnvOptions(defaults: {'A': '1', 'B': '2'});
      final b = FlatEnvOptions(defaults: {'B': '2', 'A': '1'});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equal options hash equally', () {
      expect(
        const FlatParseOptions(commentPrefix: ';').hashCode,
        const FlatParseOptions(commentPrefix: ';').hashCode,
      );
    });

    test('copyWith with no arguments returns an equal object', () {
      const base = FlatParseOptions(strict: true, commentPrefix: ';');
      expect(base.copyWith(), base);

      const include = FlatIncludeOptions(includeKey: 'source');
      expect(include.copyWith(), include);
      expect(include.copyWith(maxIncludeDepth: 1).includeKey, 'source');
    });
  });

  group('include settings are separate from parse settings', () {
    test('FlatParseOptions no longer carries them', () {
      // Passing includeKey to FlatDocument.parse suggested that parsing a
      // string might follow an include. It never did.
      const text = 'config-file = other.conf\nk = v\n';
      final doc = FlatDocument.parse(text);

      expect(doc['config-file'], 'other.conf');
      expect(doc.length, 2);
    });

    test('the two travel together through an include entry point', () {
      final dir = Directory.systemTemp.createTempSync('flatconfig_split');
      addTearDown(() => dir.deleteSync(recursive: true));

      File('${dir.path}/theme.conf').writeAsStringSync('color = red\n');
      File('${dir.path}/main.conf').writeAsStringSync(
        '; a comment in another dialect\n'
        'source = theme.conf\n',
      );

      final doc = File('${dir.path}/main.conf').parseWithIncludesSync(
        options: const FlatParseOptions(commentPrefix: ';'),
        includeOptions: const FlatIncludeOptions(includeKey: 'source'),
      );

      expect(doc['color'], 'red');
    });
  });

  group('toString says what is configured', () {
    test('the fields appear, not the instance address', () {
      final text = const FlatParseOptions(strict: true).toString();

      expect(text, contains('strict: true'));
      expect(text, isNot(contains('Instance of')));
    });

    test('a line terminator is shown escaped, so CRLF is readable', () {
      expect(
        const FlatStreamWriteOptions(lineTerminator: '\r\n').toString(),
        contains(jsonEncode('\r\n')),
      );
    });

    test('a handler is reported as present without being called', () {
      var called = false;
      final text = FlatParseOptions(onIssue: (_) => called = true).toString();

      expect(text, contains('onIssue: set'));
      expect(called, isFalse);
    });

    test('maps are summarised by size rather than dumped', () {
      final text = FlatEnvOptions(defaults: {'A': '1', 'B': '2'}).toString();

      expect(text, contains('2 entries'));
    });
  });

  group('invalid configurations are rejected where they are written', () {
    test('a negative include depth cannot survive to be used', () {
      // The assert makes `const FlatIncludeOptions(maxIncludeDepth: -1)` a
      // compile error, but a release build drops asserts, so a computed value
      // has to be caught where it is read instead.
      final options = () {
        try {
          return FlatIncludeOptions(maxIncludeDepth: -1);
        } on AssertionError {
          return null; // debug build: the assert already stopped it
        }
      }();

      if (options == null) {
        return;
      }

      expect(
        () =>
            File('unused.conf').parseWithIncludesSync(includeOptions: options),
        throwsArgumentError,
      );
    });

    test('depth zero is allowed and means no includes', () {
      expect(const FlatIncludeOptions(maxIncludeDepth: 0).maxIncludeDepth, 0);
    });

    test('an empty comment prefix is allowed and means no comments', () {
      const source = '# k = v';
      final kinds = <FlatIssueKind>[];

      // With a prefix the line is a comment and raises nothing. Without one it
      // is data, and SPEC 3 then rejects a key beginning with '#'.
      FlatDocument.parse(
        source,
        options: FlatParseOptions(onIssue: (i) => kinds.add(i.kind)),
      );
      expect(kinds, isEmpty);

      FlatDocument.parse(
        source,
        options: FlatParseOptions(
          commentPrefix: '',
          onIssue: (i) => kinds.add(i.kind),
        ),
      );
      expect(kinds, [FlatIssueKind.invalidKey]);
    });

    test('a varPattern that is not a regex is rejected', () {
      expect(
        () => FlatEnvOptions(varPattern: r'([unclosed'),
        throwsArgumentError,
      );
    });

    test('a varPattern with no capture group is rejected', () {
      expect(() => FlatEnvOptions(varPattern: r'\$\w+'), throwsArgumentError);
    });

    test(
      'an empty prefix is normalised to none, not kept as a second spelling',
      () {
        expect(FlatEnvOptions(prefix: '').prefix, isNull);
        expect(FlatEnvOptions(prefix: ''), FlatEnvOptions());
      },
    );

    test('an empty keySplitOn is rejected rather than normalised', () {
      // Unlike the prefix, there is no sensible reading of "split on nothing":
      // it would produce one empty segment per character.
      expect(() => FlatEnvOptions(keySplitOn: ''), throwsArgumentError);
    });
  });
}
