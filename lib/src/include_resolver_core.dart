// Core, web-safe include resolver interfaces and implementations.
// No dart:io imports here.

/// What a resolver is asked to find.
///
/// A single object rather than two parameters, so a resolver that needs more
/// context later gains a field instead of every implementation gaining a
/// parameter.
final class IncludeRequest {
  /// Creates a request for [target], optionally relative to [fromId].
  const IncludeRequest(this.target, {this.fromId});

  /// The include value as written, with any `?` marker already removed.
  final String target;

  /// The canonical id of the unit the directive appeared in, if any.
  ///
  /// A file resolver reads this as "resolve relative to that file's directory".
  final String? fromId;

  @override
  String toString() => 'IncludeRequest($target, fromId: $fromId)';

  @override
  bool operator ==(Object other) =>
      other is IncludeRequest &&
      other.target == target &&
      other.fromId == fromId;

  @override
  int get hashCode => Object.hash(target, fromId);
}

/// Resolves include targets (paths, virtual keys, URIs) into text units.
///
/// Asynchronous, because the interesting sources are: an HTTP endpoint, a
/// database row, a Flutter asset behind `rootBundle.loadString()`. A sync-only
/// interface excludes all three by construction, which is what the previous
/// one did.
///
/// Implement [SyncIncludeResolver] instead when the source can answer without
/// awaiting; it provides this method for you.
abstract interface class IncludeResolver {
  /// Resolves [request], or returns null if it names nothing.
  ///
  /// Returning null is not an error: the caller decides, based on whether the
  /// directive was marked optional with `?`.
  Future<IncludeUnit?> resolve(IncludeRequest request);
}

/// A resolver whose source can answer without awaiting.
///
/// Extend this rather than implementing [IncludeResolver] twice: the async
/// method is derived from the sync one here, in one place, so a sync resolver
/// still works with the async entry points.
abstract class SyncIncludeResolver implements IncludeResolver {
  /// Allows subclasses to be const.
  const SyncIncludeResolver();

  /// Resolves [request] without awaiting, or returns null.
  IncludeUnit? resolveSync(IncludeRequest request);

  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async =>
      resolveSync(request);
}

/// A resolved include: text content plus a canonical id for cycle detection.
final class IncludeUnit {
  /// Creates a new include unit with the given id and content.
  const IncludeUnit({required this.id, required this.content});

  /// The canonical id of the include unit.
  ///
  /// Two requests that reach the same content must produce the same id, or
  /// cycle detection cannot see the cycle. For files that means the resolved
  /// absolute path; in memory, something like `mem:base.conf`.
  final String id;

  /// The raw config text of the include unit.
  final String content;

  @override
  String toString() => 'IncludeUnit(id: $id, content: ${content.length} chars)';

  @override
  bool operator ==(Object other) =>
      other is IncludeUnit && other.id == id && other.content == content;

  @override
  int get hashCode => Object.hash(id, content);
}

/// Composes multiple resolvers; first hit wins.
///
/// Sync only if every member is: a composite cannot answer without awaiting
/// when one of the sources it may have to consult does.
class CompositeIncludeResolver implements IncludeResolver {
  /// Creates a new composite resolver with the given resolvers.
  CompositeIncludeResolver(List<IncludeResolver> resolvers)
    : _resolvers = List.unmodifiable(resolvers);

  final List<IncludeResolver> _resolvers;

  /// The resolvers, in the order they are consulted.
  List<IncludeResolver> get resolvers => _resolvers;

  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async {
    for (final resolver in _resolvers) {
      final resolved = await resolver.resolve(request);
      if (resolved != null) {
        return resolved;
      }
    }

    return null;
  }
}

/// A [CompositeIncludeResolver] whose members can all answer synchronously.
final class SyncCompositeIncludeResolver extends SyncIncludeResolver {
  /// Creates a composite over resolvers that are all synchronous.
  SyncCompositeIncludeResolver(List<SyncIncludeResolver> resolvers)
    : _resolvers = List.unmodifiable(resolvers);

  final List<SyncIncludeResolver> _resolvers;

  /// The resolvers, in the order they are consulted.
  List<SyncIncludeResolver> get resolvers => _resolvers;

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    for (final resolver in _resolvers) {
      final resolved = resolver.resolveSync(request);
      if (resolved != null) {
        return resolved;
      }
    }

    return null;
  }
}

/// Simple in-memory resolver using a map of id to content.
///
/// Optionally enforces a prefix namespace, for example `mem:`.
final class MemoryIncludeResolver extends SyncIncludeResolver {
  /// Creates a new in-memory resolver with the given units and optional prefix.
  MemoryIncludeResolver(Map<String, String> units, {this.prefix})
    : units = Map.unmodifiable(units);

  /// The map of id to content.
  final Map<String, String> units;

  /// The optional prefix namespace, for example `mem:`.
  final String? prefix;

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    final namespace = prefix;
    final key =
        (namespace != null &&
            namespace.isNotEmpty &&
            !request.target.startsWith(namespace))
        ? '$namespace${request.target}'
        : request.target;

    final text = units[key];
    if (text == null) {
      return null;
    }

    return IncludeUnit(id: key, content: text);
  }
}

/// Convenience alias for combining multiple resolvers.
typedef Resolvers = List<IncludeResolver>;
