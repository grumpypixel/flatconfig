import 'dart:convert' as convert;

import 'constants.dart';
import 'document.dart';
import 'validation.dart';

/// Controls how nested Map/List data are flattened into FlatEntries.
final class FlatDataOptions {
  /// Constructor for FlatDataOptions.
  const FlatDataOptions({
    this.separator = Constants.keySeparator,
    this.listMode = FlatListMode.multi,
    this.csvSeparator = ', ',
    this.csvNullToken = '',
    this.dropNulls = false,
    this.maxDepth = 64,
    this.valueEncoder,
    this.csvItemEncoder,
    this.keyEscaper,
    this.onUnsupportedListItem = FlatUnsupportedListItem.encodeJson,
  }) : assert(maxDepth >= 0, 'maxDepth must not be negative');

  /// Path separator between nested keys, e.g. `a.b.c`.
  final String separator;

  /// How deep nesting may go before flattening gives up.
  ///
  /// Cycle detection catches a structure that reaches itself, which is the
  /// unbounded case. A deep but finite one still recurses once per level and
  /// runs out of stack somewhere past a few thousand — as a `StackOverflowError`,
  /// which nothing can usefully catch. This turns it into an `ArgumentError`
  /// naming the key path instead. Defaults to 64, well past what hand-written
  /// or API-shaped data reaches.
  final int maxDepth;

  /// How lists are encoded: multiple entries or a single CSV string.
  final FlatListMode listMode;

  /// Separator used when `listMode == csv`.
  final String csvSeparator;

  /// Token used when a CSV element is `null` and `dropNulls == false`.
  /// Defaults to empty string for backwards-compatibility, but can be set to `NULL`, etc.
  final String csvNullToken;

  /// Whether `null` values are dropped entirely (otherwise become explicit resets).
  final bool dropNulls;

  /// Highest-priority encoder; if it returns non-null, it is used for ANY value (including null, Map, List).
  final FlatValueEncoder? valueEncoder;

  /// Optional per-item encoder for CSV mode (quoting/escaping).
  /// If null, items are joined as-is (v1 behavior).
  final CsvItemEncoder? csvItemEncoder;

  /// Optional escaper applied to each key segment (including root) before concatenation.
  /// Example: (k) => k.replaceAll('.', r'\.').
  final KeyEscaper? keyEscaper;

  /// Behavior when a list contains composite items (Map/List).
  final FlatUnsupportedListItem onUnsupportedListItem;

  /// A copy with the given fields replaced.
  ///
  /// The three encoders are nullable, so each takes a sentinel default rather
  /// than `null`: passing `null` explicitly clears one, and omitting it keeps
  /// what is there.
  FlatDataOptions copyWith({
    String? separator,
    FlatListMode? listMode,
    String? csvSeparator,
    String? csvNullToken,
    bool? dropNulls,
    int? maxDepth,
    FlatValueEncoder? valueEncoder = _unsetValueEncoder,
    CsvItemEncoder? csvItemEncoder = _unsetCsvItemEncoder,
    KeyEscaper? keyEscaper = _unsetKeyEscaper,
    FlatUnsupportedListItem? onUnsupportedListItem,
  }) => FlatDataOptions(
    separator: separator ?? this.separator,
    listMode: listMode ?? this.listMode,
    csvSeparator: csvSeparator ?? this.csvSeparator,
    csvNullToken: csvNullToken ?? this.csvNullToken,
    dropNulls: dropNulls ?? this.dropNulls,
    maxDepth: maxDepth ?? this.maxDepth,
    valueEncoder: identical(valueEncoder, _unsetValueEncoder)
        ? this.valueEncoder
        : valueEncoder,
    csvItemEncoder: identical(csvItemEncoder, _unsetCsvItemEncoder)
        ? this.csvItemEncoder
        : csvItemEncoder,
    keyEscaper: identical(keyEscaper, _unsetKeyEscaper)
        ? this.keyEscaper
        : keyEscaper,
    onUnsupportedListItem: onUnsupportedListItem ?? this.onUnsupportedListItem,
  );

  @override
  String toString() =>
      'FlatDataOptions(separator: $separator, listMode: ${listMode.name}, '
      'csvSeparator: $csvSeparator, csvNullToken: $csvNullToken, '
      'dropNulls: $dropNulls, maxDepth: $maxDepth, '
      'onUnsupportedListItem: ${onUnsupportedListItem.name})';

  @override
  bool operator ==(Object other) =>
      other is FlatDataOptions &&
      other.separator == separator &&
      other.listMode == listMode &&
      other.csvSeparator == csvSeparator &&
      other.csvNullToken == csvNullToken &&
      other.dropNulls == dropNulls &&
      other.maxDepth == maxDepth &&
      other.valueEncoder == valueEncoder &&
      other.csvItemEncoder == csvItemEncoder &&
      other.keyEscaper == keyEscaper &&
      other.onUnsupportedListItem == onUnsupportedListItem;

  @override
  int get hashCode => Object.hash(
    separator,
    listMode,
    csvSeparator,
    csvNullToken,
    dropNulls,
    maxDepth,
    valueEncoder,
    csvItemEncoder,
    keyEscaper,
    onUnsupportedListItem,
  );
}

/// Sentinels marking a nullable `copyWith` parameter as "not passed". Typed
/// rather than `Object?`, so a lambda written at the call site keeps its
/// inferred argument types.
String? _unsetValueEncoder(Object? value, String keyPath) => null;

String _unsetCsvItemEncoder(String item, String keyPath) => item;

String _unsetKeyEscaper(String segment) => segment;

/// List encoding mode: multi-value entries vs CSV string.
enum FlatListMode {
  /// Multiple entries for each item in the list.
  multi,

  /// A single CSV string for the list.
  csv,
}

/// Strategy for non-scalar items inside lists.
enum FlatUnsupportedListItem {
  /// Encode the item as JSON.
  encodeJson,

  /// Skip the item.
  skip,

  /// Throw an error.
  error,
}

/// Master encoder for values; returning `null` defers to default encoders.
typedef FlatValueEncoder = String? Function(Object? value, String keyPath);

/// Encoder for CSV items (e.g., quoting/escaping).
typedef CsvItemEncoder = String Function(String item, String keyPath);

/// Escaper for path key segments before concatenation (applied to root and child segments).
typedef KeyEscaper = String Function(String rawKey);

/// Flattens nested [data] into a document. Implements [FlatDocument.fromData].
FlatDocument flatDocumentFromMapData(
  Map<String, Object?> data, {
  FlatDataOptions options = const FlatDataOptions(),
}) {
  checkNonNegative(options.maxDepth, 'maxDepth');

  final entries = <FlatEntry>[];
  final active = Set<Object>.identity();

  for (final e in data.entries) {
    final root = options.keyEscaper != null
        ? options.keyEscaper!(e.key)
        : e.key;

    flattenValue(
      keyPath: root,
      value: e.value,
      options: options,
      out: entries,
      active: active,
    );
  }

  return FlatDocument.fromEntries(entries);
}

// ===== Helper Implementations (top-level; no nested functions) =====

/// Recursively flattens `value` at `keyPath` into `out` respecting `options`.
///
/// `active` holds the maps on the path from the root to `value`, so that a map
/// reaching itself is reported instead of recursing until the stack runs out.
/// `depth` bounds the other way of running out: nesting that is finite but
/// deeper than the stack.
void flattenValue({
  required String keyPath,
  required Object? value,
  required FlatDataOptions options,
  required List<FlatEntry> out,
  required Set<Object> active,
  int depth = 0,
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

  // Null handling (no override present).
  if (value == null) {
    if (!options.dropNulls) {
      out.add(FlatEntry(keyPath, null));
    }

    return;
  }

  // Scalar branch.
  if (_isScalar(value)) {
    final encoded = encodeValue(
      value: value,
      keyPath: keyPath,
      options: options,
    );
    out.add(FlatEntry(keyPath, encoded));

    return;
  }

  // Map traversal (accept any Map; convert keys to string paths).
  if (value is Map) {
    final map = value;

    // By identity, not equality: two maps with equal contents are not a cycle,
    // and the same map appearing twice as a sibling is sharing rather than
    // recursion. Only a map that is its own descendant cannot terminate.
    if (!active.add(map)) {
      throw ArgumentError.value(
        keyPath,
        'data',
        'Cyclic structure: the value at this key contains itself',
      );
    }

    if (depth >= options.maxDepth) {
      throw ArgumentError.value(
        keyPath,
        'data',
        'Nested deeper than maxDepth (${options.maxDepth})',
      );
    }

    for (final entry in map.entries) {
      final rawChild = entry.key.toString();
      final childKey = _toChildPath(
        parent: keyPath,
        child: rawChild,
        options: options,
      );

      flattenValue(
        keyPath: childKey,
        value: entry.value,
        options: options,
        out: out,
        active: active,
        depth: depth + 1,
      );
    }

    active.remove(map);

    return;
  }

  // List handling.
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
      _emitListAsCsv(keyPath: keyPath, list: list, options: options, out: out);

      return;
    }
  }

  // Fallback for anything else → JSON string.
  final json = encodeJson(value);
  out.add(FlatEntry(keyPath, json));
}

/// Encodes a single value to string according to the rules and options.
String encodeValue({
  required Object? value,
  required String keyPath,
  required FlatDataOptions options,
}) {
  // This path is only reached when _tryValueOverride returned null and value is non-null.
  if (value is bool) {
    return value ? 'true' : 'false';
  }

  if (value is num) {
    return value.toString();
  }

  // Dart enums expose `.name`.
  if (value is Enum) {
    return value.name;
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  if (value is Uri) {
    return value.toString();
  }

  // Default scalar encoding.
  return value.toString();
}

/// Emits a CSV string for a list of scalar values.
String joinAsCsv({
  required Iterable<String> items,
  required String keyPath,
  required FlatDataOptions options,
}) {
  final buffer = StringBuffer();
  var first = true;

  for (final s in items) {
    final item = options.csvItemEncoder != null
        ? options.csvItemEncoder!(s, keyPath)
        : s;

    if (!first) {
      buffer.write(options.csvSeparator);
    }

    buffer.write(item);
    first = false;
  }

  return buffer.toString();
}

/// Returns a JSON-encoded representation of the object (null-safe).
///
/// A composite the flattener does not descend into — a list, or anything that
/// is neither scalar, map nor list — ends up here. `jsonEncode` signals a
/// structure that contains itself with a [JsonCyclicError], which is an
/// `Error`: the wrong shape for bad input, and it escapes the nullable
/// accessor contract of everything built on top.
String encodeJson(Object? value) {
  try {
    return convert.jsonEncode(value);
  } on convert.JsonCyclicError {
    throw ArgumentError.value(
      value.runtimeType.toString(),
      'data',
      'Cyclic structure: a value of this type contains itself',
    );
  }
}

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
  required FlatDataOptions options,
}) {
  final safeChild = options.keyEscaper != null
      ? options.keyEscaper!(child)
      : child;

  if (parent.isEmpty) {
    return safeChild;
  }

  return parent + options.separator + safeChild;
}

void _emitListAsMulti({
  required String keyPath,
  required List<Object?> list,
  required FlatDataOptions options,
  required List<FlatEntry> out,
}) {
  for (final item in list) {
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
  required FlatDataOptions options,
  required List<FlatEntry> out,
}) {
  final items = <String>[];

  for (final item in list) {
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

  final joined = joinAsCsv(items: items, keyPath: keyPath, options: options);
  out.add(FlatEntry(keyPath, joined));
}

String? _tryValueOverride({
  required Object? value,
  required String keyPath,
  required FlatDataOptions options,
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

// ===== RFC-4180 CSV Utils =====

/// Quotes one CSV item per RFC-4180:
/// - Quote if it contains the separator, quotes, or newlines.
/// - Escape quotes by doubling them ("").
String rfc4180Quote(String item, String separator) {
  final hasSep = separator.isNotEmpty && item.contains(separator);
  final hasQuote = item.contains('"');
  final hasNl = item.contains('\n') || item.contains('\r');

  if (!hasSep && !hasQuote && !hasNl) {
    return item;
  }

  final escaped = item.replaceAll('"', '""');

  return '"$escaped"';
}

/// Returns a CsvItemEncoder that applies RFC-4180 quoting using the given separator.
/// Example:
/// ```dart
/// csvItemEncoder: rfc4180CsvItemEncoder(',')
/// ```
CsvItemEncoder rfc4180CsvItemEncoder(String separator) {
  String encode(String item, String keyPath) => rfc4180Quote(item, separator);

  return encode;
}
