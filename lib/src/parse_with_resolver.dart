import 'document.dart';
import 'exceptions.dart';
import 'include_assembly.dart';
import 'include_path_utils.dart';
import 'include_resolver_core.dart';
import 'options.dart';
import 'validation.dart';

/// Resolver-based parsing, for sources that are not the local filesystem.
///
/// Semantics match the file-based path: includes are followed depth-first,
/// cycles are detected by canonical unit id, a `?` marks an include optional,
/// and [FlatIncludeOptions.mergePolicy] decides the resulting order.
extension FlatConfigResolverIncludes on FlatDocument {
  /// Parses [text], following includes through [resolver].
  ///
  /// Asynchronous, so the resolver may read from the network, a database or a
  /// Flutter asset bundle. Use [parseStringWithIncludesSync] when every
  /// resolver involved can answer without awaiting.
  static Future<FlatDocument> parseStringWithIncludes(
    String text, {
    required IncludeResolver resolver,
    String? originId,
    FlatParseOptions options = const FlatParseOptions(),
    FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) {
    final state = _ResolveState(
      options: options,
      includeOptions: includeOptions,
      readOptions: readOptions,
      cache: cache ?? <String, FlatDocument>{},
    );

    return _resolveUnit(
      IncludeUnit(id: originId ?? _rootId, content: text),
      fromUnitId: null,
      resolver: resolver,
      state: state,
      depth: 0,
    );
  }

  /// Parses [text], following includes through a synchronous [resolver].
  static FlatDocument parseStringWithIncludesSync(
    String text, {
    required SyncIncludeResolver resolver,
    String? originId,
    FlatParseOptions options = const FlatParseOptions(),
    FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) {
    final state = _ResolveState(
      options: options,
      includeOptions: includeOptions,
      readOptions: readOptions,
      cache: cache ?? <String, FlatDocument>{},
    );

    return _resolveUnitSync(
      IncludeUnit(id: originId ?? _rootId, content: text),
      fromUnitId: null,
      resolver: resolver,
      state: state,
      depth: 0,
    );
  }
}

const String _rootId = 'mem:<root>';

/// Everything a recursion carries that does not change between units.
final class _ResolveState {
  _ResolveState({
    required this.options,
    required this.includeOptions,
    required this.readOptions,
    required this.cache,
  });

  final FlatParseOptions options;
  final FlatIncludeOptions includeOptions;
  final FlatStreamReadOptions readOptions;
  final Map<String, FlatDocument> cache;
  final Set<String> visited = <String>{};
}

Future<FlatDocument> _resolveUnit(
  IncludeUnit unit, {
  required String? fromUnitId,
  required IncludeResolver resolver,
  required _ResolveState state,
  required int depth,
}) async {
  final cached = _enter(
    unit,
    fromUnitId: fromUnitId,
    state: state,
    depth: depth,
  );
  if (cached != null) {
    return cached;
  }

  final doc = _parseUnit(unit, state);
  final collected = collectIncludes(doc, state.includeOptions);
  final groups = <List<FlatEntry>>[];

  for (final target in collected.includeTargets) {
    final processed = processIncludePath(target);
    if (processed.isEmpty) {
      groups.add(const []);
      continue;
    }

    final included = await resolver.resolve(
      IncludeRequest(processed.path, fromId: unit.id),
    );
    if (included == null) {
      groups.add(_missingOrThrow(processed, unit.id));
      continue;
    }

    final subDoc = await _resolveUnit(
      included,
      fromUnitId: unit.id,
      resolver: resolver,
      state: state,
      depth: depth + 1,
    );
    groups.add(subDoc.entries);
  }

  return _finish(doc, unit.id, groups, state);
}

FlatDocument _resolveUnitSync(
  IncludeUnit unit, {
  required String? fromUnitId,
  required SyncIncludeResolver resolver,
  required _ResolveState state,
  required int depth,
}) {
  final cached = _enter(
    unit,
    fromUnitId: fromUnitId,
    state: state,
    depth: depth,
  );
  if (cached != null) {
    return cached;
  }

  final doc = _parseUnit(unit, state);
  final collected = collectIncludes(doc, state.includeOptions);
  final groups = <List<FlatEntry>>[];

  for (final target in collected.includeTargets) {
    final processed = processIncludePath(target);
    if (processed.isEmpty) {
      groups.add(const []);
      continue;
    }

    final included = resolver.resolveSync(
      IncludeRequest(processed.path, fromId: unit.id),
    );
    if (included == null) {
      groups.add(_missingOrThrow(processed, unit.id));
      continue;
    }

    final subDoc = _resolveUnitSync(
      included,
      fromUnitId: unit.id,
      resolver: resolver,
      state: state,
      depth: depth + 1,
    );
    groups.add(subDoc.entries);
  }

  return _finish(doc, unit.id, groups, state);
}

/// Checks depth and cycles, and returns a cached result if there is one.
///
/// Returning non-null means the caller is done with this unit.
FlatDocument? _enter(
  IncludeUnit unit, {
  required String? fromUnitId,
  required _ResolveState state,
  required int depth,
}) {
  final maxDepth = state.includeOptions.maxIncludeDepth;
  checkIncludeDepth(maxDepth);
  if (depth > maxDepth) {
    throw MaxIncludeDepthExceededException(unit.id, depth, maxDepth);
  }

  if (!state.visited.add(unit.id)) {
    throw CircularIncludeException(fromUnitId ?? unit.id, unit.id);
  }

  final cached = state.cache[unit.id];
  if (cached != null) {
    state.visited.remove(unit.id);
  }

  return cached;
}

FlatDocument _parseUnit(IncludeUnit unit, _ResolveState state) =>
    FlatDocument.parse(
      unit.content,
      options: state.options,
      lineSplitter: state.readOptions.lineSplitter,
    );

/// Builds the result, then releases the unit so it can be included elsewhere.
FlatDocument _finish(
  FlatDocument doc,
  String unitId,
  List<List<FlatEntry>> groups,
  _ResolveState state,
) {
  final result = assembleIncludedDocument(doc, state.includeOptions, groups);

  state.visited.remove(unitId);
  state.cache[unitId] = result;

  return result;
}

/// An unresolved include contributes nothing when optional, and throws
/// otherwise.
List<FlatEntry> _missingOrThrow(ProcessedIncludePath processed, String fromId) {
  if (processed.isOptional) {
    return const [];
  }

  throw MissingIncludeException(fromId, processed.path);
}
