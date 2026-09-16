import 'package:meta/meta.dart';

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
  /// Creates a new [FlatEntry] with the given [key] and [value].
  ///
  /// The [key] must not be null, but [value] can be null to represent
  /// an empty or reset configuration value.
  const FlatEntry(this.key, this.value);

  /// Creates a new [FlatEntry] after checking the [key] against SPEC.md 3.
  ///
  /// The key is rejected rather than repaired: trimming ` theme ` to `theme`
  /// would quietly hand back an entry the caller did not ask for, and the
  /// caller is the only one who knows whether the whitespace was a typo or a
  /// bug upstream.
  ///
  /// Throws an [ArgumentError] naming the rule that was broken.
  factory FlatEntry.validated(String key, [String? value]) {
    checkKey(key);

    final valueProblem = invalidValueReason(value);
    if (valueProblem != null) {
      throw ArgumentError.value(value, 'value', 'Value $valueProblem');
    }

    return FlatEntry(key, value);
  }

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
/// print(doc.valuesOf('background')); // [343028, ffaa00] (all values)
/// ```
@immutable
class FlatDocument extends Iterable<FlatEntry> {
  /// Creates a new [FlatDocument] from a list of [FlatEntry] items.
  ///
  /// The entries are defensively copied to ensure immutability, and every key
  /// is checked against SPEC.md 3.
  ///
  /// This is the boundary that makes the format safe: [FlatEntry] itself is a
  /// `const` pair and cannot validate, since a `const` constructor may only
  /// assert compile-time constant expressions. Checking here instead means no
  /// key that fails to survive a round trip can reach the encoder.
  ///
  /// Throws a [FormatException] naming the key and the rule it broke.
  factory FlatDocument(List<FlatEntry> entries) {
    validateEntries(entries);

    return FlatDocument._(List.unmodifiable(entries));
  }

  /// Creates an empty configuration document.
  factory FlatDocument.empty() => const FlatDocument._(<FlatEntry>[]);

  /// Creates a [FlatDocument] from a [Map] of key-value pairs.
  ///
  /// The map keys represent configuration names and the values represent
  /// the corresponding configuration values. The map is copied defensively
  /// and the order of iteration determines the order of entries.
  ///
  /// When [strict] is `true` (default), an empty or whitespace-only key
  /// causes a [FormatException]. When `false`, such keys are silently
  /// ignored and not included in the resulting document.
  factory FlatDocument.fromMap(
    Map<String, String?> map, {
    bool strict = true,
  }) {
    final out = [
      for (final e in map.entries) FlatEntry(e.key, e.value),
    ];

    return FlatDocument(strict ? out : _keepValidEntries(out));
  }

  /// Creates a [FlatDocument] from an iterable of [FlatEntry] objects.
  ///
  /// The provided entries are copied defensively and preserve their order.
  ///
  /// When [strict] is `true` (default), any entry with an empty or
  /// whitespace-only key causes a [FormatException]. When `false`,
  /// such entries are ignored.
  factory FlatDocument.fromEntries(
    Iterable<FlatEntry> entries, {
    bool strict = true,
  }) {
    final list = entries.toList();

    return FlatDocument(strict ? list : _keepValidEntries(list));
  }

  /// Merges multiple [FlatDocument] instances into a single document.
  ///
  /// Entries are concatenated in order, preserving duplicates. Later
  /// documents in [docs] override earlier ones when viewed through
  /// [toMap] or the `[]` operator (i.e. last value wins).
  ///
  /// When [strict] is `true` (default), empty or whitespace-only keys
  /// cause a [FormatException]. When `false`, such entries are skipped.
  factory FlatDocument.merge(
    Iterable<FlatDocument> docs, {
    bool strict = true,
  }) {
    final all = <FlatEntry>[];
    for (final d in docs) {
      all.addAll(d.entries);
    }

    return FlatDocument(strict ? all : _keepValidEntries(all));
  }

  /// Creates a [FlatDocument] containing exactly one [FlatEntry].
  ///
  /// When [strict] is `true` (default), the [key] is validated and
  /// must not be empty or whitespace-only. When `false`, validation is
  /// skipped and the key is used as-is.
  factory FlatDocument.single(
    String key, {
    String? value,
    bool strict = true,
  }) =>
      FlatDocument(
        strict
            ? [FlatEntry.validated(key, value)]
            : _keepValidEntries([FlatEntry(key, value)]),
      );

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
  /// background = 343028
  /// background = ffaa00
  /// background =
  /// ''';
  ///
  /// final doc = FlatConfig.parse(config);
  /// print(doc.valuesOf('background')); // [343028, ffaa00, null]
  /// ```
  List<String?> valuesOf(String key) {
    final map = _valuesOfExpando[this] ??= _buildValuesOf();
    return map[key] ?? const [];
  }

  static final Expando<Map<String, List<String?>>> _valuesOfExpando =
      Expando<Map<String, List<String?>>>('flatconf_valuesOf_cache');

  /// Unmodifiable all the way down, for the reason given on [_buildLatest].
  /// The inner lists are frozen here so [valuesOf] can hand them out directly
  /// instead of copying on every call.
  Map<String, List<String?>> _buildValuesOf() {
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

// Validates a collection of [FlatEntry] objects.
  ///
  /// When [strict] is `true` (default), this method checks that all
  /// entries have non-empty keys after trimming whitespace. If any key is
  /// empty or consists only of whitespace, a [FormatException] is thrown.
  ///
  /// When [strict] is `false`, the validation is skipped and the method
  /// returns immediately.
  ///
  /// This method is typically used internally by [FlatDocument] factory
  /// constructors such as [FlatDocument.fromMap], [FlatDocument.merge],
  /// and [FlatDocument.fromEntries] to enforce consistent data integrity.
  static void validateEntries(
    Iterable<FlatEntry> entries, {
    bool strict = true,
  }) {
    if (!strict) {
      return;
    }
    for (final e in entries) {
      final reason = invalidEntryReason(e);
      if (reason != null) {
        throw FormatException('$reason.');
      }
    }
  }

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

/// The entries whose keys are valid, in order.
///
/// Backs the `strict: false` mode of the document factories, which drop bad
/// entries instead of throwing.
List<FlatEntry> _keepValidEntries(Iterable<FlatEntry> entries) => [
      for (final e in entries)
        if (invalidEntryReason(e) == null) e,
    ];
