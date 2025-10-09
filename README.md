# flatconfig  
*A minimal Ghostty-style `key = value` configuration parser for Dart and Flutter.*  

[![Pub Version](https://img.shields.io/pub/v/flatconfig.svg)](https://pub.dev/packages/flatconfig)
[![Build Status](https://img.shields.io/github/actions/workflow/status/grumpypixel/flatconfig/test.yml?label=tests)](https://github.com/grumpypixel/flatconfig/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart Version](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue.svg)](https://dart.dev)
[![Pub Points](https://img.shields.io/pub/points/flatconfig?label=pub%20points)](https://pub.dev/packages/flatconfig/score)

flatconfig is a flat, minimal `key = value` configuration format for Dart and Flutter — easy to read, trivial to hand-edit, and simple to round-trip.
Inspired by 👻 [Ghostty](https://ghostty.org)-style configuration files.

It provides a simple, predictable alternative to verbose formats like YAML or JSON
for small, human-editable configuration files. Ideal for tools, CLIs, and Flutter apps
that need structured settings without heavy dependencies.

---

## Highlights

- 🧩 **Tiny syntax:** `key = value` (values may be quoted)
- 📦 **Pure Dart**, minimal dependencies (only `meta`)
- 📝 **Supports duplicates**, preserves entry order
- 🔐 **Strict or lenient parsing**, optional callbacks for invalid lines
- 📁 **Async/sync file I/O**, handles UTF-8 BOM and any line endings
- 🧠 **Typed accessors** for durations, bytes, colors, URIs, JSON, enums, ratios, percents, lists, sets, maps, and ranges
- 🧱 **Collapse helpers** to deduplicate keys (first occurrence or last write)
- 🧰 **Pretty-print and debug dumps**
- 🔁 **Round-tripping** with configurable quoting and escaping

---

## Usage

Add `flatconfig` as a dependency to your `pubspec.yaml`:

```yaml
dependencies:
  flatconfig: ^0.1.0
```

Then import it in your Dart code:

```dart
import 'package:flatconfig/flatconfig.dart';
```

---

## Quick Start 🚀

```dart
import 'package:flatconfig/flatconfig.dart';

void main() {
  const raw = '''
  # Example config
  background = 282c34
  keybind = ctrl+z=close_surface
  font-family =
  ''';

  final doc = FlatConfig.parse(raw);

  print(doc['background']);       // 282c34
  print(doc.valuesOf('keybind')); // [ctrl+z=close_surface]
  print(doc['font-family']);      // null → explicit reset
}
```

---

## Data model

```dart
// A single key/value pair (value may be null for explicit resets: "key =")
class FlatEntry {
  final String key;
  final String? value;
}

// A parsed document that preserves order and duplicates.
class FlatDocument {
  final List<FlatEntry> entries;

  // Frequently used:
  Map<String, String?> toMap();     // last value per key
  String? operator [](String key);  // shorthand for latest[key]
  Iterable<String> get keys;        // first occurrence order
  List<String?> valuesOf(String key);
  bool has(String key);
  bool hasNonNull(String key);
}
```

---

## Parsing

### Strings

```dart
final doc = FlatConfig.parse(
  raw,
  options: const FlatParseOptions(
    strict: false,                 // throw on invalid lines if true
    commentPrefix: '#',            // set '' to disable comments
    decodeEscapesInQuoted: false,  // decode \" and \\ inside quotes
  ),
);
```

- Lines starting with `commentPrefix` are ignored.
- Unquoted values are trimmed; quoted values preserve whitespace and `=`.
- Empty unquoted values → `null` (explicit reset).
- Duplicate keys are preserved; the last one wins in `toMap()`.

### Files

```dart
import 'dart:io';
import 'package:flatconfig/flatconfig.dart';

final fromFile = await parseFlatFile('config.conf');

// Sync variant:
final sync = File('config.conf').parseFlatSync();
```

- Handles UTF-8 BOM
- Supports `\n`, `\r\n`, and `\r` line endings
- Works with async and sync file I/O

---

## Encoding & Round-Tripping

```dart
final out = doc.encodeToString(
  options: const FlatEncodeOptions(
    quoteIfWhitespace: true,  // quote values with outer spaces
    alwaysQuote: false,        // force quotes on all non-null values
    escapeQuoted: false,       // escape \" and \\ while encoding
  ),
);
```

### Writing to Files

```dart
await File('out.conf').writeFlat(doc);
File('out.conf').writeFlatSync(doc);
```

- Lossy by design: comments and blank lines are not preserved
- `null` values are written as key `=`

---

## Duplicate Keys → Collapse

```dart
final collapsedFirst = doc.collapse(); // keep first position, last value wins
final collapsedLast  = doc.collapse(order: CollapseOrder.lastWrite);

final keepMulti = doc.collapse(multiValueKeys: {'keybind'});
final dynamicMulti = doc.collapse(isMultiValueKey: (k) => k.startsWith('mv_'));

final dropResets = doc.collapse(dropNulls: true); // omit keys with null
```

---

## Typed Accessors (Examples)

```dart
final b  = doc.getBytes('size');          // SI (kB/MB/...) and IEC (KiB/MiB/...)
final cc = doc.getColor('color');         // {a, r, g, b}
final d  = doc.getDuration('timeout');    // "150ms", "2s", "5m", "3h", "1d"
final e  = doc.getEnum('mode', {'prod': 1, 'dev': 2}); // case-insensitive
final co = doc.getHexColor('color');      // #rgb, #rgba, #rrggbb, #aarrggbb → 0xAARRGGBB
final j  = doc.getJson('payload');        // parsed JSON object
final p  = doc.getPercent('alpha');       // "80%", "0.8", "80" → 0.8
final r  = doc.getRatio('video');         // "16:9" → 1.777...
final u  = doc.getUri('endpoint');        // relative or absolute URI

// Collections
final list = doc.getList('features');     // "A, b , a" → ["A","b","a"]
final set  = doc.getSet('features');      // → {"a","b"} (case-insensitive)

// Ranges
final dIn  = doc.getDoubleInRange('gamma', min: 0.5, max: 2.0);
final iIn  = doc.getIntInRange('retries', min: 0, max: 10);

// Require* methods throw FormatException on missing/invalid values
final sz   = doc.requireBytes('size');
final ms   = doc.requireDuration('timeout');
final col  = doc.requireHexColor('color');
final pct  = doc.requirePercent('alpha');
```

### Mini-Documents & Pairs

```dart
// Single key=value inside a value
final pair = doc.getKeyValue('keybind');
// e.g. "ctrl+z=close_surface" → ('ctrl+z','close_surface')

// Mini-document in a single value
final sub = doc.getDocument('db'); // "host=foo, port=5432"
print(sub.toMap());                // {host: foo, port: 5432}

// List of mini-documents
final servers = doc.getListOfDocuments('servers');
// "host=foo,port=8080 | host=bar,port=9090" → List<FlatDocument>

// Host[:port]
final hp = doc.getHostPort('listen'); // "[::1]:8080" → ('::1', 8080)
```

### Other Convenience Methods

```dart
doc.getTrimmed('name');                  // trimmed value
doc.getStringOr('title', 'Untitled');    // default fallback
doc.isEnabled('feature_x');               // truthy/falsey strings
doc.isOneOf('env', {'dev', 'prod'});     // case-insensitive
doc.requireKeys(['host', 'port']);       // throws on first missing key
```

All `require*` methods throw a `FormatException` with context on invalid data.

---

## Debug & Pretty Print

```dart
print(doc.debugDump());
// [0] a = 1
// [1] b = null
// ...

print(doc.toPrettyString(
  includeIndexes: true,
  sortByKey: true,
  alignColumns: true,
));
```

---

## End-to-End Example

```dart
import 'dart:io';
import 'package:flatconfig/flatconfig.dart';

Future<void> main() async {
  final result = await parseFlatFile('config.conf');

  final doc = result;
  final updated = FlatDocument([
    ...doc.entries,
    const FlatEntry('note', '  keep whitespace  '),
  ]);

  await File('out.conf').writeFlat(updated);
}
```

---

## Format Rules & Limits

- Only full-line comments (default prefix `#`)
- Inline comments are not supported
- Lines without `=` are ignored in non-strict mode
- Unquoted values are trimmed; quoted values preserve whitespace and `=`
- Empty unquoted values become `null` (explicit reset)
- Encoding is lossy (comments and blank lines are dropped)

---

### See also

- 🧠 [Ghostty Configuration Format](https://ghostty.org/docs/config)
- 🧰 [Dart Configuration File Libraries on pub.dev](https://pub.dev/packages?q=config)

---

## License

[MIT](LICENSE)

---

Made with ❤️ in Dart.  
Contributions welcome on [GitHub → grumpypixel/flatconfig](https://github.com/grumpypixel/flatconfig)
