import 'package:flatconfig/flatconfig_includes.dart';
import 'package:test/test.dart';

/// Depth bounds how far an include graph reaches. Neither it nor the number of
/// directives bounds how much the graph amounts to, which is what these cover.

/// A graph where each level includes the one below it twice. Acyclic, shallow,
/// and tiny as text: `levels` of it expand to 2^levels entries.
Map<String, String> _doublingGraph(int levels) => {
  'l0.conf': 'leaf = x',
  for (var n = 1; n <= levels; n++)
    'l$n.conf': 'config-file = l${n - 1}.conf\nconfig-file = l${n - 1}.conf',
};

/// A resolver that counts what it was asked to read.
final class _CountingMemoryResolver extends SyncIncludeResolver {
  _CountingMemoryResolver(this.units);

  final Map<String, String> units;
  var calls = 0;

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    calls++;
    final content = units[request.target];

    return content == null
        ? null
        : IncludeUnit(id: request.target, content: content);
  }
}

void main() {
  group('maxIncludedEntries', () {
    test('a doubling graph is stopped long before it is assembled', () {
      // 20 levels is 1,048,576 entries from roughly 900 characters of source.
      final resolver = _CountingMemoryResolver(_doublingGraph(20));

      expect(
        () => parseWithIncludesSync(
          'config-file = l20.conf',
          resolver: resolver,
          originId: 'main.conf',
        ),
        throwsA(
          isA<IncludeBudgetExceededException>()
              .having((e) => e.budget, 'budget', 'maxIncludedEntries')
              .having((e) => e.limit, 'limit', 100000),
        ),
      );
    });

    test('it is charged as entries are handed up, not at the end', () {
      // The point of the budget is to refuse before the allocation, so a limit
      // of 1 must stop at the first include rather than after expansion.
      final resolver = _CountingMemoryResolver(_doublingGraph(20));

      expect(
        () => parseWithIncludesSync(
          'config-file = l20.conf',
          resolver: resolver,
          includeOptions: const FlatIncludeOptions(maxIncludedEntries: 1),
          originId: 'main.conf',
        ),
        throwsA(isA<IncludeBudgetExceededException>()),
      );
      // One read per level on the way down, and no deeper: the doubling
      // happens while unwinding, which the budget never reaches.
      expect(resolver.calls, lessThan(25));
    });

    test('a graph inside the budget still assembles', () {
      final doc = parseWithIncludesSync(
        'config-file = l8.conf',
        resolver: _CountingMemoryResolver(_doublingGraph(8)),
        originId: 'main.conf',
      );

      expect(doc.length, 256);
    });

    test('the including document\'s own entries are not charged', () {
      final source = [for (var i = 0; i < 50; i++) 'k$i = v'].join('\n');

      expect(
        parseWithIncludesSync(
          '$source\nconfig-file = one.conf',
          resolver: _CountingMemoryResolver(const {'one.conf': 'a = 1'}),
          includeOptions: const FlatIncludeOptions(maxIncludedEntries: 1),
          originId: 'main.conf',
        ).length,
        51,
      );
    });
  });

  group('maxIncludes', () {
    test('it bounds how many directives a traversal follows', () {
      // Distinct targets, so the cache never spares a read. This is the shape
      // that costs a network resolver a request per directive.
      final units = {for (var i = 0; i < 40; i++) 'u$i.conf': 'k$i = v'};
      final source = [
        for (var i = 0; i < 40; i++) 'config-file = u$i.conf',
      ].join('\n');
      final resolver = _CountingMemoryResolver(units);

      expect(
        () => parseWithIncludesSync(
          source,
          resolver: resolver,
          includeOptions: const FlatIncludeOptions(maxIncludes: 10),
          originId: 'main.conf',
        ),
        throwsA(
          isA<IncludeBudgetExceededException>().having(
            (e) => e.budget,
            'budget',
            'maxIncludes',
          ),
        ),
      );
      expect(resolver.calls, 11);
    });

    test('the root document is not counted as an include', () {
      expect(
        parseWithIncludesSync(
          'a = 1',
          resolver: _CountingMemoryResolver(const {}),
          includeOptions: const FlatIncludeOptions(maxIncludes: 0),
          originId: 'main.conf',
        ).toMap(),
        {'a': '1'},
      );
    });
  });

  group('the budgets are checked where they are used', () {
    // A literal would be caught by the constructor's assertion at compile
    // time. Computing the value defers it to run time, where a debug build
    // asserts and a release build has to reach the traversal's own check.
    final negative = int.parse('-1');

    test('a negative maxIncludes is rejected', () {
      expect(
        () => parseWithIncludesSync(
          'a = 1',
          resolver: _CountingMemoryResolver(const {}),
          includeOptions: FlatIncludeOptions(maxIncludes: negative),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });

    test('a negative maxIncludedEntries is rejected', () {
      expect(
        () => parseWithIncludesSync(
          'a = 1',
          resolver: _CountingMemoryResolver(const {}),
          includeOptions: FlatIncludeOptions(maxIncludedEntries: negative),
        ),
        throwsA(anyOf(isA<AssertionError>(), isA<ArgumentError>())),
      );
    });
  });
}
