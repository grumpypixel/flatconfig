import 'package:flatconfig/flatconfig_includes.dart';
import 'package:test/test.dart';

/// A resolver that can only answer after awaiting.
///
/// This is the shape the previous sync-only interface excluded by
/// construction: an HTTP endpoint, a database row, a Flutter asset behind
/// `rootBundle.loadString()`.
final class _AsyncResolver implements IncludeResolver {
  _AsyncResolver(this.units);

  final Map<String, String> units;
  final requested = <IncludeRequest>[];

  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async {
    requested.add(request);
    await Future<void>.delayed(Duration.zero);

    final content = units[request.target];
    if (content == null) {
      return null;
    }

    return IncludeUnit(id: request.target, content: content);
  }
}

void main() {
  group('an include can come from a source that has to be awaited', () {
    test('a nested async include is followed to the bottom', () async {
      final resolver = _AsyncResolver({
        'theme.conf': 'config-file = palette.conf\nfont = mono\n',
        'palette.conf': 'background = 343028\n',
      });

      final doc = await parseWithIncludes(
        'config-file = theme.conf\n',
        resolver: resolver,
        originId: 'net:root',
      );

      expect(doc['background'], '343028');
      expect(doc['font'], 'mono');
    });

    test('the request carries the unit the directive appeared in', () async {
      final resolver = _AsyncResolver({
        'theme.conf': 'config-file = palette.conf\n',
        'palette.conf': 'background = 343028\n',
      });

      await parseWithIncludes(
        'config-file = theme.conf\n',
        resolver: resolver,
        originId: 'net:root',
      );

      expect(resolver.requested, [
        const IncludeRequest('theme.conf', fromId: 'net:root'),
        const IncludeRequest('palette.conf', fromId: 'theme.conf'),
      ]);
    });

    test('a missing required include still throws', () {
      final resolver = _AsyncResolver({});

      expect(
        parseWithIncludes('config-file = nope.conf\n', resolver: resolver),
        throwsA(isA<MissingIncludeException>()),
      );
    });

    test('a missing optional include is skipped', () async {
      final doc = await parseWithIncludes(
        'config-file = ?nope.conf\nk = v\n',
        resolver: _AsyncResolver({}),
      );

      expect(doc['k'], 'v');
    });

    test('a cycle is still detected across awaits', () {
      final resolver = _AsyncResolver({
        'a.conf': 'config-file = b.conf\n',
        'b.conf': 'config-file = a.conf\n',
      });

      expect(
        parseWithIncludes('config-file = a.conf\n', resolver: resolver),
        throwsA(isA<CircularIncludeException>()),
      );
    });
  });

  group('a synchronous resolver works with both entry points', () {
    final units = {'mem:theme.conf': 'background = 343028\n'};

    test('through the sync entry point', () {
      final doc = parseWithIncludesSync(
        'config-file = theme.conf\n',
        resolver: MemoryIncludeResolver(units, prefix: 'mem:'),
      );

      expect(doc['background'], '343028');
    });

    test('and through the async one, without a wrapper', () async {
      // SyncIncludeResolver derives the async method, so a sync source does
      // not have to be adapted to be used asynchronously.
      final doc = await parseWithIncludes(
        'config-file = theme.conf\n',
        resolver: MemoryIncludeResolver(units, prefix: 'mem:'),
      );

      expect(doc['background'], '343028');
    });
  });

  group('the merge policy decides what a line below an include does', () {
    final resolver = MemoryIncludeResolver({
      'mem:theme.conf': 'font-size = 14\n',
    }, prefix: 'mem:');

    const source = 'config-file = theme.conf\nfont-size = 99\n';

    test('ghostty: the include wins', () {
      final doc = parseWithIncludesSync(source, resolver: resolver);

      expect(doc['font-size'], '14');
    });

    test('lastWins: the line below wins', () {
      final doc = parseWithIncludesSync(
        source,
        resolver: resolver,
        includeOptions: const FlatIncludeOptions(
          mergePolicy: IncludeMergePolicy.lastWins,
        ),
      );

      expect(doc['font-size'], '99');
    });
  });

  group('resolver value types', () {
    test('two units with the same id and content are equal', () {
      expect(
        const IncludeUnit(id: 'a', content: 'k = v'),
        const IncludeUnit(id: 'a', content: 'k = v'),
      );
      expect(
        const IncludeUnit(id: 'a', content: 'k = v').hashCode,
        const IncludeUnit(id: 'a', content: 'k = v').hashCode,
      );
      expect(
        const IncludeUnit(id: 'a', content: 'k = v'),
        isNot(const IncludeUnit(id: 'a', content: 'k = w')),
      );
    });

    test('a composite of sync resolvers is itself synchronous', () {
      final composite = SyncCompositeIncludeResolver([
        MemoryIncludeResolver(const {'a': 'k = 1'}),
        MemoryIncludeResolver(const {'b': 'k = 2'}),
      ]);

      expect(
        composite.resolveSync(const IncludeRequest('b'))?.content,
        'k = 2',
      );
      expect(composite.resolveSync(const IncludeRequest('c')), isNull);
    });
  });

  group('when a resolver goes wrong', () {
    test('a thrown error reaches the caller unwrapped', () {
      expect(
        () => parseWithIncludes(
          'config-file = boom\n',
          resolver: _FailingResolver(StateError('the network is down')),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a rejected future reaches the caller too', () {
      expect(
        () => parseWithIncludes(
          'config-file = boom\n',
          resolver: _FailingResolver(const FormatException('bad payload')),
          originId: 'net:root',
        ),
        throwsFormatException,
      );
    });

    test('an optional include does not excuse a thrown error', () {
      // `?` says the unit may be absent, not that the resolver may fail: a
      // resolver signals absence by returning null.
      expect(
        () => parseWithIncludes(
          'config-file = ?boom\n',
          resolver: _FailingResolver(StateError('the network is down')),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('content the parser rejects is reported against that unit', () {
      expect(
        () => parseWithIncludes(
          'config-file = broken.conf\n',
          resolver: _AsyncResolver({'broken.conf': 'no-equals-here\n'}),
          options: const FlatParseOptions(strict: true),
        ),
        throwsA(isA<MissingEqualsException>()),
      );
    });

    test('a unit answered under a different id is tracked under that id', () {
      // A resolver may redirect, and the id it returns is the one that counts
      // for cycle detection. Here the redirect target names the root again.
      expect(
        () => parseWithIncludes(
          'config-file = alias\n',
          resolver: _RedirectingResolver(),
          originId: 'net:root',
        ),
        throwsA(isA<CircularIncludeException>()),
      );
    });

    test('depth is enforced on the async path as well', () {
      expect(
        () => parseWithIncludes(
          'config-file = a.conf\n',
          resolver: _AsyncResolver({
            'a.conf': 'config-file = b.conf\n',
            'b.conf': 'config-file = c.conf\n',
            'c.conf': 'k = v\n',
          }),
          includeOptions: const FlatIncludeOptions(maxIncludeDepth: 2),
        ),
        throwsA(isA<MaxIncludeDepthExceededException>()),
      );
    });

    test('one failing resolver in a composite does not fall through', () {
      // A composite asks the next resolver when one returns null, not when one
      // throws: swallowing the error would silently serve stale content.
      final composite = CompositeIncludeResolver([
        _FailingResolver(StateError('down')),
        MemoryIncludeResolver(const {'theme.conf': 'k = fallback'}),
      ]);

      expect(
        () => parseWithIncludes(
          'config-file = theme.conf\n',
          resolver: composite,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

/// A resolver that always fails with [error].
final class _FailingResolver implements IncludeResolver {
  _FailingResolver(this.error);

  final Object error;

  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async => throw error;
}

/// A resolver that answers every request with the root's id, as a redirect
/// back to the document that asked.
final class _RedirectingResolver implements IncludeResolver {
  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async =>
      const IncludeUnit(id: 'net:root', content: 'k = v\n');
}
