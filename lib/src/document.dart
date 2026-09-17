import 'dart:convert';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'exceptions.dart';
import 'from_map_data.dart';
import 'lookup.dart';
import 'options.dart';
import 'parser.dart';
import 'parser_utils.dart';
import 'validation.dart';

/// Converter function that turns a non-null string into a typed value `T`.
///
/// Contract:
/// - Throw on invalid input; do not return `null`.
/// - The input has already been trimmed unless the caller opted out.
///
/// An [Exception] means the value is wrong; an [Error] means the converter is,
/// and is never caught on your behalf.
///
/// Example:
/// ```dart
/// final port = doc.getAs('port', int.parse);
/// ```
typedef FlatConverter<T> = T Function(String value);

/// Ordering strategy for collapsing duplicate keys in a [FlatDocument].
enum CollapseOrder {
  /// Keep the position of the first occurrence of a key.
  firstOccurrence,

  /// Keep the position of the last write (last occurrence) of a key.
  lastWrite,
}

/// A single configuration entry representing a `key = value` pair.
///
/// Each [FlatEntry] represents one line in a flat configuration file.
/// The [value] may be `null` if the configuration used an empty value (`key =`),
/// which is typically used to reset or unset a configuration option.
///
/// Example:
/// ```dart
/// final entry = FlatEntry('background', '343028');
/// print(entry.key);   // background
/// print(entry.value); // 343028
/// ```
@immutable
class FlatEntry {
  /// Creates an entry, rejecting anything the format cannot write out.
  ///
  /// The [key] must satisfy SPEC.md 3 and [value] must not span a line break;
  /// a null [value] is the explicit reset (`key =`). Both are rejected rather
  /// than repaired: trimming ` theme ` to `theme` would quietly hand back an
  /// entry the caller did not ask for, and only the caller knows whether the
  /// whitespace was a typo or a bug upstream.
  ///
  /// This is a factory and not a `const` constructor on purpose. A `const`
  /// constructor can only check through `assert`, which is removed from
  /// release builds, and a guard that disappears exactly where it matters is
  /// the defect Phase 1.8 went through the package to remove.
  ///
  /// Throws an [ArgumentError] naming the rule that was broken.
  factory FlatEntry(String key, [String? value]) {
    checkKey(key);

    final valueProblem = invalidValueReason(value);
    if (valueProblem != null) {
      throw ArgumentError.value(value, 'value', 'Value $valueProblem');
    }

    return FlatEntry._(key, value);
  }

  /// Creates an entry that clears [key], written out as `key =`.
  factory FlatEntry.reset(String key) => FlatEntry(key);

  const FlatEntry._(this.key, this.value);

  /// The configuration key (left side of the `=` sign).
  final String key;

  /// The configuration value (right side of the `=` sign).
  ///
  /// This can be `null` to represent an empty value or configuration reset.
  final String? value;

  @override
  String toString() => 'FlatEntry($key, ${value ?? "null"})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlatEntry && key == other.key && value == other.value;

  @override
  int get hashCode => Object.hash(key, value);
}

/// A parsed configuration document containing all [FlatEntry] items.
///
/// [FlatDocument] represents a complete configuration file that has been parsed
/// from text. It preserves the order of entries and allows duplicate keys,
/// making it suitable for configuration files where the same key might appear
/// multiple times with different values.
///
/// The document provides various methods for accessing configuration values,
/// including type-safe getters for common data types and utilities for working
/// with duplicate keys.
///
/// Example:
/// ```dart
/// const config = '''
/// background = 343028
/// background = ffaa00
/// font-size = 14
/// ''';
///
/// final doc = FlatDocument.parse(config);
/// print(doc['background']); // ffaa00 (last value)
/// print(doc.allValues('background')); // [343028, ffaa00] (all values)
/// ```
@immutable
class FlatDocument {
  /// Creates a new [FlatDocument] from a list of [FlatEntry] items.
  ///
  /// The entries are copied defensively, and that is all this does: every
  /// [FlatEntry] is already valid by construction, so no key or value that
  /// fails to survive a round trip can reach here in the first place.
  factory FlatDocument(List<FlatEntry> entries) =>
      FlatDocument._(List.unmodifiable(entries));

  /// Creates an empty configuration document.
  factory FlatDocument.empty() => const FlatDocument._(<FlatEntry>[]);

  /// Creates a [FlatDocument] from a [Map] of key-value pairs.
  ///
  /// The map keys represent configuration names and the values represent
  /// the corresponding configuration values. The map is copied defensively
  /// and the order of iteration determines the order of entries.
  ///
  /// Throws an [ArgumentError] if any key breaks SPEC.md 3. Leniency belongs
  /// to the parser, where hand-edited files arrive; a document built in code
  /// from a key the format cannot represent is a bug at the call site.
  factory FlatDocument.fromMap(Map<String, String?> map) =>
      FlatDocument([for (final e in map.entries) FlatEntry(e.key, e.value)]);

  /// Creates a [FlatDocument] from an iterable of [FlatEntry] objects.
  ///
  /// The provided entries are copied defensively and preserve their order.
  ///
  /// Throws an [ArgumentError] if any key breaks SPEC.md 3.
  factory FlatDocument.fromEntries(Iterable<FlatEntry> entries) =>
      FlatDocument(entries.toList());

  // Private const constructor used internally
  const FlatDocument._(this.entries);

  // ── from text ──────────────────────────────────────────────────────────

  /// Parses a configuration string.
  ///
  /// ```dart
  /// final doc = FlatDocument.parse('background = 343028');
  /// print(doc['background']); // 343028
  /// ```
  static FlatDocument parse(
    String source, {
    FlatParseOptions options = const FlatParseOptions(),
    LineSplitter lineSplitter = const LineSplitter(),
  }) => parseSource(source, options: options, lineSplitter: lineSplitter);

  /// Parses a configuration that has already been split into lines.
  static FlatDocument parseLines(
    List<String> lines, {
    FlatParseOptions options = const FlatParseOptions(),
  }) => parseSourceLines(lines, options: options);

  /// Parses a configuration whose lines arrive over time.
  ///
  /// The asynchronous counterpart to [parseLines], for a source that hands out
  /// lines rather than bytes — stdin, or a socket behind a [LineSplitter].
  /// Bytes are the commoner case and [parseBytes] decodes and splits them.
  static Future<FlatDocument> parseLineStream(
    Stream<String> lines, {
    FlatParseOptions options = const FlatParseOptions(),
  }) => parseStringStream(lines, options: options);

  /// Parses a configuration from a byte stream, decoding it first.
  static Future<FlatDocument> parseBytes(
    Stream<List<int>> bytes, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) => parseByteStream(bytes, options: options, readOptions: readOptions);

  /// Lazily yields entries from a byte stream as they are read.
  ///
  /// Use this when the document is too large to hold at once; otherwise
  /// [parseBytes] is the simpler read.
  static Stream<FlatEntry> streamEntries(
    Stream<List<int>> bytes, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) =>
      streamEntriesFromBytes(bytes, options: options, readOptions: readOptions);

  // ── from data ──────────────────────────────────────────────────────────

  /// Builds a document from environment-like maps.
  ///
  /// This is pure: it reads no ambient state. Pass `Platform.environment`
  /// yourself if that is what you mean.
  static FlatDocument fromEnvironment(
    Map<String, String> env, {
    FlatEnvOptions? options,
  }) => documentFromEnvironment(env, options: options);

  /// Builds a document by flattening nested map and list data into key paths.
  ///
  /// Nested maps become `a.b.c = value`; lists become either repeated entries
  /// or one CSV value, depending on [options].
  static FlatDocument fromData(
    Map<String, Object?> data, {
    FlatDataOptions options = const FlatDataOptions(),
  }) => flatDocumentFromMapData(data, options: options);

  /// The list of configuration entries in this document.
  ///
  /// The entries are in the order they appeared in the original configuration file.
  final List<FlatEntry> entries;

  /// All unique keys in insertion order (like [Map.keys]).
  ///
  /// Later duplicates do not change the order. If a key appears multiple times,
  /// only the first occurrence determines its position in this iterable.
  Iterable<String> get keys => toMap().keys;

  /// Whether the document mentions [key] at all, with or without a value.
  ///
  /// A key assigned nothing (`key =`) counts as present; see [lookup] to tell
  /// the two apart.
  bool containsKey(String key) => toMap().containsKey(key);

  /// Which of the three states [key] is in.
  ///
  /// Reach for this instead of `operator []` whenever "never mentioned" and
  /// "explicitly cleared" call for different behaviour, since both read as
  /// `null` through the operator.
  FlatLookup lookup(String key) {
    final map = toMap();
    if (!map.containsKey(key)) {
      return const FlatLookup.absent();
    }

    final value = map[key];

    return value == null ? const FlatLookup.reset() : FlatLookup.present(value);
  }

  /// Returns a map containing the last value for each key.
  ///
  /// The map contains only the most recent value for each key, with null values
  /// for keys whose last assignment was empty (like `key =`). This is useful
  /// for simple key-value lookups when you don't need to preserve duplicate keys.
  Map<String, String?> toMap() => _latestExpando[this] ??= _buildLatest();

  // Cache map stored externally to keep this class const-friendly.
  static final Expando<Map<String, String?>> _latestExpando =
      Expando<Map<String, String?>>('flatconf_latest_cache');

  /// Returns an unmodifiable map, so that every caller is safe by
  /// construction. Leaving the wrapping to the callers is what let [cache]
  /// hand out a writable view of a document documented as immutable.
  Map<String, String?> _buildLatest() {
    final map = <String, String?>{};
    for (final e in entries) {
      map[e.key] = e.value;
    }

    return Map.unmodifiable(map);
  }

  /// Caches the latest and allValues maps.
  ///
  /// Parameters:
  /// - [toMap]: whether to cache the latest map
  /// - [toAllValues]: whether to cache the allValues map
  void cache({bool toMap = true, bool toAllValues = false}) {
    if (toMap) {
      _latestExpando[this] = _buildLatest();
    }
    if (toAllValues) {
      _allValuesExpando[this] = _buildAllValues();
    }
  }

  /// Returns every value assigned to [key], in file order, nulls included.
  ///
  /// This method preserves the order of values as they appeared in the original
  /// configuration file. If a key appears multiple times, all values are returned
  /// in the order they were encountered.
  ///
  /// Example:
  /// ```dart
  /// const config = '''
  /// background = 343028
  /// background = ffaa00
  /// background =
  /// ''';
  ///
  /// final doc = FlatDocument.parse(config);
  /// print(doc.allValues('background')); // [343028, ffaa00, null]
  /// ```
  List<String?> allValues(String key) {
    final map = _allValuesExpando[this] ??= _buildAllValues();
    return map[key] ?? const [];
  }

  static final Expando<Map<String, List<String?>>> _allValuesExpando =
      Expando<Map<String, List<String?>>>('flatconf_allValues_cache');

  /// Unmodifiable all the way down, for the reason given on [_buildLatest].
  /// The inner lists are frozen here so [valuesOf] can hand them out directly
  /// instead of copying on every call.
  Map<String, List<String?>> _buildAllValues() {
    final map = <String, List<String?>>{};
    for (final e in entries) {
      map.putIfAbsent(e.key, () => []).add(e.value);
    }

    return Map.unmodifiable({
      for (final entry in map.entries)
        entry.key: List<String?>.unmodifiable(entry.value),
    });
  }

  /// Convenience operator for accessing the latest value of a key.
  ///
  /// This is equivalent to `toMap()[key]` and returns the most recent value
  /// for the given key, or null if the key is not found or has an empty value.
  String? operator [](String key) => toMap()[key];

  /// Attempts to parse the latest value for [key] as an integer.
  ///
  /// Returns null if the key is missing or the value cannot be parsed as an integer.
  int? getInt(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    return int.tryParse(v);
  }

  /// Attempts to parse the latest value for [key] as a boolean.
  ///
  /// Recognizes the following values as true: `true`, `1`, `yes`, `on`
  /// Recognizes the following values as false: `false`, `0`, `no`, `off`
  ///
  /// Returns null if the key is missing or the value is not recognized.
  bool? getBool(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final t = v.trim().toLowerCase();
    if (t == 'true' || t == '1' || t == 'yes' || t == 'on') {
      return true;
    }

    if (t == 'false' || t == '0' || t == 'no' || t == 'off') {
      return false;
    }

    return null;
  }

  /// Attempts to parse the latest value for [key] as a double.
  ///
  /// Returns null if the key is missing or the value cannot be parsed as a double.
  double? getDouble(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    return tryParseFinite(v);
  }

  /// Returns all entries whose key matches [key].
  ///
  /// This preserves the order of entries as they appeared in the original file.
  Iterable<FlatEntry> whereKey(String key) sync* {
    for (final e in entries) {
      if (e.key == key) {
        yield e;
      }
    }
  }

  /// Returns all entries whose key is in [keys].
  ///
  /// This preserves the order of entries as they appeared in the original file.
  Iterable<FlatEntry> whereKeys(Iterable<String> keys) sync* {
    final set = keys.toSet();
    for (final e in entries) {
      if (set.contains(e.key)) {
        yield e;
      }
    }
  }

  /// Returns all entries whose value matches [value].
  ///
  /// This preserves the order of entries as they appeared in the original file.
  Iterable<FlatEntry> whereValue(String? value) sync* {
    for (final e in entries) {
      if (e.value == value) {
        yield e;
      }
    }
  }

  /// Returns the latest string value for the given key.
  ///
  /// This is equivalent to `this[key]` and returns the most recent value
  /// for the key, or null if the key is not found or has an empty value.
  String? getString(String key) => this[key];

  // ── typed accessors ──────────────────────────────────────────────────
  //
  // Every type offers exactly three shapes: getX (nullable),
  // getXOr(key, fallback) and requireX (throws). getAs extends the same
  // three to any type a converter can produce.

  // ── String ───────────────────────────────────────────────────────────────

  /// Returns the latest value for [key], or [defaultValue] when absent.
  String getStringOr(String key, String defaultValue) =>
      this[key] ?? defaultValue;

  /// Returns the latest value for [key].
  ///
  /// Throws a [FormatException] when the key is absent or was reset.
  String requireString(String key) {
    final v = this[key];
    if (v == null) {
      throw const FormatException('Missing string').explain(key: key);
    }

    return v;
  }

  // ── int ──────────────────────────────────────────────────────────────────

  /// Parses the latest value for [key] as an integer, or returns [defaultValue].
  int getIntOr(String key, int defaultValue) =>
      int.tryParse(this[key] ?? '') ?? defaultValue;

  /// Parses the latest value for [key] as an integer.
  ///
  /// Throws a [FormatException] when the value is absent or not an integer.
  int requireInt(String key) {
    final raw = this[key];
    final parsed = int.tryParse(raw ?? '');
    if (parsed == null) {
      throw const FormatException(
        'Expected integer',
      ).explain(key: key, got: raw);
    }

    return parsed;
  }

  // ── double ───────────────────────────────────────────────────────────────

  /// Parses the latest value for [key] as a double, or returns [defaultValue].
  ///
  /// `NaN` and the infinities are rejected: they pass every range check by
  /// being unordered, which makes them worse than a parse failure.
  double getDoubleOr(String key, double defaultValue) =>
      tryParseFinite(this[key]) ?? defaultValue;

  /// Parses the latest value for [key] as a finite double.
  ///
  /// Throws a [FormatException] when the value is absent, unparseable, or one
  /// of `NaN`, `Infinity`, `-Infinity`.
  double requireDouble(String key) {
    final raw = this[key];
    final parsed = tryParseFinite(raw);
    if (parsed == null) {
      throw const FormatException(
        'Expected double',
      ).explain(key: key, got: raw);
    }

    return parsed;
  }

  // ── bool ─────────────────────────────────────────────────────────────────

  /// Parses the latest value for [key] as a boolean, or returns [defaultValue].
  ///
  /// See [FlatDocument.getBool] for the accepted spellings.
  bool getBoolOr(String key, bool defaultValue) => getBool(key) ?? defaultValue;

  /// Parses the latest value for [key] as a boolean.
  ///
  /// Throws a [FormatException] when the value is absent or not a recognised
  /// boolean spelling.
  bool requireBool(String key) {
    final raw = this[key];
    final parsed = getBool(key);
    if (parsed == null) {
      throw const FormatException('Expected bool').explain(key: key, got: raw);
    }

    return parsed;
  }

  // ── List<String> ─────────────────────────────────────────────────────────

  /// Splits the latest value for [key] on [separator].
  ///
  /// Returns `null` when the key is absent or was reset. An explicitly empty
  /// value yields an empty list, not `null`.
  List<String>? getList(
    String key, {
    String separator = ',',
    bool trimItems = true,
    bool skipEmpty = true,
  }) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final out = <String>[];
    for (var part in v.split(separator)) {
      if (trimItems) {
        part = part.trim();
      }
      if (skipEmpty && part.isEmpty) {
        continue;
      }
      out.add(part);
    }

    return out;
  }

  /// Splits the latest value for [key], or returns [defaultValue] when absent.
  List<String> getListOr(
    String key,
    List<String> defaultValue, {
    String separator = ',',
    bool trimItems = true,
    bool skipEmpty = true,
  }) =>
      getList(
        key,
        separator: separator,
        trimItems: trimItems,
        skipEmpty: skipEmpty,
      ) ??
      defaultValue;

  /// Splits the latest value for [key].
  ///
  /// Throws a [FormatException] when the key is absent or was reset.
  List<String> requireList(
    String key, {
    String separator = ',',
    bool trimItems = true,
    bool skipEmpty = true,
  }) {
    final list = getList(
      key,
      separator: separator,
      trimItems: trimItems,
      skipEmpty: skipEmpty,
    );
    if (list == null) {
      throw const FormatException('Missing list').explain(key: key);
    }

    return list;
  }

  // ── any type ─────────────────────────────────────────────────────────────

  /// Converts the latest value for [key] using [convert].
  ///
  /// Returns `null` when the key is absent, the value is empty (unless
  /// [ignoreEmpty] is false), or [convert] throws an [Exception].
  ///
  /// An [Error] from [convert] propagates: a `TypeError` or `ArgumentError`
  /// says the converter is wrong, not that the config is.
  T? getAs<T>(
    String key,
    FlatConverter<T> convert, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) {
    final s = _prepare(key, trim: trim, ignoreEmpty: ignoreEmpty);
    if (s == null) {
      return null;
    }

    try {
      return convert(s);
    } on Exception {
      return null;
    }
  }

  /// Converts the latest value for [key], or returns [defaultValue].
  ///
  /// Substitutes [defaultValue] in every case where [getAs] returns `null`.
  T getAsOr<T>(
    String key,
    FlatConverter<T> convert,
    T defaultValue, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) =>
      getAs<T>(key, convert, trim: trim, ignoreEmpty: ignoreEmpty) ??
      defaultValue;

  /// Converts the latest value for [key] using [convert].
  ///
  /// Throws a [FormatException] when the key is absent, the value is empty
  /// (unless [ignoreEmpty] is false), or [convert] rejects it.
  T requireAs<T>(
    String key,
    FlatConverter<T> convert, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) {
    final raw = this[key];
    final s = _prepare(key, trim: trim, ignoreEmpty: ignoreEmpty);
    if (s == null) {
      throw FormatException(
        raw == null ? 'Missing value' : 'Empty value',
      ).explain(key: key, got: raw);
    }

    try {
      return convert(s);
    } on Exception catch (e) {
      throw const FormatException(
        'Conversion failed',
      ).explain(key: key, got: raw, cause: e);
    }
  }

  /// Converts every value recorded for [key], in file order.
  ///
  /// Returns `null` when the key never appears, which an empty list cannot
  /// express: a key mentioned only as a reset (`key =`) legitimately carries no
  /// values. Reset entries are skipped rather than converted.
  ///
  /// Throws a [FormatException] on the first value [convert] rejects. Dropping
  /// the bad items instead would turn a typo into a silently shorter list; if
  /// that is what you want, filter `allValues(key)` yourself.
  List<T>? allAs<T>(
    String key,
    FlatConverter<T> convert, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) {
    if (!containsKey(key)) {
      return null;
    }

    final out = <T>[];
    for (final raw in allValues(key)) {
      if (raw == null) {
        continue;
      }

      final s = trim ? raw.trim() : raw;
      if (ignoreEmpty && s.isEmpty) {
        continue;
      }

      try {
        out.add(convert(s));
      } on Exception catch (e) {
        throw const FormatException(
          'Conversion failed',
        ).explain(key: key, got: raw, cause: e);
      }
    }

    return out;
  }

  /// Returns the value for [key] ready for conversion, or `null` when there is
  /// nothing worth handing to a converter.
  String? _prepare(
    String key, {
    required bool trim,
    required bool ignoreEmpty,
  }) {
    final raw = this[key];
    if (raw == null) {
      return null;
    }

    final s = trim ? raw.trim() : raw;

    return ignoreEmpty && s.isEmpty ? null : s;
  }

  // ── manipulation, encoding, formatting ───────────────────────────────

  /// Returns a new document where duplicate keys are collapsed into at most
  /// one entry per key (latest value wins). Multi-value keys can be preserved.
  ///
  /// This method is useful for converting a document with duplicate keys into
  /// a more traditional key-value structure where each key appears only once.
  ///
  /// Parameters:
  /// - [order]: choose whether the collapsed entry stays at the first or last
  ///   occurrence position
  /// - [dropNulls]: if true, omit keys whose final collapsed value is `null`
  ///   (i.e., explicit resets are removed)
  /// - [multiValueKeys]: keys that must not be collapsed; all their entries are
  ///   preserved in-place
  /// - [isMultiValueKey]: optional predicate to dynamically mark keys as
  ///   multi-value in addition to [multiValueKeys]
  /// - [ignoreResets]: if true, ignore reset entries (key =) when collapsing
  ///
  /// Example:
  /// ```dart
  /// const config = '''
  /// background = 343028
  /// background = ffaa00
  /// title = My App
  /// ''';
  ///
  /// final doc = FlatDocument.parse(config);
  /// final collapsed = doc.collapse();
  /// print(collapsed['background']); // ffaa00
  /// ```
  FlatDocument collapse({
    CollapseOrder order = CollapseOrder.firstOccurrence,
    bool dropNulls = false,
    Iterable<String> multiValueKeys = const [],
    bool Function(String key)? isMultiValueKey,
    bool ignoreResets = false,
  }) {
    final multiSet = multiValueKeys is Set<String>
        ? multiValueKeys
        : multiValueKeys.toSet();

    bool isMulti(String k) =>
        multiSet.contains(k) || (isMultiValueKey?.call(k) ?? false);

    // Pre-pass: track last value and anchor/last indices for single-value keys.
    final lastVal = <String, String?>{};
    final anchorIndex = <String, int>{};
    final lastIndex = <String, int>{};

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];

      if (isMulti(e.key)) {
        // Multi-value keys will be preserved in the second pass.
        continue;
      }

      if (ignoreResets && e.value == null) {
        // Ignored has to mean absent. Setting an anchor here kept a key whose
        // only entries were resets alive as a reset, and updating lastIndex
        // moved the retained value to the ignored entry's position under
        // CollapseOrder.lastWrite.
        continue;
      }

      // Normal case: value (also null) is accepted.
      lastVal[e.key] = e.value;

      // Set the anchor position for the first occurrence (or keep it).
      anchorIndex.putIfAbsent(e.key, () => i);

      // Update the last occurrence.
      lastIndex[e.key] = i;
    }

    if (order == CollapseOrder.lastWrite) {
      // overwrite anchors with last occurrence indices
      for (final k in lastIndex.keys) {
        anchorIndex[k] = lastIndex[k]!;
      }
    }

    // Emit-Pass
    final out = <FlatEntry>[];
    final emitted = <String>{};

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (isMulti(e.key)) {
        // Preserve multi-value entries exactly in original order/location.
        out.add(e);
        continue;
      }

      final anchor = anchorIndex[e.key];
      if (anchor == null || emitted.contains(e.key)) {
        continue;
      }

      if (i == anchor) {
        final v = lastVal[e.key];
        if (dropNulls && v == null) {
          // skip explicit reset if requested
        } else {
          out.add(FlatEntry(e.key, v));
        }
        emitted.add(e.key);
      }
    }

    return FlatDocument(out);
  }

  /// Encodes this document into a textual configuration string.
  ///
  /// This method converts the document back to the flat configuration format,
  /// with each entry becoming a line in the format `key = value`. The encoding
  /// behavior can be customized using [options].
  ///
  /// Note: Line endings are normalized in the I/O layer, not in this method.
  ///
  /// Example:
  /// ```dart
  /// final doc = FlatDocument.fromMap({'background': '343028', 'title': 'My App'});
  /// final text = doc.encode();
  /// print(text);
  /// // background = 343028
  /// // title = My App
  /// ```
  String encode({FlatEncodeOptions options = const FlatEncodeOptions()}) {
    String quoteIfNeeded(String v) {
      final hasLeadingOrTrailingWhitespace = v != v.trim();
      final containsSeparator = v.contains(Constants.pairSeparator);
      final startsWithComment =
          options.commentPrefix.isNotEmpty &&
          v.trimLeft().startsWith(options.commentPrefix);
      final containsDoubleQuote = v.contains(Constants.quote);
      final containsNewline =
          v.contains(Constants.newline) || v.contains(Constants.carriageReturn);

      // An empty string must be quoted: a bare `key = ` is the wire form of an
      // explicit reset, so emitting it here would turn '' into null on the way
      // back (SPEC.md 6).
      final needsQuoting =
          v.isEmpty ||
          options.alwaysQuote ||
          (options.quoteIfWhitespace && hasLeadingOrTrailingWhitespace) ||
          containsSeparator ||
          startsWithComment ||
          containsDoubleQuote ||
          containsNewline;

      if (!needsQuoting) {
        return v;
      }

      if (options.escapeQuoted) {
        final escaped = v
            .replaceAll(Constants.backslash, r'\\')
            .replaceAll(Constants.quote, r'\"');

        return '"$escaped"';
      }

      return '"$v"';
    }

    final buf = StringBuffer();
    for (final e in entries) {
      checkKeyAgainstCommentPrefix(e.key, options.commentPrefix);

      final v = e.value;
      buf.writeln(v == null ? '${e.key} =' : '${e.key} = ${quoteIfNeeded(v)}');
    }

    return buf.toString();
  }

  /// Encodes this document and returns the result as bytes.
  ///
  /// This method first encodes the document to text using [options], then
  /// converts the text to bytes using the encoding specified in [writeOptions].
  /// Line endings are normalized according to [writeOptions.lineTerminator].
  ///
  /// Example:
  /// ```dart
  /// final doc = FlatDocument.fromMap({'background': '343028'});
  /// final bytes = doc.encodeToBytesWithWriteOptions();
  /// await File('config.flat').writeAsBytes(bytes);
  /// ```
  List<int> encodeToBytesWithWriteOptions({
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) {
    final text = encode(options: options);
    // encode() always terminates the last line (SPEC.md 7), so there is never
    // a missing newline to add here.
    final normalized = normalizeLineEndings(
      text,
      lineTerminator: writeOptions.lineTerminator,
    );

    return writeOptions.encoding.encode(normalized);
  }

  /// Appends every entry of [other] after this document's entries.
  ///
  /// In a last-write-wins model this is already the resolved merge:
  /// `a.concat(b).toMap()` equals `{...a.toMap(), ...b.toMap()}`. To let this
  /// document win instead, concatenate the other way round: `b.concat(a)`.
  ///
  /// Duplicates are kept, so [collapse] is what reduces the result to one
  /// entry per key.
  ///
  /// Example:
  /// ```dart
  /// final defaults = FlatDocument.fromMap({'background': '343028', 'title': 'App'});
  /// final user = FlatDocument.fromMap({'background': 'ffaa00', 'debug': 'true'});
  /// final combined = defaults.concat(user);
  /// print(combined['background']); // ffaa00
  /// print(combined['title']); // App
  /// ```
  FlatDocument concat(FlatDocument other) =>
      FlatDocument([...entries, ...other.entries]);

  /// Alias for [concat], so documents can be combined with `+`.
  FlatDocument operator +(FlatDocument other) => concat(other);

  /// This document with [key] set to [value], as the only entry for that key.
  ///
  /// An existing key keeps the position of its first occurrence and loses its
  /// other occurrences; a new key is appended. Setting a key twice therefore
  /// leaves one entry rather than a growing history, which is what makes this
  /// safe to call in a loop before writing the document back out.
  ///
  /// Pass `null` for [value] to write an explicit reset (`key =`), which is a
  /// different thing from [without]: the key is still there, and still shadows
  /// a value an earlier include set.
  ///
  /// ```dart
  /// final doc = FlatDocument.parse('a = 1\nb = x\na = 3');
  /// print(doc.withValue('a', '2').encode()); // a = 2\nb = x\n
  /// ```
  ///
  /// Throws an [ArgumentError] if [key] or [value] breaks SPEC.md 3.
  FlatDocument withValue(String key, String? value) {
    final replacement = FlatEntry(key, value);
    final result = <FlatEntry>[];
    var placed = false;

    for (final entry in entries) {
      if (entry.key != key) {
        result.add(entry);
      } else if (!placed) {
        result.add(replacement);
        placed = true;
      }
    }

    if (!placed) {
      result.add(replacement);
    }

    return FlatDocument(result);
  }

  /// This document without any entry for [key].
  ///
  /// Every occurrence goes, including an explicit reset, so the key reads as
  /// absent afterwards. The remaining entries keep their order.
  ///
  /// ```dart
  /// final doc = FlatDocument.parse('a = 1\nb = x\na = 3');
  /// print(doc.without('a').encode()); // b = x\n
  /// ```
  FlatDocument without(String key) => FlatDocument([
    for (final e in entries)
      if (e.key != key) e,
  ]);

  /// This document with [entry] appended, keeping any entry for the same key.
  ///
  /// This is the format's own notion of a write: a later line shadows an
  /// earlier one without erasing it, which is what [allValues] reports and
  /// what [collapse] resolves. Use [withValue] when the document is going to
  /// be written back out and one entry per key is what you want.
  FlatDocument withEntry(FlatEntry entry) => FlatDocument([...entries, entry]);

  /// Creates a human-friendly dump of entries in insertion order.
  ///
  /// This method is useful for debugging and understanding the structure of
  /// a configuration document. It shows each entry with its index and value.
  ///
  /// Parameters:
  /// - [includeIndexes]: if true, each line is prefixed with its index in brackets
  ///
  /// Example output (includeIndexes=true):
  /// ```
  /// [0] background = 343028
  /// [1] title = My App
  /// [2] debug = null
  /// ```
  ///
  /// When [includeIndexes] is false, the index prefix is omitted.
  String debugDump({bool includeIndexes = true}) {
    final buf = StringBuffer();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (includeIndexes) {
        buf.write('[');
        buf.write(i);
        buf.write('] ');
      }
      buf
        ..write(e.key)
        ..write(' = ')
        ..write(e.value ?? 'null');
      if (i + 1 < entries.length) {
        buf.writeln();
      }
    }

    return buf.toString();
  }

  /// Pretty printer with optional sorting and column alignment.
  ///
  /// This method formats the document for human-readable output with various
  /// formatting options to improve readability.
  ///
  /// Parameters:
  /// - [includeIndexes]: if true, lines are prefixed with "[i] " showing their index
  /// - [sortByKey]: if true, lines are ordered by key (stable sort on index)
  /// - [alignColumns]: if true, keys are padded so the '=' signs align in columns
  ///
  /// Example output (sortByKey=true, alignColumns=true):
  /// ```
  /// [0] background = 343028
  /// [1] debug      = true
  /// [2] title      = My App
  /// ```
  String toPrettyString({
    bool includeIndexes = true,
    bool sortByKey = false,
    bool alignColumns = false,
  }) {
    final items = <(int, String, String?)>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      items.add((i, e.key, e.value));
    }

    if (sortByKey) {
      items.sort((a, b) {
        final c = a.$2.compareTo(b.$2);
        if (c != 0) {
          return c;
        }

        return a.$1.compareTo(b.$1);
      });
    }

    var maxKeyLen = 0;
    if (alignColumns) {
      for (final it in items) {
        if (it.$2.length > maxKeyLen) {
          maxKeyLen = it.$2.length;
        }
      }
    }

    final buf = StringBuffer();
    for (var idx = 0; idx < items.length; idx++) {
      final (i, key, value) = items[idx];
      if (includeIndexes) {
        buf
          ..write('[')
          ..write(i)
          ..write('] ');
      }
      if (alignColumns) {
        buf
          ..write(key)
          ..write(' ' * (maxKeyLen - key.length))
          ..write(' = ');
      } else {
        buf
          ..write(key)
          ..write(' = ');
      }
      buf.write(value ?? 'null');
      if (idx + 1 < items.length) {
        buf.writeln();
      }
    }

    return buf.toString();
  }

  /// Returns a new document containing only entries whose keys start with [prefix].
  ///
  /// Operates on the resolved/latest view (unique keys; last value wins),
  /// preserving the first-occurrence key order.
  ///
  /// When [prefix] is empty, this returns a clone of the current document,
  /// including duplicates.
  FlatDocument slice(String prefix) {
    if (prefix.isEmpty) {
      // Clone original entries, including duplicates and order.
      return FlatDocument(List<FlatEntry>.of(entries));
    }

    // Resolved/latest view: unique keys with last value, in first-occurrence order.
    final out = <FlatEntry>[];
    for (final k in toMap().keys) {
      if (k.startsWith(prefix)) {
        out.add(FlatEntry(k, this[k]));
      }
    }

    return FlatDocument(out);
  }

  /// Returns a new document with keys starting with [prefix], but with [prefix]
  /// removed from the beginning of each key.
  ///
  /// Operates on the resolved/latest view (unique keys; last value wins),
  /// preserving the first-occurrence key order.
  ///
  /// When [prefix] is empty, this returns a clone of the current document
  /// (including duplicates) without rewriting.
  ///
  /// Throws an [ArgumentError] when removing [prefix] would leave a key the
  /// format cannot hold — an empty one for a key equal to the prefix, or one
  /// starting with `#` or whitespace for a key such as `window.#secret`. Those
  /// are valid source keys, so dropping them would lose an entry the caller
  /// never heard about.
  FlatDocument stripPrefix(String prefix) {
    if (prefix.isEmpty) {
      // Clone original entries unchanged.
      return FlatDocument(List<FlatEntry>.of(entries));
    }

    final out = <FlatEntry>[];
    for (final key in toMap().keys) {
      if (!key.startsWith(prefix)) {
        continue;
      }

      final stripped = key.substring(prefix.length);
      final reason = invalidKeyReason(stripped);
      if (reason != null) {
        throw ArgumentError.value(
          key,
          'prefix',
          "Removing '$prefix' leaves a key that $reason; the entry cannot be "
              'renamed',
        );
      }

      out.add(FlatEntry(stripped, this[key]));
    }

    return FlatDocument(out);
  }

  @override
  String toString() => 'FlatDocument(${entries.length} entries)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FlatDocument && _listEquals(entries, other.entries);

  @override
  int get hashCode => Object.hashAll(entries);

  /// How many entries the document holds, duplicates included.
  int get length => entries.length;

  /// Whether the document holds no entries at all.
  bool get isEmpty => entries.isEmpty;

  /// Whether the document holds at least one entry.
  bool get isNotEmpty => entries.isNotEmpty;

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) {
      return true;
    }

    if (a.length != b.length) {
      return false;
    }

    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }

    return true;
  }
}
