import 'document.dart';
import 'exceptions.dart';
import 'include_assembly.dart';
import 'include_path_utils.dart';
import 'include_resolver_core.dart';
import 'include_traversal.dart';
import 'options.dart';

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
  }) {
    final traversal = IncludeTraversal(
      options: options,
      includeOptions: includeOptions,
      readOptions: readOptions,
    );

    return _resolveUnit(
      IncludeUnit(id: originId ?? _rootId, content: text),
      fromUnitId: null,
      resolver: resolver,
      traversal: traversal,
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
  }) {
    final traversal = IncludeTraversal(
      options: options,
      includeOptions: includeOptions,
      readOptions: readOptions,
    );

    return _resolveUnitSync(
      IncludeUnit(id: originId ?? _rootId, content: text),
      fromUnitId: null,
      resolver: resolver,
      traversal: traversal,
      depth: 0,
    );
  }
}

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
      traversal: traversal,
      depth: depth + 1,
    );
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
      traversal: traversal,
      depth: depth + 1,
    );
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
