import 'document.dart';
import 'exceptions.dart';
import 'parser_utils.dart';

/// Converter function that turns a non-null string into a typed value `T`.
///
/// Contract:
/// - Throw on invalid input; do not return `null`.
/// - The input has already been trimmed unless the caller opted out.
///
/// Used by [FlatDocumentAccessors.getAs], [FlatDocumentAccessors.getAsOr],
/// [FlatDocumentAccessors.requireAs] and [FlatDocumentAccessors.allAs].
///
/// Example:
/// ```dart
/// final port = doc.getAs('port', int.parse);
/// ```
typedef FlatConverter<T> = T Function(String value);

/// Typed accessors for [FlatDocument].
///
/// Every supported type follows the same three shapes, with no exceptions:
///
/// - `getX(key)` returns `null` when the value is missing or unparseable,
/// - `getXOr(key, fallback)` substitutes [fallback] in that case,
/// - `requireX(key)` throws a [FormatException] instead.
///
/// [getAs] extends the same three shapes to any type you can write a converter
/// for, which is where anything beyond `String`, `int`, `double`, `bool` and
/// `List<String>` belongs. Date, duration, URI, JSON and enum converters ship
/// ready-made in `package:flatconfig/flatconfig_accessors.dart`.
extension FlatDocumentAccessors on FlatDocument {
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
}
