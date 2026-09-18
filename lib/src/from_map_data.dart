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
    this.maxEncodedNodes = 1 << 20,
    this.valueEncoder,
    this.csvItemEncoder,
    this.keyEscaper,
    this.onUnsupportedListItem = FlatUnsupportedListItem.encodeJson,
  }) : assert(maxDepth >= 0, 'maxDepth must not be negative'),
       assert(maxEncodedNodes >= 0, 'maxEncodedNodes must not be negative');

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

  /// How many values a composite may expand to once written out.
  ///
  /// JSON has no sharing, so a value two parents point at appears under both.
  /// A node holding the same child twice doubles per level: forty levels is
  /// eighty objects in memory and a trillion in the output. Depth does not see
  /// that, and neither does the size of the input.
  ///
  /// Exceeding it raises an `ArgumentError` naming the key path. Defaults to
  /// 1,048,576, which no configuration value reaches without meaning to.
  final int maxEncodedNodes;

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

  @override
  String toString() =>
      'FlatDataOptions(separator: $separator, listMode: ${listMode.name}, '
      'csvSeparator: $csvSeparator, csvNullToken: $csvNullToken, '
      'dropNulls: $dropNulls, maxDepth: $maxDepth, '
      'maxEncodedNodes: $maxEncodedNodes, '
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
      other.maxEncodedNodes == maxEncodedNodes &&
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
    maxEncodedNodes,
    valueEncoder,
    csvItemEncoder,
    keyEscaper,
    onUnsupportedListItem,
  );
}

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
  checkNonNegative(options.maxEncodedNodes, 'maxEncodedNodes');

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

  // List handling. Nothing below descends through this function again, so the
  // depth left over from the walk so far has to be checked here in one go.
  if (value is List) {
    checkEncodableValue(value, options.maxDepth - depth, keyPath, options);

    final list = value.cast<Object?>();

    // Exhaustive, so a future list mode is a compile error here rather than a
    // list quietly falling through to whole-value JSON below.
    switch (options.listMode) {
      case FlatListMode.multi:
        _emitListAsMulti(
          keyPath: keyPath,
          list: list,
          options: options,
          out: out,
        );
      case FlatListMode.csv:
        _emitListAsCsv(
          keyPath: keyPath,
          list: list,
          options: options,
          out: out,
        );
    }

    return;
  }

  // Fallback for anything else → JSON string.
  checkEncodableValue(value, options.maxDepth - depth, keyPath, options);
  out.add(FlatEntry(keyPath, encodeJson(value)));
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

/// Throws an [ArgumentError] unless [value] is within [options]' budgets.
///
/// Two ways a composite value can be more than the encoder can take, and
/// neither is visible from its size in memory.
///
/// It can be too **deep**: the flattener bounds its own recursion, but it does
/// not descend into a list — a composite item goes to [encodeJson], and
/// `jsonEncode` walks it recursively, so ten thousand nested lists reach the
/// end of the stack inside the encoder as a `StackOverflowError` that nothing
/// can usefully catch.
///
/// It can also be too **wide**: JSON has no notion of sharing, so a value that
/// two parents point at is written out under each of them. Forty levels of a
/// node holding the same child twice is eighty objects in memory and 2^40 in
/// the output.
///
/// Measured level by level rather than by recursing, so the check cannot be
/// the thing that overflows, and each level keeps only distinct nodes, so a
/// shared subtree is walked once however often it is pointed at. A structure
/// that contains itself never runs out of levels and is caught by the depth
/// limit.
void checkEncodableValue(
  Object? value,
  int remainingDepth,
  String keyPath,
  FlatDataOptions options,
) {
  var frontier = <Object?, int>{if (_hasChildren(value)) _expand(value): 1};
  var emitted = 0;

  for (var depth = 0; frontier.isNotEmpty; depth++) {
    if (depth >= remainingDepth) {
      throw ArgumentError.value(keyPath, 'data', 'Nested deeper than maxDepth');
    }

    final next = Map<Object?, int>.identity();

    frontier.forEach((node, paths) {
      final children = node is Map ? node.values : (node! as List);

      // Every child is written once per path that reaches its parent, which is
      // what turns sharing into duplication.
      emitted += children.length * paths;

      for (final child in children) {
        if (_hasChildren(child)) {
          final node = _expand(child);
          next[node] = (next[node] ?? 0) + paths;
        }
      }
    });

    if (emitted > options.maxEncodedNodes) {
      throw ArgumentError.value(
        keyPath,
        'data',
        'Expands to more than maxEncodedNodes (${options.maxEncodedNodes}) '
            'values once written out',
      );
    }

    frontier = next;
  }
}

/// Whether [value] is something the JSON encoder will walk into.
///
/// A map, a list, or an object with a `toJson` that returns one. The last case
/// is the reason this is a function rather than a type test: the encoder calls
/// `toJson` itself, so an object that looks like a leaf here can hand it a
/// structure of any shape, and both budgets would have been measured against
/// the wrong thing.
bool _hasChildren(Object? value) {
  final expanded = _expand(value);

  return expanded is Map || expanded is List;
}

/// [value] as the encoder will see it: its `toJson()` result, or itself.
///
/// Anything but a `Map`, `List` or JSON scalar gets one `toJson` call, the same
/// one `jsonEncode` will make. A type without that method, or one that throws
/// from it, is returned unchanged and left for the encoder to reject.
Object? _expand(Object? value) {
  if (value == null ||
      value is Map ||
      value is List ||
      value is String ||
      value is num ||
      value is bool) {
    return value;
  }

  try {
    return (value as dynamic).toJson() as Object?;
  } on NoSuchMethodError {
    return value;
  } on Object {
    return value;
  }
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

/// What one list item becomes, decided once for both list modes.
///
/// The two emitters used to repeat this: the override, the null, the scalar,
/// the unsupported-item policy and the JSON fallback, in the same order, with
/// only the output differing. Five chances for the two modes to disagree.
sealed class _ItemOutcome {
  const _ItemOutcome();
}

/// The item became text.
final class _ItemText extends _ItemOutcome {
  const _ItemText(this.text);

  final String text;
}

/// The item is a null the caller wants kept.
final class _ItemNull extends _ItemOutcome {
  const _ItemNull();
}

/// The item contributes nothing.
final class _ItemSkipped extends _ItemOutcome {
  const _ItemSkipped();
}

/// Decides what [item] becomes, for a list rendered as [mode].
///
/// [mode] names the list mode in the error the `error` policy raises, and is
/// the only thing the two callers pass differently.
_ItemOutcome _classifyItem(
  Object? item,
  String keyPath,
  FlatDataOptions options,
  String mode,
) {
  final forced = _tryValueOverride(
    value: item,
    keyPath: keyPath,
    options: options,
  );
  if (forced != null) {
    return _ItemText(forced);
  }

  if (item == null) {
    return options.dropNulls ? const _ItemSkipped() : const _ItemNull();
  }

  if (_isScalar(item)) {
    return _ItemText(
      encodeValue(value: item, keyPath: keyPath, options: options),
    );
  }

  // Exhaustive, so adding a policy is a compile error here rather than a
  // silent fall through to JSON.
  return switch (options.onUnsupportedListItem) {
    FlatUnsupportedListItem.skip => const _ItemSkipped(),
    FlatUnsupportedListItem.error => throw FormatException(
      'Composite item in list not supported in $mode mode',
    ),
    FlatUnsupportedListItem.encodeJson => _ItemText(encodeJson(item)),
  };
}

void _emitListAsMulti({
  required String keyPath,
  required List<Object?> list,
  required FlatDataOptions options,
  required List<FlatEntry> out,
}) {
  for (final item in list) {
    switch (_classifyItem(item, keyPath, options, 'multi')) {
      case _ItemText(:final text):
        out.add(FlatEntry(keyPath, text));
      case _ItemNull():
        out.add(FlatEntry(keyPath, null));
      case _ItemSkipped():
        break;
    }
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
    switch (_classifyItem(item, keyPath, options, 'csv')) {
      case _ItemText(:final text):
        items.add(text);
      case _ItemNull():
        items.add(options.csvNullToken);
      case _ItemSkipped():
        break;
    }
  }

  out.add(
    FlatEntry(
      keyPath,
      joinAsCsv(items: items, keyPath: keyPath, options: options),
    ),
  );
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

// ===== Inline list quoting =====

/// Quotes one inline list item the way this format reads it back.
///
/// The grammar of SPEC.md 5, which is what `FlatDocument.getList` parses: wrap
/// the item in quotes when leaving it bare would change where the item ends,
/// and escape a quote as `\"` and a backslash as `\\`.
///
/// This replaced an RFC-4180 encoder that doubled quotes instead. It produced
/// valid CSV that this package could not read: `getList` decodes `\"`, so an
/// item written `""quote""` came back with its doubling intact. Two public
/// helpers that do not compose are worse than one.
String quoteInlineItem(String item, String separator) {
  // Any character of the separator, not the separator as a whole: the default
  // writes `', '` while a reader splits on `,` and trims, so an item holding
  // either would come back as two.
  final holdsSeparator = separator.codeUnits.any(
    (unit) => item.codeUnits.contains(unit),
  );

  final needsQuotes =
      item.isEmpty ||
      holdsSeparator ||
      item.contains(Constants.quote) ||
      item.trim().length != item.length;

  if (!needsQuotes) {
    return item;
  }

  final escaped = item
      .replaceAll(Constants.backslash, r'\\')
      .replaceAll(Constants.quote, r'\"');

  return '"$escaped"';
}

/// A [CsvItemEncoder] that writes items [quoteInlineItem] can read back.
///
/// ```dart
/// csvItemEncoder: inlineItemEncoder(',')
/// ```
CsvItemEncoder inlineItemEncoder(String separator) {
  String encode(String item, String keyPath) =>
      quoteInlineItem(item, separator);

  return encode;
}
