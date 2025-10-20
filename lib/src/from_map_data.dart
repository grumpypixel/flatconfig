// file: lib/src/from_map_data.dart

import 'dart:convert' as convert;

import 'document.dart';

/// Controls how nested Map/List data are flattened into FlatEntries.
final class FlatMapDataOptions {
  /// Constructor for FlatMapDataOptions.
  const FlatMapDataOptions({
    this.separator = '.',
    this.listMode = FlatListMode.multi,
    this.csvSeparator = ', ',
    this.csvNullToken = '', // keep v1 behavior, but configurable
    this.dropNulls = false,
    this.valueEncoder,
    this.onUnsupportedListItem = FlatUnsupportedListItem.encodeJson,
    this.strict = true,
  });

  /// Path separator between nested keys, e.g. `a.b.c`.
  final String separator;

  /// How lists are encoded: multiple entries or a single CSV string.
  final FlatListMode listMode;

  /// Separator used when `listMode == csv`.
  final String csvSeparator;

  /// Token used when a CSV element is `null` and `dropNulls == false`.
  /// Defaults to empty string for backwards-compat, but can be set to `null`, `NULL`, etc.
  final String csvNullToken;

  /// Whether `null` values are dropped entirely (otherwise become explicit resets).
  final bool dropNulls;

  /// Highest-priority encoder; if it returns non-null, it is used for ANY value (including null, Map, List).
  final FlatValueEncoder? valueEncoder;

  /// Behavior when a list contains composite items (Map/List).
  final FlatUnsupportedListItem onUnsupportedListItem;

  /// Enables strict key validation consistent with other factories.
  final bool strict;
}

/// List encoding mode: multi-value entries vs CSV string.
enum FlatListMode {
  /// Multiple entries for each item in the list
  multi,

  /// A single CSV string for the list
  csv,
}

/// Strategy for non-scalar items inside lists.
enum FlatUnsupportedListItem {
  /// Encode the item as JSON
  encodeJson,

  /// Skip the item
  skip,

  /// Throw an error
  error,
}

/// Master encoder for values; returning `null` defers to default encoders.
typedef FlatValueEncoder = String? Function(Object? value, String keyPath);


/// Extension methods for FlatDocument.
extension FlatDocumentFactories on FlatDocument {
  /// Flattens nested Map/List data into a FlatDocument.
  ///
  /// Contract:
  /// - Maps are traversed recursively and joined with `options.separator`.
  /// - Lists are emitted as multi-value or CSV depending on `options.listMode`.
  /// - `null` becomes explicit reset unless `options.dropNulls == true`.
  /// - `options.valueEncoder` has highest priority for ANY value.
  /// - Strict behavior mirrors other factories via `options.strict`.
  static FlatDocument fromMapData(
    Map<String, Object?> data, {
    FlatMapDataOptions options = const FlatMapDataOptions(),
  }) {
    final entries = <FlatEntry>[];

    for (final e in data.entries) {
      flattenValue(
        keyPath: e.key,
        value: e.value,
        options: options,
        out: entries,
      );
    }

    return FlatDocument.fromEntries(entries, strict: options.strict);
  }
}

// ===== Helper Implementations (top-level; no nested functions) =====

/// Recursively flattens `value` at `keyPath` into `out` respecting `options`.
void flattenValue({
  required String keyPath,
  required Object? value,
  required FlatMapDataOptions options,
  required List<FlatEntry> out,
}) {
  // Highest priority: user-supplied encoder may force a specific representation for ANY value.
  final forced = _tryValueOverride(
    value: value,
    keyPath: keyPath,
    options: options,
  );
  if (forced != null) {
    out.add(FlatEntry(keyPath, forced));

    return;
  }

  // Null handling (no override present)
  if (value == null) {
    if (!options.dropNulls) {
      out.add(FlatEntry(keyPath, null));
    }

    return;
  }

  // Scalar branch
  if (_isScalar(value)) {
    final encoded = encodeValue(
      value: value,
      keyPath: keyPath,
      options: options,
    );

    out.add(FlatEntry(keyPath, encoded));

    return;
  }

  // Map traversal (accept any Map; convert keys to string paths)
  if (value is Map) {
    final map = value;

    for (final entry in map.entries) {
      final childKey = _toChildPath(
        parent: keyPath,
        child: entry.key.toString(),
        options: options,
      );

      flattenValue(
        keyPath: childKey,
        value: entry.value,
        options: options,
        out: out,
      );
    }

    return;
  }

  // List handling
  if (value is List) {
    final list = value.cast<Object?>();

    if (options.listMode == FlatListMode.multi) {
      _emitListAsMulti(
        keyPath: keyPath,
        list: list,
        options: options,
        out: out,
      );

      return;
    }

    if (options.listMode == FlatListMode.csv) {
      _emitListAsCsv(
        keyPath: keyPath,
        list: list,
        options: options,
        out: out,
      );

      return;
    }
  }

  // Fallback for anything else → JSON string
  final json = encodeJson(value);
  out.add(FlatEntry(keyPath, json));
}

/// Encodes a single value to string according to the rules and options.
String encodeValue({
  required Object? value,
  required String keyPath,
  required FlatMapDataOptions options,
}) {
  // This path is only reached when _tryValueOverride returned null and value is non-null.
  if (value is bool) {
    return value ? 'true' : 'false';
  }

  if (value is num) {
    return value.toString();
  }

  // Dart enums expose `.name`
  if (value is Enum) {
    return value.name;
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  if (value is Uri) {
    return value.toString();
  }

  // Default scalar encoding
  return value.toString();
}

/// Emits a CSV string for a list of scalar values.
String joinAsCsv({
  required Iterable<String> items,
  required FlatMapDataOptions options,
}) {
  final buffer = StringBuffer();
  var first = true;

  for (final s in items) {
    if (!first) {
      buffer.write(options.csvSeparator);
    }
    buffer.write(s);
    first = false;
  }

  return buffer.toString();
}

/// Returns a JSON-encoded representation of the object (null-safe).
String encodeJson(Object? value) => convert.jsonEncode(value);

// ===== Private helpers =====

bool _isScalar(Object? v) {
  if (v == null) {
    return true;
  }

  if (v is String ||
      v is num ||
      v is bool ||
      v is DateTime ||
      v is Uri ||
      v is Enum) {
    return true;
  }

  return false;
}

String _toChildPath({
  required String parent,
  required String child,
  required FlatMapDataOptions options,
}) {
  if (parent.isEmpty) {
    return child;
  }

  return parent + options.separator + child;
}

void _emitListAsMulti({
  required String keyPath,
  required List<Object?> list,
  required FlatMapDataOptions options,
  required List<FlatEntry> out,
}) {
  for (final item in list) {
    // Highest priority: allow override even for null and composites
    final forced = _tryValueOverride(
      value: item,
      keyPath: keyPath,
      options: options,
    );
    if (forced != null) {
      out.add(FlatEntry(keyPath, forced));

      continue;
    }

    if (item == null) {
      if (!options.dropNulls) {
        out.add(FlatEntry(keyPath, null));
      }

      continue;
    }

    if (_isScalar(item)) {
      final encoded = encodeValue(
        value: item,
        keyPath: keyPath,
        options: options,
      );

      out.add(FlatEntry(keyPath, encoded));

      continue;
    }

    // Composite item handling according to policy
    if (options.onUnsupportedListItem == FlatUnsupportedListItem.skip) {
      continue;
    }

    if (options.onUnsupportedListItem == FlatUnsupportedListItem.error) {
      throw const FormatException(
        'Composite item in list not supported in multi mode',
      );
    }

    final json = encodeJson(item);
    out.add(FlatEntry(keyPath, json));
  }
}

void _emitListAsCsv({
  required String keyPath,
  required List<Object?> list,
  required FlatMapDataOptions options,
  required List<FlatEntry> out,
}) {
  final items = <String>[];

  for (final item in list) {
    // Highest priority: allow override for any item first
    final forced = _tryValueOverride(
      value: item,
      keyPath: keyPath,
      options: options,
    );
    if (forced != null) {
      items.add(forced);

      continue;
    }

    if (item == null) {
      if (!options.dropNulls) {
        items.add(options.csvNullToken);
      }

      continue;
    }

    if (_isScalar(item)) {
      final encoded = encodeValue(
        value: item,
        keyPath: keyPath,
        options: options,
      );

      items.add(encoded);

      continue;
    }

    // Composite values in csv mode
    if (options.onUnsupportedListItem == FlatUnsupportedListItem.skip) {
      continue;
    }

    if (options.onUnsupportedListItem == FlatUnsupportedListItem.error) {
      throw const FormatException(
        'Composite item in list not supported in csv mode',
      );
    }

    final json = encodeJson(item);
    items.add(json);
  }

  final joined = joinAsCsv(items: items, options: options);
  out.add(FlatEntry(keyPath, joined));
}

String? _tryValueOverride({
  required Object? value,
  required String keyPath,
  required FlatMapDataOptions options,
}) {
  if (options.valueEncoder == null) {
    return null;
  }

  final overridden = options.valueEncoder!(value, keyPath);
  if (overridden == null) {
    return null;
  }

  return overridden;
}
