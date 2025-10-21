import 'document.dart';
import 'exceptions.dart';
import 'ghostty_semantics.dart';
import 'include_path_utils.dart';
import 'include_resolver_core.dart';
import 'options.dart';
import 'parser.dart';

/// Resolver-based parsing entry that mirrors Ghostty semantics and your
/// file-based implementation, but operates on arbitrary resolvers.
extension FlatConfigResolverIncludes on FlatConfig {
  /// Parses a raw string with Ghostty-style includes resolved via [resolver].
  ///
  /// Semantics are identical to file-based parsing in this package:
  /// - Include directives are processed at the end of the current unit.
  /// - Later entries in the current unit do not override include keys.
  /// - If multiple included units define the same key, the later include wins.
  /// - Optional includes use `?` and are ignored if missing.
  /// - Circular includes are detected via the canonical unit id.
  static FlatDocument parseStringWithIncludes(
    String text, {
    required IncludeResolver resolver,
    String? originId, // canonical id of this "virtual file"
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) {
    final visited = <String>{};
    final effectiveCache = cache ?? <String, FlatDocument>{};

    final root = IncludeUnit(
      id: originId ?? 'mem:<root>',
      content: text,
    );

    final result = _parseWithResolverRecursiveSync(
      currentUnit: root,
      fromUnitId: null,
      resolver: resolver,
      options: options,
      readOptions: readOptions,
      visited: visited,
      cache: effectiveCache,
      depth: 0,
    );

    return result;
  }
}

// Internal sync recursive parse using IncludeResolver (no File I/O here).
FlatDocument _parseWithResolverRecursiveSync({
  required IncludeUnit currentUnit,
  String? fromUnitId,
  required IncludeResolver resolver,
  required FlatParseOptions options,
  required FlatStreamReadOptions readOptions,
  required Set<String> visited,
  required Map<String, FlatDocument> cache,
  required int depth,
}) {
  if (depth > options.maxIncludeDepth) {
    throw MaxIncludeDepthExceededException(
      currentUnit.id,
      depth,
      options.maxIncludeDepth,
    );
  }

  final String unitId = currentUnit.id;

  if (!visited.add(unitId)) {
    throw CircularIncludeException(fromUnitId ?? unitId, unitId);
  }

  final cached = cache[unitId];
  if (cached != null) {
    visited.remove(unitId);

    return cached;
  }

  final doc = FlatConfig.parse(
    currentUnit.content,
    options: options,
    lineSplitter: readOptions.lineSplitter,
  );

  // First pass: collect include directives and pre-include entries
  final collected = collectIncludesAndPreEntries(doc, options);

  // Resolve includes
  final includeEntries = _processIncludesWithResolverSync(
    includeValues: collected.includeValues,
    fromUnitId: unitId,
    resolver: resolver,
    options: options,
    readOptions: readOptions,
    visited: visited,
    cache: cache,
    depth: depth,
  );

  // Process document with Ghostty semantics to get filtered tail entries
  final keysFromIncludes = includeEntries.map((e) => e.key).toSet();
  final filteredTail = filterTailEntries(doc, options, keysFromIncludes);

  // Build final document according to Ghostty semantics
  final result = buildGhosttyDocument(
    collected.preIncludeEntries,
    includeEntries,
    filteredTail,
  );

  visited.remove(unitId);
  cache[unitId] = result;

  return result;
}

List<FlatEntry> _processIncludesWithResolverSync({
  required List<String> includeValues,
  required String fromUnitId,
  required IncludeResolver resolver,
  required FlatParseOptions options,
  required FlatStreamReadOptions readOptions,
  required Set<String> visited,
  required Map<String, FlatDocument> cache,
  required int depth,
}) {
  final includeEntries = <FlatEntry>[];

  for (final raw in includeValues) {
    final processed = processIncludePath(raw);
    if (processed.isEmpty) {
      continue;
    }

    final unit = resolver.resolve(processed.path, fromId: fromUnitId);
    if (unit == null) {
      if (processed.isOptional) {
        continue;
      }

      throw MissingIncludeException(fromUnitId, processed.path);
    }

    final subDoc = _parseWithResolverRecursiveSync(
      currentUnit: unit,
      fromUnitId: fromUnitId,
      resolver: resolver,
      options: options,
      readOptions: readOptions,
      visited: visited,
      cache: cache,
      depth: depth + 1,
    );

    includeEntries.addAll(subDoc.entries);
  }

  return includeEntries;
}
