import 'document.dart';
import 'exceptions.dart';
import 'include_assembly.dart';
import 'include_path_utils.dart';
import 'include_resolver_core.dart';
import 'include_traversal.dart';
import 'options.dart';

/// Parses [text] and follows every include it names through [resolver].
///
/// Semantics match the file-based path in
/// `package:flatconfig/flatconfig_io.dart`: includes are followed depth-first,
/// cycles are detected by unit id, a `?` marks an include optional, and
/// [FlatIncludeOptions.mergePolicy] decides the resulting order. [originId]
/// names [text] itself, so a resolver can tell which unit a directive came
/// from and a cycle back to the root is caught.
///
/// Asynchronous, so the resolver may read from the network, a database or a
/// Flutter asset bundle. Use [parseWithIncludesSync] when every resolver
/// involved can answer without awaiting.
///
/// ```dart
/// final doc = await parseWithIncludes(
///   'config-file = theme.conf',
///   resolver: MemoryIncludeResolver({'theme.conf': 'background = 343028'}),
/// );
/// ```
///
/// Only [FlatStreamReadOptions.lineSplitter] applies here. The encoding cannot:
/// a resolver hands over text, so whatever decoding was needed has already
/// happened, and only the resolver knew what to decode — `FileIncludeResolver`
/// takes an encoding of its own for that reason.
///
/// Throws [CircularIncludeException] on a cycle, [MissingIncludeException] for
/// a required include the resolver cannot answer,
/// [MaxIncludeDepthExceededException] past [FlatIncludeOptions.maxIncludeDepth],
/// and [IncludeBudgetExceededException] past its other budgets.
Future<FlatDocument> parseWithIncludes(
  String text, {
  required IncludeResolver resolver,
  String? originId,
  FlatParseOptions options = const FlatParseOptions(),
  FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
}) => _resolveUnit(
  IncludeUnit(id: originId ?? _rootId, content: text),
  fromUnitId: null,
  resolver: resolver,
  traversal: IncludeTraversal(
    options: options,
    includeOptions: includeOptions,
    readOptions: readOptions,
  ),
  depth: 0,
);

/// Parses [text] and follows every include it names through a synchronous
/// [resolver].
///
/// The synchronous counterpart to [parseWithIncludes], which every resolver in
/// the chain must be able to satisfy.
FlatDocument parseWithIncludesSync(
  String text, {
  required SyncIncludeResolver resolver,
  String? originId,
  FlatParseOptions options = const FlatParseOptions(),
  FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
}) => _resolveUnitSync(
  IncludeUnit(id: originId ?? _rootId, content: text),
  fromUnitId: null,
  resolver: resolver,
  traversal: IncludeTraversal(
    options: options,
    includeOptions: includeOptions,
    readOptions: readOptions,
  ),
  depth: 0,
);

const String _rootId = 'mem:<root>';

/// What following a unit's includes needs, or the answer if it is already in.
typedef _Prepared = ({
  FlatDocument? cached,
  FlatDocument doc,
  List<String> targets,
});

/// Claims [unit] for this traversal and parses it, unless it is already done.
///
/// Shared so that the two resolver loops cannot disagree about the cache, the
/// cycle check, the depth or how a unit is parsed — they differ only in
/// awaiting the resolver, and everything else they had in common was a copy.
_Prepared _prepareUnit(
  IncludeUnit unit, {
  required String? fromUnitId,
  required IncludeTraversal traversal,
  required int depth,
}) {
  final done = traversal.begin(
    unit.id,
    reportedAs: unit.id,
    includedFrom: fromUnitId,
    depth: depth,
  );
  if (done != null) {
    return (cached: done, doc: done, targets: const []);
  }

  final doc = _parseUnit(unit, traversal);

  return (
    cached: null,
    doc: doc,
    targets: collectIncludes(doc, traversal.includeOptions).includeTargets,
  );
}

/// The request [target] makes, or `null` when it names nothing.
///
/// A directive that names nothing contributes an empty group, which this
/// records itself so neither caller has to remember to.
({IncludeRequest request, ProcessedIncludePath processed})? _requestFor(
  String target,
  IncludeUnit unit,
  IncludeTraversal traversal,
  List<List<FlatEntry>> groups,
) {
  final processed = processIncludePath(
    target,
    decodeEscapes: traversal.options.decodeEscapesInQuoted,
  );

  if (processed.isEmpty) {
    groups.add(const []);

    return null;
  }

  // Before the request goes out: an answer nobody gives still costs one.
  traversal.chargeInclude(processed.path);

  return (
    request: IncludeRequest(processed.path, fromId: unit.id),
    processed: processed,
  );
}

Future<FlatDocument> _resolveUnit(
  IncludeUnit unit, {
  required String? fromUnitId,
  required IncludeResolver resolver,
  required IncludeTraversal traversal,
  required int depth,
}) async {
  final prepared = _prepareUnit(
    unit,
    fromUnitId: fromUnitId,
    traversal: traversal,
    depth: depth,
  );
  final cached = prepared.cached;
  if (cached != null) {
    return cached;
  }

  final groups = <List<FlatEntry>>[];

  for (final target in prepared.targets) {
    final next = _requestFor(target, unit, traversal, groups);
    if (next == null) {
      continue;
    }

    final included = await resolver.resolve(next.request);
    if (included == null) {
      groups.add(_missingOrThrow(next.processed, unit.id));
      continue;
    }

    final subDoc = await _resolveUnit(
      included,
      fromUnitId: unit.id,
      resolver: resolver,
      traversal: traversal,
      depth: depth + 1,
    );
    groups.add(subDoc.entries);
  }

  return _assemble(prepared.doc, unit.id, groups, traversal);
}

FlatDocument _resolveUnitSync(
  IncludeUnit unit, {
  required String? fromUnitId,
  required SyncIncludeResolver resolver,
  required IncludeTraversal traversal,
  required int depth,
}) {
  final prepared = _prepareUnit(
    unit,
    fromUnitId: fromUnitId,
    traversal: traversal,
    depth: depth,
  );
  final cached = prepared.cached;
  if (cached != null) {
    return cached;
  }

  final groups = <List<FlatEntry>>[];

  for (final target in prepared.targets) {
    final next = _requestFor(target, unit, traversal, groups);
    if (next == null) {
      continue;
    }

    final included = resolver.resolveSync(next.request);
    if (included == null) {
      groups.add(_missingOrThrow(next.processed, unit.id));
      continue;
    }

    final subDoc = _resolveUnitSync(
      included,
      fromUnitId: unit.id,
      resolver: resolver,
      traversal: traversal,
      depth: depth + 1,
    );
    groups.add(subDoc.entries);
  }

  return _assemble(prepared.doc, unit.id, groups, traversal);
}

FlatDocument _parseUnit(IncludeUnit unit, IncludeTraversal traversal) =>
    FlatDocument.parse(
      unit.content,
      options: traversal.options,
      lineSplitter: traversal.readOptions.lineSplitter,
    );

FlatDocument _assemble(
  FlatDocument doc,
  String unitId,
  List<List<FlatEntry>> groups,
  IncludeTraversal traversal,
) {
  traversal.checkAssembledSize(doc.length, groups, unitId);

  return traversal.finish(
    unitId,
    assembleIncludedDocument(doc, traversal.includeOptions, groups),
  );
}

/// An unresolved include contributes nothing when optional, and throws
/// otherwise.
List<FlatEntry> _missingOrThrow(ProcessedIncludePath processed, String fromId) {
  if (processed.isOptional) {
    return const [];
  }

  throw MissingIncludeException(fromId, processed.path);
}
