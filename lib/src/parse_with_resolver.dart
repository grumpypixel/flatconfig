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

Future<FlatDocument> _resolveUnit(
  IncludeUnit unit, {
  required String? fromUnitId,
  required IncludeResolver resolver,
  required IncludeTraversal traversal,
  required int depth,
}) async {
  final done = traversal.begin(
    unit.id,
    reportedAs: unit.id,
    includedFrom: fromUnitId,
    depth: depth,
  );
  if (done != null) {
    return done;
  }

  final doc = _parseUnit(unit, traversal);
  final collected = collectIncludes(doc, traversal.includeOptions);
  final groups = <List<FlatEntry>>[];

  for (final target in collected.includeTargets) {
    final processed = processIncludePath(
      target,
      decodeEscapes: traversal.options.decodeEscapesInQuoted,
    );
    if (processed.isEmpty) {
      groups.add(const []);
      continue;
    }

    traversal.chargeInclude(processed.path);

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
      traversal: traversal,
      depth: depth + 1,
    );
    traversal.chargeEntries(subDoc.length, included.id);
    groups.add(subDoc.entries);
  }

  return _assemble(doc, unit.id, groups, traversal);
}

FlatDocument _resolveUnitSync(
  IncludeUnit unit, {
  required String? fromUnitId,
  required SyncIncludeResolver resolver,
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
    return done;
  }

  final doc = _parseUnit(unit, traversal);
  final collected = collectIncludes(doc, traversal.includeOptions);
  final groups = <List<FlatEntry>>[];

  for (final target in collected.includeTargets) {
    final processed = processIncludePath(
      target,
      decodeEscapes: traversal.options.decodeEscapesInQuoted,
    );
    if (processed.isEmpty) {
      groups.add(const []);
      continue;
    }

    traversal.chargeInclude(processed.path);

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
      traversal: traversal,
      depth: depth + 1,
    );
    traversal.chargeEntries(subDoc.length, included.id);
    groups.add(subDoc.entries);
  }

  return _assemble(doc, unit.id, groups, traversal);
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
) => traversal.finish(
  unitId,
  assembleIncludedDocument(doc, traversal.includeOptions, groups),
);

/// An unresolved include contributes nothing when optional, and throws
/// otherwise.
List<FlatEntry> _missingOrThrow(ProcessedIncludePath processed, String fromId) {
  if (processed.isOptional) {
    return const [];
  }

  throw MissingIncludeException(fromId, processed.path);
}
