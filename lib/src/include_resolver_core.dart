// Core, web-safe include resolver interfaces and implementations.
// No dart:io imports here.

/// Resolves include targets (paths, virtual keys, URIs) into text units.
abstract class IncludeResolver {
  /// Resolve `target` relative to `fromId` (if provided).
  ///
  /// Return null if not found. Caller decides what to do with optional `?`.
  IncludeUnit? resolve(String target, {String? fromId});
}

/// A resolved include: text content + canonical id for cycle detection.
class IncludeUnit {
  /// Creates a new include unit with the given id and content.
  IncludeUnit({
    required this.id,
    required this.content,
  });

  /// The canonical id of the include unit.
  final String id; // e.g., absolute file path or "mem:base.conf"

  /// The raw config text of the include unit.
  final String content; // raw config text

  @override
  String toString() => 'IncludeUnit(id: $id, content: ${content.length} chars)';
}

/// Composes multiple resolvers; first hit wins.
class CompositeIncludeResolver implements IncludeResolver {
  /// Creates a new composite resolver with the given resolvers.
  CompositeIncludeResolver(this._resolvers);

  /// The list of resolvers.
  final List<IncludeResolver> _resolvers;

  @override
  IncludeUnit? resolve(String target, {String? fromId}) {
    for (final r in _resolvers) {
      final resolved = r.resolve(target, fromId: fromId);
      if (resolved != null) {
        return resolved;
      }
    }

    return null;
  }
}

/// Simple in-memory resolver using a map of id -> content.
/// Optionally enforces a prefix namespace (e.g. "mem:").
class MemoryIncludeResolver implements IncludeResolver {
  /// Creates a new in-memory resolver with the given units and optional prefix.
  MemoryIncludeResolver(this.units, {this.prefix});

  /// The map of id -> content.
  final Map<String, String> units;

  /// The optional prefix namespace (e.g. "mem:").
  final String? prefix;

  @override
  IncludeUnit? resolve(String target, {String? fromId}) {
    final String key;
    if (prefix != null && prefix!.isNotEmpty && !target.startsWith(prefix!)) {
      key = '${prefix!}$target';
    } else {
      key = target;
    }

    final text = units[key];
    if (text == null) {
      return null;
    }

    return IncludeUnit(id: key, content: text);
  }
}

/// Convenience alias for combining multiple resolvers.
typedef Resolvers = List<IncludeResolver>;
