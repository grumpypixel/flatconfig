import 'package:meta/meta.dart';

/// A single configuration entry representing a `key = value` pair.
///
/// Each [FlatEntry] represents one line in a flat configuration file.
/// The [value] may be `null` if the configuration used an empty value (`key =`),
/// which is typically used to reset or unset a configuration option.
///
/// Example:
/// ```dart
/// final entry = FlatEntry('background', '282c34');
/// print(entry.key);   // background
/// print(entry.value); // 282c34
/// ```
@immutable
class FlatEntry {
  /// Creates a new [FlatEntry] with the given [key] and [value].
  ///
  /// The [key] must not be null, but [value] can be null to represent
  /// an empty or reset configuration value.
  const FlatEntry(this.key, this.value);

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
/// background = 282c34
/// background = ffaa00
/// font-size = 14
/// ''';
///
/// final doc = FlatConfig.parse(config);
/// print(doc['background']); // ffaa00 (last value)
/// print(doc.valuesOf('background')); // [282c34, ffaa00] (all values)
/// ```
@immutable
class FlatDocument extends Iterable<FlatEntry> {
  /// Creates a new [FlatDocument] from a list of [FlatEntry] items.
  ///
  /// The entries are defensively copied to ensure immutability.
  factory FlatDocument(List<FlatEntry> entries) => FlatDocument._(
        List.unmodifiable(entries),
      );

  /// Creates an empty configuration document.
  factory FlatDocument.empty() => const FlatDocument._(<FlatEntry>[]);

  // Private const constructor used internally
  const FlatDocument._(this.entries);

  /// The list of configuration entries in this document.
  ///
  /// The entries are in the order they appeared in the original configuration file.
  final List<FlatEntry> entries;

  /// All unique keys in insertion order (like [Map.keys]).
  ///
  /// Later duplicates do not change the order. If a key appears multiple times,
  /// only the first occurrence determines its position in this iterable.
  Iterable<String> get keys => toMap().keys;

  /// Returns true if the document contains the given key, regardless of value.
  ///
  /// This includes keys with null values (empty assignments like `key =`).
  bool has(String key) => toMap().containsKey(key);

  /// Returns true if the latest value for [key] is non-null.
  ///
  /// This is equivalent to `this[key] != null`.
  bool hasNonNull(String key) => this[key] != null;

  /// Returns the first value for the given key.
  ///
  /// If the key appears multiple times in the document, this returns the value
  /// from the first occurrence. Returns null if the key is not found.
  String? firstValueOf(String key) {
    for (final e in entries) {
      if (e.key == key) {
        return e.value;
      }
    }

    return null;
  }

  /// Returns the last value for the given key.
  ///
  /// This is equivalent to `this[key]` and returns the value from the most
  /// recent occurrence of the key in the document.
  String? lastValueOf(String key) => this[key];

  /// Returns a map containing the last value for each key.
  ///
  /// The map contains only the most recent value for each key, with null values
  /// for keys whose last assignment was empty (like `key =`). This is useful
  /// for simple key-value lookups when you don't need to preserve duplicate keys.
  Map<String, String?> toMap() =>
      _latestExpando[this] ??= Map.unmodifiable(_buildLatest());

  // Cache map stored externally to keep this class const-friendly.
  static final Expando<Map<String, String?>> _latestExpando =
      Expando<Map<String, String?>>('flatconf_latest_cache');

  Map<String, String?> _buildLatest() {
    final map = <String, String?>{};
    for (final e in entries) {
      map[e.key] = e.value;
    }

    return map;
  }

  /// Caches the latest and valuesOf maps.
  ///
  /// Parameters:
  /// - [toMap]: whether to cache the latest map
  /// - [toValuesOf]: whether to cache the valuesOf map
  void cache({bool toMap = true, bool toValuesOf = false}) {
    if (toMap) {
      _latestExpando[this] = _buildLatest();
    }
    if (toValuesOf) {
      _valuesOfExpando[this] = _buildValuesOf();
    }
  }

  /// Returns all values for a given key, including duplicates and nulls.
  ///
  /// This method preserves the order of values as they appeared in the original
  /// configuration file. If a key appears multiple times, all values are returned
  /// in the order they were encountered.
  ///
  /// Example:
  /// ```dart
  /// const config = '''
  /// background = 282c34
  /// background = ffaa00
  /// background =
  /// ''';
  ///
  /// final doc = FlatConfig.parse(config);
  /// print(doc.valuesOf('background')); // [282c34, ffaa00, null]
  /// ```
  List<String?> valuesOf(String key) {
    final map = _valuesOfExpando[this] ??= _buildValuesOf();
    final list = map[key];
    if (list == null) {
      return const [];
    }

    return List.unmodifiable(list);
  }

  static final Expando<Map<String, List<String?>>> _valuesOfExpando =
      Expando<Map<String, List<String?>>>('flatconf_valuesOf_cache');

  Map<String, List<String?>> _buildValuesOf() {
    final map = <String, List<String?>>{};
    for (final e in entries) {
      map.putIfAbsent(e.key, () => []).add(e.value);
    }

    return map;
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

    return double.tryParse(v);
  }

  /// Returns all entries whose key matches [key].
  ///
  /// This preserves the order of entries as they appeared in the original file.
  Iterable<FlatEntry> whereKey(String key) sync* {
    for (final e in entries) {
      if (e.key == key) yield e;
    }
  }

  /// Returns all entries whose key is in [keys].
  ///
  /// This preserves the order of entries as they appeared in the original file.
  Iterable<FlatEntry> whereKeys(Iterable<String> keys) sync* {
    final set = keys.toSet();
    for (final e in entries) {
      if (set.contains(e.key)) yield e;
    }
  }

  /// Returns all entries whose value matches [value].
  ///
  /// This preserves the order of entries as they appeared in the original file.
  Iterable<FlatEntry> whereValue(String? value) sync* {
    for (final e in entries) {
      if (e.value == value) yield e;
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

  @override
  Iterator<FlatEntry> get iterator => entries.iterator;

  @override
  int get length => entries.length;

  @override
  bool get isEmpty => entries.isEmpty;

  @override
  bool get isNotEmpty => entries.isNotEmpty;
}

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
