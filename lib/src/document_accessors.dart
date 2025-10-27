import 'dart:convert' as convert;
import 'constants.dart';
import 'document.dart';
import 'exceptions.dart';
import 'parser_utils.dart';

/// Converter function that transforms a non-null string into a typed value `T`.
///
/// Contract:
/// - Must throw on invalid input (do not return null).
/// - May assume the input has already been optionally trimmed by the caller.
///
/// Used by: `getAs`, `getAsOr`, `requireAs`.
///
/// Example:
/// ```dart
/// final port = doc.getAs('port', int.parse);
/// ```
typedef FlatConverter<T> = T Function(String value);

/// Advanced, context-aware converter.
///
/// Receives:
/// - [raw]: the raw (optionally trimmed) string value, or `null` if the key is missing,
/// - [key]: the configuration key,
/// - [doc]: the entire document (for cross-field logic).
///
/// Return `null` to signal conversion failure (treated like “no value” in lenient
/// APIs; `requireAsWith` will throw).
///
/// Used by: `getAsWith`, `requireAsWith`.
///
/// Example:
/// ```dart
/// final size = doc.getAsWith<int>('size', (raw, key, d) {
///   if (raw == null) return null;
///   return int.tryParse(raw); // null → conversion failure
/// });
/// ```
typedef FlatAdvancedConverter<T> = T? Function(
  String? raw,
  String key,
  FlatDocument doc,
);

/// Extensions for [FlatDocument] providing additional accessor and parsing helpers.
///
/// This extension adds convenient methods for accessing configuration values
/// with type conversion, default values, and validation. It includes methods
/// for parsing common data types like integers, booleans, dates, durations,
/// colors, and more.
extension FlatDocumentAccessors on FlatDocument {
  /// Returns the latest value for [key] with whitespace trimmed, or null if missing.
  ///
  /// This is equivalent to `this[key]?.trim()`.
  String? getTrimmed(String key) => this[key]?.trim();

  /// Returns the trimmed string value or an empty string when missing.
  ///
  /// This is equivalent to `getTrimmed(key) ?? ''`.
  String getTrimmedOrEmpty(String key) => getTrimmed(key) ?? '';

  /// Returns the string value for [key] or [defaultValue] if missing.
  ///
  /// This method provides a convenient way to get a string value with a fallback
  /// when the key is not present or has a null value.
  String getStringOr(String key, String defaultValue) {
    final v = this[key];

    return v ?? defaultValue;
  }

  /// Requires a string value for [key], throwing an exception if missing.
  ///
  /// This method throws a [FormatException] if the key is not present or has
  /// a null value. Empty strings are considered valid.
  String requireString(String key) {
    final v = this[key];
    if (v == null) {
      throw const FormatException('Missing string').explain(
        key: key,
      );
    }

    return v;
  }

  /// Returns the boolean value for [key] or [defaultValue] if missing/invalid.
  ///
  /// This method attempts to parse the value as a boolean using the same rules
  /// as [getBool], but returns [defaultValue] instead of null for missing or
  /// invalid values.
  bool getBoolOr(String key, bool defaultValue) {
    final b = getBool(key);

    return b ?? defaultValue;
  }

  /// Requires a boolean value for [key], throwing an exception if missing/invalid.
  ///
  /// This method throws a [FormatException] if the key is not present or the
  /// value cannot be parsed as a boolean.
  bool requireBool(String key) {
    final raw = this[key];
    final parsed = getBool(key);
    if (parsed == null) {
      throw const FormatException('Expected bool').explain(
        key: key,
        got: raw,
      );
    }

    return parsed;
  }

  /// Interprets the value as a feature flag, returning [defaultValue] when absent.
  ///
  /// This method is a convenience wrapper around [getBoolOr] that's specifically
  /// designed for feature flags and boolean configuration options.
  bool isEnabled(String key, {bool defaultValue = false}) =>
      getBoolOr(key, defaultValue);

  /// Returns true when the feature flag is disabled (logical negation of [isEnabled]).
  ///
  /// This method is the inverse of [isEnabled] and is useful for checking if
  /// a feature is explicitly disabled.
  bool isDisabled(String key, {bool defaultValue = false}) =>
      !isEnabled(key, defaultValue: defaultValue);

  /// Returns [defaultValue] if absent or invalid.
  int getIntOr(String key, int defaultValue) {
    final v = this[key];
    final i = int.tryParse(v ?? '');

    return i ?? defaultValue;
  }

  /// Require an int; throws [FormatException] if missing/invalid.
  int requireInt(String key) {
    final raw = this[key];
    final parsed = int.tryParse(raw ?? '');
    if (parsed == null) {
      throw const FormatException('Expected integer').explain(
        key: key,
        got: raw,
      );
    }

    return parsed;
  }

  /// Returns [defaultValue] if absent or invalid.
  double getDoubleOr(String key, double defaultValue) {
    final v = this[key];
    final d = double.tryParse(v ?? '');

    return d ?? defaultValue;
  }

  /// Require a double; throws [FormatException] if missing/invalid.
  double requireDouble(String key) {
    final raw = this[key];
    final parsed = double.tryParse(raw ?? '');
    if (parsed == null) {
      throw const FormatException('Expected double').explain(
        key: key,
        got: raw,
      );
    }

    return parsed;
  }

  /// Parses ISO-8601 timestamps. Returns null if absent/invalid.
  DateTime? getDateTime(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }
    try {
      return DateTime.parse(v);
    } on FormatException catch (_) {
      return null;
    }
  }

  /// Require DateTime; throws [FormatException] if missing/invalid.
  DateTime requireDateTime(String key) {
    final dt = getDateTime(key);
    if (dt == null) {
      throw const FormatException('Expected ISO-8601 DateTime').explain(
        key: key,
        got: this[key],
      );
    }

    return dt;
  }

  /// Parses duration from values like: 150ms, 2s, 5m, 3h, 1d.
  /// Bare numbers are treated as milliseconds.
  Duration? getDuration(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final t = v.trim().toLowerCase();
    if (t.isEmpty) {
      return null;
    }

    final match = Constants.durationRegex.firstMatch(t);
    if (match == null) {
      return null;
    }

    final numStr = match.group(1)!;
    final unit = match.group(2) ?? 'ms';
    final value = double.tryParse(numStr);
    if (value == null) {
      return null;
    }

    return switch (unit) {
      'ms' => Duration(milliseconds: value.round()),
      's' => Duration(milliseconds: (value * 1000).round()),
      'm' => Duration(milliseconds: (value * 60 * 1000).round()),
      'h' => Duration(milliseconds: (value * 60 * 60 * 1000).round()),
      'd' => Duration(milliseconds: (value * 24 * 60 * 60 * 1000).round()),
      _ => null,
    };
  }

  /// Returns parsed duration or [defaultValue] when absent/invalid.
  Duration getDurationOr(String key, Duration defaultValue) =>
      getDuration(key) ?? defaultValue;

  /// Require a duration; throws [FormatException] if missing/invalid.
  Duration requireDuration(String key) {
    final d = getDuration(key);
    if (d == null) {
      throw const FormatException('Expected duration').explain(
        key: key,
        got: this[key],
      );
    }

    return d;
  }

  /// Parses bytes from strings like: 10KB, 2MB, 1GiB.
  /// Supports SI (kB, MB, GB, TB, PB) and IEC (KiB, MiB, GiB, TiB, PiB).
  /// Bare numbers are bytes.
  int? getBytes(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final t = v.trim().toLowerCase();
    if (t.isEmpty) {
      return null;
    }

    final match = Constants.bytesRegex.firstMatch(t);
    if (match == null) {
      return null;
    }

    final numStr = match.group(1)!;
    final unit = match.group(2) ?? 'b';
    final value = double.tryParse(numStr);
    if (value == null) {
      return null;
    }

    final scale = switch (unit) {
      'b' => 1,
      'kb' => 1000,
      'mb' => 1000 * 1000,
      'gb' => 1000 * 1000 * 1000,
      'tb' => 1000 * 1000 * 1000 * 1000,
      'pb' => 1000 * 1000 * 1000 * 1000 * 1000,
      'kib' => 1024,
      'mib' => 1024 * 1024,
      'gib' => 1024 * 1024 * 1024,
      'tib' => 1024 * 1024 * 1024 * 1024,
      'pib' => 1024 * 1024 * 1024 * 1024 * 1024,
      _ => null,
    };

    if (scale == null) {
      return null;
    }

    final bytes = (value * scale).round();

    return bytes >= 0 ? bytes : null; // >= 0 is just a sanity check
  }

  /// Require bytes; throws [FormatException] if missing/invalid.
  int requireBytes(String key) {
    final b = getBytes(key);
    if (b == null) {
      throw const FormatException('Expected bytes').explain(
        key: key,
        got: this[key],
      );
    }

    return b;
  }

  /// Parses relative or absolute URIs. Returns null if absent/invalid.
  Uri? getUri(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    return Uri.tryParse(v);
  }

  /// Require Uri; throws [FormatException] if missing/invalid.
  Uri requireUri(String key) {
    final u = getUri(key);
    if (u == null) {
      throw const FormatException('Expected URI').explain(
        key: key,
        got: this[key],
      );
    }

    return u;
  }

  /// Maps string value to enum via provided mapping.
  T? getEnum<T>(
    String key,
    Map<String, T> mapping, {
    bool caseInsensitive = true,
    Map<String, T>? preNormalizedLowerMapping,
  }) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    if (!caseInsensitive) {
      return mapping[v.trim()];
    }

    final k = v.trim().toLowerCase();
    final m = preNormalizedLowerMapping ??
        {for (final e in mapping.entries) e.key.toLowerCase(): e.value};

    return m[k];
  }

  /// Require enum; throws [FormatException] if missing/invalid.
  T requireEnum<T>(
    String key,
    Map<String, T> mapping, {
    bool caseInsensitive = true,
    Map<String, T>? preNormalizedLowerMapping,
  }) {
    final v = getEnum<T>(
      key,
      mapping,
      caseInsensitive: caseInsensitive,
      preNormalizedLowerMapping: preNormalizedLowerMapping,
    );
    if (v == null) {
      throw const FormatException('Expected enum').explain(
        key: key,
        got: this[key],
      );
    }

    return v;
  }

  /// Parses a hex color and returns as 32-bit ARGB integer (0xAARRGGBB).
  /// Accepts forms: #rgb, #rgba, #rrggbb, #aarrggbb, #rrggbbaa; '#' optional.
  /// By default, 8-digit values are interpreted as CSS-style RRGGBBAA
  /// (alpha at the end). Set [cssAlphaAtEnd] to false to treat them as AARRGGBB.
  int? getHexColor(String key, {bool cssAlphaAtEnd = true}) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    var s = v.trim().toLowerCase();
    if (s.isEmpty) {
      return null;
    }

    if (s.startsWith('#')) {
      s = s.substring(1);
    }

    // Early reject if contains non-hex characters
    if (!Constants.hexColorRegex.hasMatch(s)) {
      return null;
    }

    // Accept lengths: 3 (#rgb), 4 (#rgba), 6 (#rrggbb), 8 (#aarrggbb or #rrggbbaa)
    if (!(s.length == 3 || s.length == 4 || s.length == 6 || s.length == 8)) {
      return null;
    }

    // Expand shorthand (#rgb/#rgba) to full length
    if (s.length == 3 || s.length == 4) {
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        final c = s[i];
        buf
          ..write(c)
          ..write(c);
      }
      s = buf.toString(); // now 6 or 8 (rrggbb or rrggbbaa)
    }

    // If 6 digits (RRGGBB), assume full opacity (FF)
    if (s.length == 6) {
      s = 'ff$s'; // AARRGGBB
    } else if (s.length == 8) {
      // 8 digits: either AARRGGBB or RRGGBBAA
      if (cssAlphaAtEnd) {
        // Convert RRGGBBAA -> AARRGGBB
        s = '${s.substring(6, 8)}${s.substring(0, 6)}';
      } else {
        // Keep as AARRGGBB
        // no change
      }
    }

    // Now s should be 8 hex digits: AARRGGBB
    final hex = int.tryParse(s, radix: 16);
    if (hex == null) {
      return null;
    }

    return hex;
  }

  /// Require hex color; throws [FormatException] if missing/invalid.
  /// Pass-through to [getHexColor] with the same [cssAlphaAtEnd] semantics.
  int requireHexColor(String key, {bool cssAlphaAtEnd = true}) {
    final hex = getHexColor(key, cssAlphaAtEnd: cssAlphaAtEnd);
    if (hex == null) {
      throw const FormatException('Expected hex color').explain(
        key: key,
        got: this[key],
      );
    }

    return hex;
  }

  /// Returns color as a tuple-like map {a,r,g,b} if parseable; otherwise null.
  /// You can override [cssAlphaAtEnd] to control how 8-digit hex values are read:
  /// - true (default): interpret as RRGGBBAA (CSS-style)
  /// - false: interpret as AARRGGBB (Flutter/Android-style)
  Map<String, int>? getColor(String key, {bool cssAlphaAtEnd = true}) {
    final argb = getHexColor(key, cssAlphaAtEnd: cssAlphaAtEnd);
    if (argb == null) {
      return null;
    }

    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;

    return {'a': a, 'r': r, 'g': g, 'b': b};
  }

  /// Require color; throws [FormatException] if missing/invalid.
  /// Pass-through to [getColor] with the same [cssAlphaAtEnd] semantics.
  Map<String, int> requireColor(String key, {bool cssAlphaAtEnd = true}) {
    final color = getColor(key, cssAlphaAtEnd: cssAlphaAtEnd);
    if (color == null) {
      throw const FormatException('Expected color').explain(
        key: key,
        got: this[key],
      );
    }

    return color;
  }

  /// Like [getColor], but as a tuple (a,r,g,b).
  (int a, int r, int g, int b)? getColorTuple(
    String key, {
    bool cssAlphaAtEnd = true,
  }) {
    final argb = getHexColor(key, cssAlphaAtEnd: cssAlphaAtEnd);
    if (argb == null) {
      return null;
    }

    return (
      (argb >> 24) & 0xFF,
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
    );
  }

  /// Require color tuple; throws [FormatException] if missing/invalid.
  (int a, int r, int g, int b) requireColorTuple(
    String key, {
    bool cssAlphaAtEnd = true,
  }) {
    final t = getColorTuple(key, cssAlphaAtEnd: cssAlphaAtEnd);
    if (t == null) {
      throw const FormatException('Expected color')
          .explain(key: key, got: this[key]);
    }

    return t;
  }

  /// Returns null if absent/invalid/out of range.
  int? getIntInRange(String key, {int? min, int? max}) {
    final v = this[key];
    final i = int.tryParse(v ?? '');
    if (i == null) {
      return null;
    }
    if (min != null && i < min) {
      return null;
    }
    if (max != null && i > max) {
      return null;
    }

    return i;
  }

  /// Require int in range; throws [FormatException] if missing/invalid/out of range.
  int requireIntInRange(String key, {int? min, int? max}) {
    final i = getIntInRange(key, min: min, max: max);
    if (i == null) {
      throw FormatException(
        'Expected int in range ${min ?? '-∞'}..${max ?? '∞'}',
      ).explain(
        key: key,
        got: this[key],
      );
    }

    return i;
  }

  /// Parses an int and clamps it to the provided [min] and [max].
  /// Returns null if the value is absent or cannot be parsed.
  int? getClampedInt(String key, {required int min, required int max}) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final i = int.tryParse(v);
    if (i == null) {
      return null;
    }

    var lo = min;
    var hi = max;
    if (lo > hi) {
      final tmp = lo;
      lo = hi;
      hi = tmp;
    }
    if (i < lo) {
      return lo;
    }
    if (i > hi) {
      return hi;
    }

    return i;
  }

  /// Returns null if absent/invalid/out of range.
  double? getDoubleInRange(String key, {double? min, double? max}) {
    final v = this[key];
    final d = double.tryParse(v ?? '');
    if (d == null) {
      return null;
    }
    if (min != null && d < min) {
      return null;
    }
    if (max != null && d > max) {
      return null;
    }

    return d;
  }

  /// Require double in range; throws [FormatException] if missing/invalid/out of range.
  double requireDoubleInRange(String key, {double? min, double? max}) {
    final d = getDoubleInRange(key, min: min, max: max);
    if (d == null) {
      throw FormatException(
        'Expected double in range ${min ?? '-∞'}..${max ?? '∞'}',
      ).explain(
        key: key,
        got: this[key],
      );
    }

    return d;
  }

  /// Splits a string into a list using [separator] (default ',').
  /// Optionally trims items and skips empty items.
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

    final parts = v.split(separator);
    final out = <String>[];
    for (var p in parts) {
      if (trimItems) {
        p = p.trim();
      }
      if (skipEmpty && p.isEmpty) {
        continue;
      }
      out.add(p);
    }

    return out;
  }

  /// Like [getList], but never returns null.
  List<String> getListOrEmpty(
    String key, {
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
      const [];

  /// Splits a string into a set using [separator] (default ',').
  /// Optionally trims items, skips empty items, and lowercases when
  /// [caseInsensitive] is true.
  Set<String>? getSet(
    String key, {
    String separator = ',',
    bool trimItems = true,
    bool skipEmpty = true,
    bool caseInsensitive = true,
  }) {
    final list = getList(
      key,
      separator: separator,
      trimItems: trimItems,
      skipEmpty: skipEmpty,
    );
    if (list == null) {
      return null;
    }

    if (caseInsensitive) {
      return list.map((e) => e.toLowerCase()).toSet();
    }

    return list.toSet();
  }

  /// Like [getSet], but never returns null.
  Set<String> getSetOrEmpty(
    String key, {
    String separator = ',',
    bool trimItems = true,
    bool skipEmpty = true,
  }) =>
      getSet(key,
          separator: separator, trimItems: trimItems, skipEmpty: skipEmpty) ??
      const {};

  /// Parses "a:1,b:2" into a map. Trims keys/values when [trim]=true.
  /// Items without [pairSep] are ignored.
  Map<String, String> getMap(
    String key, {
    String itemSep = ',',
    String pairSep = ':',
    bool trim = true,
  }) {
    final v = this[key];
    if (v == null || v.isEmpty) {
      return const {};
    }

    final out = <String, String>{};
    for (final item in v.split(itemSep)) {
      final idx = item.indexOf(pairSep);
      if (idx < 0) {
        continue;
      }

      var k = item.substring(0, idx);
      var vv = item.substring(idx + pairSep.length);
      if (trim) {
        k = k.trim();
        vv = vv.trim();
      }
      if (k.isEmpty) {
        continue;
      }
      out[k] = vv;
    }

    return out;
  }

  /// Like [getMap], but never returns null (always a map).
  Map<String, String> getMapOrEmpty(
    String key, {
    String itemSep = ',',
    String pairSep = ':',
    bool trim = true,
  }) {
    final map = getMap(
      key,
      itemSep: itemSep,
      pairSep: pairSep,
      trim: trim,
    );

    // return the same instance if already empty to allow const {}
    return map.isEmpty ? const {} : map;
  }

  /// Parses the latest value of [key] as a single `key=value` pair and returns
  /// it as a record `(String key, String? value)`.
  ///
  /// Returns null when the document misses [key] or the value does not contain
  /// '='. The key part is right-trimmed when [trimKey] is true. Value parsing
  /// follows the same rules as the main parser (quoted values preserve
  /// whitespace and '='; unquoted values are trimmed; empty -> null).
  (String key, String? value)? getKeyValue(
    String key, {
    bool decodeEscapesInQuoted = false,
    bool trimKey = true,
  }) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final idx = v.indexOf(Constants.pairSeparator);
    if (idx < 0) {
      return null;
    }

    var k = v.substring(0, idx);
    if (trimKey) {
      k = k.trimRight();
    }

    final value = parseValue(
      v.substring(idx + 1),
      decodeEscapesInQuoted: decodeEscapesInQuoted,
    );

    if (k.isEmpty) {
      // Mirror top-level semantics: ignore/invalid when key empty.
      return null;
    }

    return (k, value);
  }

  /// Returns a unified numeric value (int or double) or null if invalid/missing.
  num? getNum(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }
    final i = int.tryParse(v);
    if (i != null) {
      return i;
    }

    return double.tryParse(v);
  }

  /// Require num; throws [FormatException] if missing/invalid.
  num requireNum(String key) {
    final n = getNum(key);
    if (n == null) {
      throw const FormatException('Expected num')
          .explain(key: key, got: this[key]);
    }

    return n;
  }

  /// Parses aspect ratio like "16:9" or "4:3" to a double (w/h).
  double? getRatio(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final t = v.trim();
    final idx = t.indexOf(':');
    if (idx <= 0 || idx >= t.length - 1) {
      return null;
    }

    final left = double.tryParse(t.substring(0, idx).trim());
    final right = double.tryParse(t.substring(idx + 1).trim());
    if (left == null || right == null || right == 0) {
      return null;
    }

    return left / right;
  }

  /// Require ratio; throws [FormatException] if missing/invalid.
  double requireRatio(String key) {
    final r = getRatio(key);
    if (r == null) {
      throw const FormatException('Expected ratio')
          .explain(key: key, got: this[key]);
    }

    return r;
  }

  // Parses a percentage to a ratio.
  ///
  /// Accepts forms like "50%", "80 %", "0.8", or "80" (interpreted as 80%).
  /// By default values may exceed 1.0 (e.g. "150" -> 1.5).
  /// Set [clamp01] to true to clamp the result into [0.0, 1.0].
  double? getPercent(
    String key, {
    bool clamp01 = false,
  }) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final t = v.trim().toLowerCase();
    if (t.isEmpty) {
      return null;
    }

    var s = t;
    var hadPercent = false;
    if (s.endsWith('%')) {
      s = s.substring(0, s.length - 1).trim();
      hadPercent = true;
    }

    final x = double.tryParse(s);
    if (x == null) {
      return null;
    }

    double r;
    if (hadPercent) {
      r = x / 100.0;
    } else if (x > 1.0) {
      // Not explicitly percent: treat values > 1 as percent, else ratio.
      r = x / 100.0;
    } else {
      if (x < 0.0) {
        return null; // negative not supported
      }
      r = x; // already a ratio 0..1
    }
    if (clamp01) {
      if (r < 0.0) {
        return 0.0;
      }
      if (r > 1.0) {
        return 1.0;
      }
    }

    return r;
  }

  /// Require a percentage; throws when missing/invalid.
  double requirePercent(String key) {
    final r = getPercent(key);
    if (r == null) {
      throw const FormatException('Expected percent').explain(
        key: key,
        got: this[key],
      );
    }

    return r;
  }

  /// Parses the latest value as JSON using [jsonDecode]. Returns null on
  /// missing/invalid JSON. The result is typically a Map or List.
  Object? getJson(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    try {
      return convert.jsonDecode(v);
    } catch (_) {
      return null;
    }
  }

  /// Require JSON; throws [FormatException] if missing/invalid.
  Object requireJson(String key) {
    final j = getJson(key);
    if (j == null) {
      throw const FormatException('Expected JSON').explain(
        key: key,
        got: this[key],
      );
    }

    return j;
  }

  /// Parses a host[:port] string into (host, port?). Supports IPv6 in brackets
  /// like "[::1]:8080" and returns null on invalid/missing.
  (String host, int? port)? getHostPort(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final t = v.trim();
    if (t.isEmpty) {
      return null;
    }

    String host;
    String? portStr;

    if (t.startsWith('[')) {
      final end = t.indexOf(']');
      if (end <= 0) {
        return null;
      }

      host = t.substring(1, end);
      final rest = t.substring(end + 1).trimLeft();
      if (rest.isEmpty) {
        return (host, null);
      }
      if (!rest.startsWith(':')) {
        return null; // invalid trailing chars after IPv6
      }

      portStr = rest.substring(1).trim();
      if (portStr.isEmpty) {
        return (host, null);
      }
    } else {
      final idx = t.lastIndexOf(':');
      if (idx > 0 && t.indexOf(':') == idx) {
        // exactly one ':' -> split host:port
        host = t.substring(0, idx).trim();
        portStr = t.substring(idx + 1).trim();
        if (host.isEmpty) {
          return null;
        }
        if (portStr.isEmpty) {
          portStr = null;
        }
      } else {
        // no ':' or multiple ':' (likely raw IPv6 without brackets) -> host only
        host = t;
        portStr = null;
      }
    }

    int? port;
    if (portStr != null) {
      final p = int.tryParse(portStr);
      if (p == null || p < 0 || p > 65535) {
        return null;
      }
      port = p;
    }

    return (host, port);
  }

  /// Returns true if the latest value equals one of [values].
  ///
  /// When [caseInsensitive] is true (default), comparison ignores case.
  /// If [preNormalizedLowerValues] is provided, it is used to avoid repeated
  /// lowercasing of the values.
  bool isOneOf(
    String key,
    Set<String> values, {
    bool caseInsensitive = true,
    Set<String>? preNormalizedLowerValues,
  }) {
    final v = this[key];
    if (v == null) {
      return false;
    }

    if (!caseInsensitive) {
      return values.contains(v.trim());
    }

    final set =
        preNormalizedLowerValues ?? values.map((e) => e.toLowerCase()).toSet();
    return set.contains(v.trim().toLowerCase());
  }

  /// Require that all [keys] are present (value may be empty quoted string).
  ///
  /// Throws [FormatException] listing the first missing key encountered.
  void requireKeys(Iterable<String> keys) {
    for (final k in keys) {
      if (!has(k)) {
        throw const FormatException('Missing required key').explain(
          key: k,
        );
      }
    }
  }

  /// Returns `true` if all [keys] exist in this document.
  /// - When [ignoreNulls] is true (default), keys with null values don't count.
  /// - Case-sensitive by default.
  bool hasAllKeys(
    Iterable<String> keys, {
    bool ignoreNulls = true,
    bool caseSensitive = true,
  }) {
    final map = caseSensitive
        ? toMap()
        : {
            for (final e in entries) e.key.toLowerCase(): e.value,
          };

    for (final key in keys) {
      final k = caseSensitive ? key : key.toLowerCase();
      final v = map[k];
      if (v == null) {
        if (!map.containsKey(k)) {
          return false;
        }
        if (ignoreNulls) {
          return false;
        }
      }
    }

    return true;
  }

  /// Parses the latest value of [key] as a mini document comprised of
  /// `key=value` items separated by [itemSep] (default ',').
  ///
  /// - Items without '=' are ignored.
  /// - Keys are right-trimmed when [trimKey] is true.
  /// - When [trimItems] is true, leading/trailing whitespace around each item
  ///   is removed before parsing.
  /// - Values are parsed with the same rules as the main parser (quoted values
  ///   can contain '='; unquoted values are trimmed; empty -> null).
  /// - Returns [FlatDocument.empty] when the key is missing or value is empty.
  FlatDocument getDocument(
    String key, {
    String itemSep = ',',
    bool trimItems = true,
    bool trimKey = true,
    bool decodeEscapesInQuoted = false,
  }) {
    final v = this[key];
    if (v == null || v.isEmpty) {
      return FlatDocument.empty();
    }

    final out = <FlatEntry>[];
    for (var item in splitRespectingQuotes(v, itemSep)) {
      if (trimItems) item = item.trim();
      if (item.isEmpty) {
        continue;
      }

      final idx = indexOfUnquoted(item, Constants.pairSeparator);
      if (idx < 0) {
        continue;
      } // ignoriert Non-Pairs (wie vorher)

      var k = item.substring(0, idx);
      if (trimKey) {
        k = k.trimRight();
      }
      if (k.isEmpty) {
        continue;
      }

      final value = parseValue(
        item.substring(idx + 1),
        decodeEscapesInQuoted: decodeEscapesInQuoted,
      );

      out.add(FlatEntry(k, value));
    }

    return out.isEmpty ? FlatDocument.empty() : FlatDocument(out);
  }

  /// Parses the latest value of [key] as a list of mini-documents, where
  /// each item is itself a comma-separated `key=value` document, and items
  /// are separated by [listSep] (default '|').
  ///
  /// Example:
  /// servers = host=foo,port=8080 | host=bar,port=9090
  ///
  /// - Items without '=' are ignored.
  /// - Keys are right-trimmed when [trimKey] is true.
  /// - When [trimItems] is true, leading/trailing whitespace around each item
  ///   is removed before parsing.
  /// - Values are parsed like the main parser (quoted values may include '=')
  /// - Returns null when [key] missing; empty list when present but no valid items.
  List<FlatDocument>? getListOfDocuments(
    String key, {
    String listSep = '|',
    String itemSep = ',',
    bool trimItems = true,
    bool trimKey = true,
    bool decodeEscapesInQuoted = false,
  }) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final documents = <FlatDocument>[];
    for (var chunk in splitRespectingQuotes(v, listSep)) {
      if (trimItems) {
        chunk = chunk.trim();
      }
      if (chunk.isEmpty) {
        continue;
      }

      // Quote-aware Zerlegung in key=value Items (wie in getDocument)
      final subEntries = <FlatEntry>[];
      for (var item in splitRespectingQuotes(chunk, itemSep)) {
        if (trimItems) {
          item = item.trim();
        }
        if (item.isEmpty) {
          continue;
        }

        final idx = indexOfUnquoted(item, Constants.pairSeparator);
        if (idx < 0) {
          continue;
        }

        var k = item.substring(0, idx);
        if (trimKey) {
          k = k.trimRight();
        }
        if (k.isEmpty) {
          continue;
        }

        final value = parseValue(
          item.substring(idx + 1),
          decodeEscapesInQuoted: decodeEscapesInQuoted,
        );
        subEntries.add(FlatEntry(k, value));
      }

      if (subEntries.isNotEmpty) {
        documents.add(FlatDocument(subEntries));
      }
    }

    return documents;
  }

  /// Tries to convert the latest value for [key] using [convert].
  ///
  /// Returns `null` if:
  /// - the key is missing,
  /// - the (optionally trimmed) value is empty (when [ignoreEmpty] is true), or
  /// - the converter throws.
  ///
  /// Example:
  /// ```dart
  /// final timeout = doc.getAs('timeout', Duration.parse);
  /// ```
  T? getAs<T>(
    String key,
    FlatConverter<T> convert, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) {
    final raw = this[key];
    if (raw == null) {
      return null;
    }

    final s = trim ? raw.trim() : raw;
    if (s.isEmpty && ignoreEmpty) {
      return null;
    }

    try {
      return convert(s);
    } catch (_) {
      return null;
    }
  }

  /// Converts the latest value for [key] using [convert], or returns [defaultValue]
  /// when the key is missing, the (optionally trimmed) value is empty
  /// (when [ignoreEmpty] is true), or the converter throws.
  ///
  /// Never throws.
  ///
  /// Example:
  /// ```dart
  /// final port = doc.getAsOr('port', int.parse, 8080);
  /// ```
  T getAsOr<T>(
    String key,
    FlatConverter<T> convert,
    T defaultValue, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) {
    final v = getAs<T>(
      key,
      convert,
      trim: trim,
      ignoreEmpty: ignoreEmpty,
    );

    return v ?? defaultValue;
  }

  /// Strictly converts the latest value for [key] using [convert].
  ///
  /// Throws a [FormatException] with context when:
  /// - the key is missing,
  /// - the (optionally trimmed) value is empty (when [ignoreEmpty] is true), or
  /// - the converter throws.
  ///
  /// Uses `.explain(key: ..., got: ...)` to attach context.
  ///
  /// Example:
  /// ```dart
  /// final timeout = doc.requireAs('timeout', Duration.parse);
  /// ```
  T requireAs<T>(
    String key,
    FlatConverter<T> convert, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) {
    final raw = this[key];
    if (raw == null) {
      throw const FormatException('Missing value').explain(key: key, got: null);
    }

    final s = trim ? raw.trim() : raw;
    if (ignoreEmpty && s.isEmpty) {
      throw const FormatException('Empty value').explain(key: key, got: raw);
    }

    try {
      return convert(s);
    } catch (e) {
      throw FormatException('Invalid value')
          .explain(key: key, got: raw, cause: e);
    }
  }

  /// Tries to convert the latest value for [key] using a context-aware [converter].
  ///
  /// Returns `null` if:
  /// - the key is missing,
  /// - the (optionally trimmed) value is empty (when [ignoreEmpty] is true), or
  /// - the [converter] returns `null`.
  ///
  /// Use [requireAsWith] for a strict variant.
  ///
  /// Example:
  /// ```dart
  /// final db = doc.getAsWith('db', (raw, key, d) {
  ///   if (raw == null) return null;
  ///   // e.g. "host=localhost, port=5432"
  ///   final sub = FlatConfig.parse(raw).toMap();
  ///   final host = sub['host'];
  ///   final port = int.tryParse(sub['port'] ?? '');
  ///   return (host != null && port != null) ? (host, port) : null;
  /// });
  /// ```
  T? getAsWith<T>(
    String key,
    FlatAdvancedConverter<T> converter, {
    bool trim = false,
    bool ignoreEmpty = false,
  }) {
    final raw = this[key];
    final processed = raw == null ? null : (trim ? raw.trim() : raw);
    if (ignoreEmpty && (processed?.isEmpty ?? true)) {
      return null;
    }

    return converter(processed, key, this);
  }

  /// Strictly converts using a context-aware [converter]; throws on missing/empty/invalid.
  ///
  /// Throws a [FormatException] with context when:
  /// - the key is missing,
  /// - the (optionally trimmed) value is empty (when [ignoreEmpty] is true), or
  /// - the [converter] returns `null`.
  ///
  /// Example:
  /// ```dart
  /// final ratio = doc.requireAsWith('video', (raw, key, d) {
  ///   if (raw == null) return null;
  ///   final parts = raw.split(':');
  ///   if (parts.length != 2) return null;
  ///   final w = double.tryParse(parts[0]);
  ///   final h = double.tryParse(parts[1]);
  ///   return (w != null && h != null && h != 0) ? (w / h) : null;
  /// });
  /// ```
  T requireAsWith<T>(
    String key,
    FlatAdvancedConverter<T> converter, {
    bool trim = false,
    bool ignoreEmpty = false,
    String message = 'Invalid value',
  }) {
    final raw = this[key];
    if (raw == null) {
      throw const FormatException('Missing value').explain(key: key, got: null);
    }

    final processed = trim ? raw.trim() : raw;
    if (ignoreEmpty && processed.isEmpty) {
      throw const FormatException('Empty value').explain(key: key, got: raw);
    }

    final result = converter(processed, key, this);
    if (result == null) {
      throw FormatException(message).explain(key: key, got: raw);
    }

    return result;
  }

  /// Lazily converts all values for [key] (see [valuesOf]) using [convert].
  ///
  /// Skips invalid items without throwing:
  /// - null entries,
  /// - (optionally trimmed) empty strings when [ignoreEmpty] is true,
  /// - items whose [convert] throws.
  ///
  /// This is the permissive variant; use [requireAllAs] for strict mode.
  ///
  /// Example:
  /// ```dart
  /// final sizes = doc.getAllAs('size', (s) => int.parse(s)).toList();
  /// ```
  Iterable<T> getAllAs<T>(
    String key,
    FlatConverter<T> convert, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) sync* {
    for (final raw in valuesOf(key)) {
      if (raw == null) {
        continue;
      }

      final s = trim ? raw.trim() : raw;
      if (ignoreEmpty && s.isEmpty) {
        continue;
      }

      try {
        yield convert(s);
      } catch (_) {
        // skip invalid item
      }
    }
  }

  /// Strictly converts all values for [key]. Throws on the first invalid item:
  /// - missing (null) entry,
  /// - (optionally trimmed) empty value when [ignoreEmpty] is true,
  /// - converter error.
  ///
  /// Returns a list with the converted values in input order.
  ///
  /// Example:
  /// ```dart
  /// final ports = doc.requireAllAs('port', int.parse);
  /// ```
  List<T> requireAllAs<T>(
    String key,
    FlatConverter<T> convert, {
    bool trim = true,
    bool ignoreEmpty = true,
  }) {
    final out = <T>[];
    for (final raw in valuesOf(key)) {
      if (raw == null) {
        throw const FormatException('Missing value')
            .explain(key: key, got: null);
      }

      final s = trim ? raw.trim() : raw;
      if (ignoreEmpty && s.isEmpty) {
        throw const FormatException('Empty value').explain(key: key, got: raw);
      }

      try {
        out.add(convert(s));
      } catch (e) {
        throw FormatException('Invalid value')
            .explain(key: key, got: raw, cause: e);
      }
    }

    return out;
  }
}
