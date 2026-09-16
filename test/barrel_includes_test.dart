/// Imports nothing but the include barrel. It re-exports the core, so one
/// import has to be enough to write out every type in its signatures.
library barrel_includes_test;

import 'package:flatconfig/flatconfig_includes.dart';
import 'package:test/test.dart';

final class _Async implements IncludeResolver {
  _Async(this._units);

  final Map<String, String> _units;

  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async {
    final content = _units[request.target];

    return content == null
        ? null
        : IncludeUnit(id: request.target, content: content);
  }
}

void main() {
  const source = 'config-file = theme.conf\nfont-size = 99\n';
  const theme = 'background = 343028\nfont-size = 14\n';

  test('a synchronous resolver, through the sync entry point', () {
    final doc = parseWithIncludesSync(
      source,
      resolver: MemoryIncludeResolver(const {'theme.conf': theme}),
    );

    expect(doc['background'], '343028');
    expect(doc.requireInt('font-size'), 14);
  });

  test('an asynchronous resolver, through the async entry point', () async {
    final doc = await parseWithIncludes(
      source,
      resolver: _Async(const {'theme.conf': theme}),
      originId: 'mem:root',
    );

    expect(doc['background'], '343028');
  });

  test('the merge policy is reachable and changes the outcome', () {
    FlatDocument parse(IncludeMergePolicy policy) => parseWithIncludesSync(
      source,
      resolver: MemoryIncludeResolver(const {'theme.conf': theme}),
      includeOptions: FlatIncludeOptions(mergePolicy: policy),
    );

    expect(parse(IncludeMergePolicy.ghostty).requireInt('font-size'), 14);
    expect(parse(IncludeMergePolicy.lastWins).requireInt('font-size'), 99);
  });

  test('resolvers compose, both ways', () {
    final sync = SyncCompositeIncludeResolver([
      MemoryIncludeResolver(const {}),
      MemoryIncludeResolver(const {'theme.conf': theme}),
    ]);
    final async = CompositeIncludeResolver([
      _Async(const {}),
      MemoryIncludeResolver(const {'theme.conf': theme}),
    ]);

    expect(
      parseWithIncludesSync(source, resolver: sync)['background'],
      '343028',
    );
    expect(async, isA<IncludeResolver>());

    final Resolvers listed = [async, sync];
    expect(listed, hasLength(2));
  });

  test('the include exceptions are reachable from this barrel', () {
    expect(
      () => parseWithIncludesSync(
        'config-file = nope.conf\n',
        resolver: MemoryIncludeResolver(const {}),
      ),
      throwsA(isA<MissingIncludeException>()),
    );
    expect(
      () => parseWithIncludesSync(
        'config-file = loop.conf\n',
        resolver: MemoryIncludeResolver(const {
          'loop.conf': 'config-file = loop.conf\n',
        }),
      ),
      throwsA(isA<CircularIncludeException>()),
    );
    expect(
      () => parseWithIncludesSync(
        source,
        resolver: MemoryIncludeResolver(const {'theme.conf': theme}),
        includeOptions: const FlatIncludeOptions(maxIncludeDepth: 0),
      ),
      throwsA(isA<MaxIncludeDepthExceededException>()),
    );
    expect(
      () => parseWithIncludesSync(
        'config-file = nope.conf\n',
        resolver: MemoryIncludeResolver(const {}),
      ),
      throwsA(isA<ConfigIncludeException>()),
    );
  });

  test('the core is re-exported, so one import is enough', () {
    expect(FlatDocument.parse('a = 1\n').requireInt('a'), 1);
  });
}
