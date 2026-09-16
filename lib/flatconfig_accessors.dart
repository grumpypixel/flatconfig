/// Ready-made accessors for types that are common in configuration files but
/// are not part of the format itself: dates, durations, URIs, JSON and enums.
///
/// The core library deliberately stops at `String`, `int`, `double`, `bool` and
/// `List<String>`, plus `getAs` for everything else. This library is that
/// "everything else" for the five cases most projects end up writing anyway,
/// with the same `getX` / `getXOr` / `requireX` shapes.
///
/// ```dart
/// import 'package:flatconfig/flatconfig.dart';
/// import 'package:flatconfig/flatconfig_accessors.dart';
///
/// final doc = FlatDocument.parse('timeout = 30s');
/// print(doc.requireDuration('timeout')); // 0:00:30.000000
/// ```
///
/// Web- and WASM-safe: it adds parsing only, no `dart:io`.
library;

export 'src/optional_accessors.dart' show FlatDocumentOptionalAccessors;
