import 'dart:convert' as convert;

import 'constants.dart';
import 'document.dart';
import 'document_accessors.dart';
import 'exceptions.dart';
import 'parser_utils.dart';

/// Ready-made converters for types that are common in configuration but not
/// part of the format.
///
/// These follow the same three shapes as the core accessors — `getX`, `getXOr`,
/// `requireX` — and each is a thin layer over [FlatDocumentAccessors.getAs].
/// They live in their own library so that a program parsing `key = value` pairs
/// does not carry a date parser it never calls.
///
/// ```dart
/// import 'package:flatconfig/flatconfig_accessors.dart';
///
/// final timeout = doc.getDurationOr('timeout', const Duration(seconds: 30));
/// ```
extension FlatDocumentOptionalAccessors on FlatDocument {
  // ── DateTime ─────────────────────────────────────────────────────────────

  /// Parses the latest value for [key] as an ISO-8601 timestamp.
  DateTime? getDateTime(String key) => getAs(key, DateTime.parse);

  /// Parses the latest value for [key] as an ISO-8601 timestamp, or returns
  /// [defaultValue].
  DateTime getDateTimeOr(String key, DateTime defaultValue) =>
      getDateTime(key) ?? defaultValue;

  /// Parses the latest value for [key] as an ISO-8601 timestamp.
  ///
  /// Throws a [FormatException] when the value is absent or malformed.
  DateTime requireDateTime(String key) {
    final dt = getDateTime(key);
    if (dt == null) {
      throw const FormatException(
        'Expected ISO-8601 DateTime',
      ).explain(key: key, got: this[key]);
    }

    return dt;
  }

  // ── Duration ─────────────────────────────────────────────────────────────

  /// Parses the latest value for [key] as a duration.
  ///
  /// Accepts a number with an optional unit suffix: `ms` (the default), `s`,
  /// `m`, `h` or `d`. Fractions are allowed and round to whole milliseconds,
  /// so `1.5s` is 1500 ms.
  Duration? getDuration(String key) {
    final v = this[key];
    if (v == null) {
      return null;
    }

    final match = Constants.durationRegex.firstMatch(v.trim().toLowerCase());
    if (match == null) {
      return null;
    }

    final value = tryParseFinite(match.group(1));
    if (value == null) {
      return null;
    }

    final unit = match.group(2) ?? 'ms';
    final perUnit = switch (unit) {
      'ms' => 1,
      's' => 1000,
      'm' => 60 * 1000,
      'h' => 60 * 60 * 1000,
      'd' => 24 * 60 * 60 * 1000,
      _ => null,
    };
    if (perUnit == null) {
      return null;
    }

    return Duration(milliseconds: (value * perUnit).round());
  }

  /// Parses the latest value for [key] as a duration, or returns [defaultValue].
  Duration getDurationOr(String key, Duration defaultValue) =>
      getDuration(key) ?? defaultValue;

  /// Parses the latest value for [key] as a duration.
  ///
  /// Throws a [FormatException] when the value is absent or malformed.
  Duration requireDuration(String key) {
    final d = getDuration(key);
    if (d == null) {
      throw const FormatException(
        'Expected duration',
      ).explain(key: key, got: this[key]);
    }

    return d;
  }

  // ── Uri ──────────────────────────────────────────────────────────────────

  /// Parses the latest value for [key] as a [Uri].
  Uri? getUri(String key) {
    final v = this[key];

    return v == null ? null : Uri.tryParse(v);
  }

  /// Parses the latest value for [key] as a [Uri], or returns [defaultValue].
  Uri getUriOr(String key, Uri defaultValue) => getUri(key) ?? defaultValue;

  /// Parses the latest value for [key] as a [Uri].
  ///
  /// Throws a [FormatException] when the value is absent or malformed.
  Uri requireUri(String key) {
    final u = getUri(key);
    if (u == null) {
      throw const FormatException(
        'Expected URI',
      ).explain(key: key, got: this[key]);
    }

    return u;
  }

  // ── JSON ─────────────────────────────────────────────────────────────────

  /// Decodes the latest value for [key] as JSON.
  Object? getJson(String key) =>
      getAs<Object?>(key, (v) => convert.jsonDecode(v) as Object?);

  /// Decodes the latest value for [key] as JSON, or returns [defaultValue].
  Object getJsonOr(String key, Object defaultValue) =>
      getJson(key) ?? defaultValue;

  /// Decodes the latest value for [key] as JSON.
  ///
  /// Throws a [FormatException] when the value is absent or malformed. A
  /// literal `null` document is indistinguishable from absence here and is
  /// therefore rejected too.
  Object requireJson(String key) {
    final j = getJson(key);
    if (j == null) {
      throw const FormatException(
        'Expected JSON',
      ).explain(key: key, got: this[key]);
    }

    return j;
  }

  // ── enum ─────────────────────────────────────────────────────────────────

  /// Maps the latest value for [key] through [mapping].
  ///
  /// Matching ignores case unless [caseInsensitive] is false.
  T? getEnum<T>(
    String key,
    Map<String, T> mapping, {
    bool caseInsensitive = true,
  }) {
    final v = this[key]?.trim();
    if (v == null) {
      return null;
    }

    if (!caseInsensitive) {
      return mapping[v];
    }

    final wanted = v.toLowerCase();
    for (final e in mapping.entries) {
      if (e.key.toLowerCase() == wanted) {
        return e.value;
      }
    }

    return null;
  }

  /// Maps the latest value for [key] through [mapping], or returns
  /// [defaultValue] when it matches nothing.
  T getEnumOr<T>(
    String key,
    Map<String, T> mapping,
    T defaultValue, {
    bool caseInsensitive = true,
  }) =>
      getEnum<T>(key, mapping, caseInsensitive: caseInsensitive) ??
      defaultValue;

  /// Maps the latest value for [key] through [mapping].
  ///
  /// Throws a [FormatException] when the value is absent or matches nothing.
  T requireEnum<T>(
    String key,
    Map<String, T> mapping, {
    bool caseInsensitive = true,
  }) {
    final v = getEnum<T>(key, mapping, caseInsensitive: caseInsensitive);
    if (v == null) {
      throw FormatException(
        'Expected one of ${mapping.keys.join(', ')}',
      ).explain(key: key, got: this[key]);
    }

    return v;
  }
}
