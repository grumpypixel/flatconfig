import 'dart:convert';

import 'package:flatconfig/flatconfig_includes.dart';
import 'package:test/test.dart';

/// Every type that claims to be a value has to behave like one.
///
/// `==` without a matching `hashCode` is the classic way to lose an entry in a
/// `Set` or a `Map`, and a `toString` nobody calls is the classic way to ship
/// one that throws. Both were uncovered across the options and lookup types,
/// so they are swept here in one place rather than one test per class.

/// Asserts that [a] and [b] are equal, hash alike, survive a `Set`, and say
/// something of their own when printed.
void _behavesLikeAValue(Object a, Object b, Object different) {
  final label = a.runtimeType.toString();

  expect(a, b, reason: '$label: equal values must compare equal');
  expect(
    a.hashCode,
    b.hashCode,
    reason: '$label: equal values must hash alike',
  );
  expect(a, isNot(different), reason: '$label: different values must differ');
  expect({a, b}, hasLength(1), reason: '$label: a Set must fold the two');
  expect(
    a.toString(),
    isNot(startsWith('Instance of')),
    reason: '$label: must override toString',
  );
}

void main() {
  group('lookup results', () {
    test('absent', () {
      _behavesLikeAValue(
        const FlatAbsent(),
        const FlatAbsent(),
        const FlatReset(),
      );
      expect(const FlatAbsent().toString(), 'FlatLookup.absent()');
    });

    test('reset', () {
      _behavesLikeAValue(
        const FlatReset(),
        const FlatReset(),
        const FlatPresent('x'),
      );
      expect(const FlatReset().toString(), 'FlatLookup.reset()');
    });

    test('present', () {
      _behavesLikeAValue(
        const FlatPresent('x'),
        const FlatPresent('x'),
        const FlatPresent('y'),
      );
      expect(const FlatPresent('x').toString(), 'FlatLookup.present(x)');
    });

    test('the three states never collide in a set', () {
      expect({
        const FlatAbsent(),
        const FlatReset(),
        const FlatPresent(''),
      }, hasLength(3));
    });
  });

  group('options', () {
    test('FlatParseOptions', () {
      _behavesLikeAValue(
        const FlatParseOptions(),
        const FlatParseOptions(),
        const FlatParseOptions(strict: true),
      );
    });

    test('FlatIncludeOptions', () {
      _behavesLikeAValue(
        const FlatIncludeOptions(),
        const FlatIncludeOptions(),
        const FlatIncludeOptions(includeKey: 'source'),
      );
      expect(
        const FlatIncludeOptions().toString(),
        allOf(contains('config-file'), contains('ghostty')),
      );
    });

    test('FlatStreamReadOptions', () {
      _behavesLikeAValue(
        const FlatStreamReadOptions(),
        const FlatStreamReadOptions(),
        const FlatStreamReadOptions(encoding: latin1),
      );
      expect(const FlatStreamReadOptions().toString(), contains('utf-8'));
    });

    test('FlatStreamWriteOptions', () {
      _behavesLikeAValue(
        const FlatStreamWriteOptions(),
        const FlatStreamWriteOptions(),
        const FlatStreamWriteOptions(lineTerminator: '\r\n'),
      );
    });

    test('FlatEncodeOptions', () {
      _behavesLikeAValue(
        const FlatEncodeOptions(),
        const FlatEncodeOptions(),
        const FlatEncodeOptions(alwaysQuote: true),
      );
      expect(const FlatEncodeOptions().toString(), contains('escapeQuoted'));
    });

    test('FlatEnvOptions', () {
      _behavesLikeAValue(
        FlatEnvOptions(prefix: 'APP_'),
        FlatEnvOptions(prefix: 'APP_'),
        FlatEnvOptions(prefix: 'OTHER_'),
      );
    });

    test('FlatDataOptions', () {
      // Deliberately not const: canonicalization would make identity alone
      // look like equality, which is how this class went without an == for as
      // long as it did.
      _behavesLikeAValue(
        FlatDataOptions(separator: '/'),
        FlatDataOptions(separator: '/'),
        FlatDataOptions(),
      );
    });
  });

  group('include requests and units', () {
    test('a request', () {
      _behavesLikeAValue(
        const IncludeRequest('theme.conf', fromId: 'main.conf'),
        const IncludeRequest('theme.conf', fromId: 'main.conf'),
        const IncludeRequest('theme.conf'),
      );
      expect(
        const IncludeRequest('theme.conf', fromId: 'main.conf').toString(),
        allOf(contains('theme.conf'), contains('main.conf')),
      );
    });

    test('a unit', () {
      _behavesLikeAValue(
        const IncludeUnit(id: 'a', content: 'k = v'),
        const IncludeUnit(id: 'a', content: 'k = v'),
        const IncludeUnit(id: 'a', content: 'k = w'),
      );
    });
  });

  group('documents and entries', () {
    test('an entry', () {
      _behavesLikeAValue(
        FlatEntry('a', '1'),
        FlatEntry('a', '1'),
        FlatEntry('a', '2'),
      );
    });

    test('a reset entry differs from an empty one', () {
      expect(FlatEntry('a', null), isNot(FlatEntry('a', '')));
      expect(
        {FlatEntry('a', null), FlatEntry('a', '')},
        hasLength(2),
        reason: 'null and the empty string must not share a hash bucket',
      );
    });

    test('a document', () {
      _behavesLikeAValue(
        FlatDocument.parse('a = 1\n'),
        FlatDocument.parse('a = 1\n'),
        FlatDocument.parse('a = 2\n'),
      );
    });

    test('order is part of a document', () {
      expect(
        FlatDocument.parse('a = 1\nb = 2\n'),
        isNot(FlatDocument.parse('b = 2\na = 1\n')),
      );
    });
  });

  group('composites expose the resolvers they were given', () {
    test('async', () {
      final inner = [
        MemoryIncludeResolver(const {'a': 'k = 1'}),
        MemoryIncludeResolver(const {'b': 'k = 2'}),
      ];

      expect(CompositeIncludeResolver(inner).resolvers, inner);
    });

    test('sync', () {
      final inner = [
        MemoryIncludeResolver(const {'a': 'k = 1'}),
        MemoryIncludeResolver(const {'b': 'k = 2'}),
      ];

      expect(SyncCompositeIncludeResolver(inner).resolvers, inner);
    });
  });

  group('an issue describes itself', () {
    for (final kind in FlatIssueKind.values) {
      test('${kind.name} has a message', () {
        final issue = FlatIssue(
          kind: kind,
          line: 3,
          column: 1,
          rawLine: 'whatever',
        );

        expect(issue.message, isNotEmpty);
        expect(issue.toString(), contains('3'));
      });
    }

    test('a detail replaces the generic message where one is offered', () {
      const withDetail = FlatIssue(
        kind: FlatIssueKind.invalidKey,
        line: 1,
        column: 1,
        rawLine: 'a"b = 1',
        detail: 'must not contain a quote',
      );

      expect(withDetail.message, 'must not contain a quote');
    });
  });
}
