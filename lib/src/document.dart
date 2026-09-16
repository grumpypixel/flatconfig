import 'dart:convert';

import 'package:meta/meta.dart';

import 'from_map_data.dart';
import 'lookup.dart';
import 'options.dart';
import 'parser.dart';
import 'parser_utils.dart';
import 'validation.dart';

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
/// final doc = FlatConfig.parse(config);
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
    FlatEnvOptions options = const FlatEnvOptions(),
  }) => documentFromEnvironment(env, options: options);

  /// Builds a document by flattening nested map and list data into key paths.
  ///
  /// Nested maps become `a.b.c = value`; lists become either repeated entries
  /// or one CSV value, depending on [options].
  static FlatDocument fromData(
    Map<String, Object?> data, {
    FlatMapDataOptions options = const FlatMapDataOptions(),
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
  /// final doc = FlatConfig.parse(config);
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
