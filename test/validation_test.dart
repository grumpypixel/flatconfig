import 'package:flatconfig/src/validation.dart';
import 'package:test/test.dart';

/// What a rejected argument says about itself.
///
/// Asserting only that an [ArgumentError] is thrown leaves all three of its
/// fields unchecked. `ArgumentError.value` takes the value, then the name,
/// then the message, and any other order compiles: the caller then reads
/// "Invalid argument (Must not be negative): maxIncludes", which names the
/// limit as the complaint and the complaint as the limit.
Matcher throwsArgumentErrorWith({
  required Object? value,
  required String name,
  required String message,
}) => throwsA(
  isA<ArgumentError>()
      .having((e) => e.invalidValue, 'invalidValue', value)
      .having((e) => e.name, 'name', name)
      .having((e) => e.message, 'message', message),
);

void main() {
  group('checkSingleCharacter', () {
    test('it names the value, the argument and the rule', () {
      expect(
        () => checkSingleCharacter('ab', 'listSeparator'),
        throwsArgumentErrorWith(
          value: 'ab',
          name: 'listSeparator',
          message: 'Must be a single character',
        ),
      );
    });

    test('an empty string is not one character either', () {
      expect(
        () => checkSingleCharacter('', 'listSeparator'),
        throwsArgumentErrorWith(
          value: '',
          name: 'listSeparator',
          message: 'Must be a single character',
        ),
      );
    });

    test('exactly one character passes', () {
      expect(() => checkSingleCharacter(',', 'listSeparator'), returnsNormally);
    });
  });

  group('checkNonNegative', () {
    test('it names the value, the argument and the rule', () {
      expect(
        () => checkNonNegative(-1, 'maxIncludes'),
        throwsArgumentErrorWith(
          value: -1,
          name: 'maxIncludes',
          message: 'Must not be negative',
        ),
      );
    });

    test('zero is not negative', () {
      expect(() => checkNonNegative(0, 'maxIncludes'), returnsNormally);
    });
  });

  group('checkKey', () {
    test('the message carries the reason the key was refused', () {
      expect(
        () => checkKey('a=b'),
        throwsArgumentErrorWith(
          value: 'a=b',
          name: 'key',
          message: "Key must not contain '='",
        ),
      );
    });

    test('the caller may name the argument', () {
      expect(
        () => checkKey('', 'includeKey'),
        throwsArgumentErrorWith(
          value: '',
          name: 'includeKey',
          message: 'Key must not be empty',
        ),
      );
    });

    test('a valid key passes', () {
      expect(() => checkKey('theme'), returnsNormally);
    });
  });

  group('checkKeyAgainstCommentPrefix', () {
    test('it names the prefix the key collides with', () {
      expect(
        () => checkKeyAgainstCommentPrefix(';secret', ';'),
        throwsArgumentErrorWith(
          value: ';secret',
          name: 'key',
          message: "Key must not begin with the comment prefix ';'",
        ),
      );
    });

    test('an empty prefix disables the check', () {
      expect(
        () => checkKeyAgainstCommentPrefix(';secret', ''),
        returnsNormally,
      );
    });

    test('a key that merely contains the prefix passes', () {
      expect(() => checkKeyAgainstCommentPrefix('a;b', ';'), returnsNormally);
    });
  });

  group('checkCommentPrefix', () {
    test('it names the value, the argument and the rule', () {
      expect(
        () => checkCommentPrefix('#\n#'),
        throwsArgumentErrorWith(
          value: '#\n#',
          name: 'commentPrefix',
          message: 'Must not contain a line break',
        ),
      );
    });

    test('an empty prefix is allowed and disables comments', () {
      expect(() => checkCommentPrefix(''), returnsNormally);
    });
  });

  group('checkLineTerminator', () {
    test('it names the three terminators the parser reads', () {
      expect(
        () => checkLineTerminator('|'),
        throwsArgumentErrorWith(
          value: '|',
          name: 'lineTerminator',
          message: r'Must be one of "\n", "\r" or "\r\n"',
        ),
      );
    });

    test('all three are accepted', () {
      for (final terminator in const ['\n', '\r', '\r\n']) {
        expect(() => checkLineTerminator(terminator), returnsNormally);
      }
    });
  });
}
