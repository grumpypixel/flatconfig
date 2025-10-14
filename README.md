# flatconfig
*A minimal `Ghostty`-style `key = value` configuration parser for Dart and Flutter.*

[![Pub Version](https://img.shields.io/pub/v/flatconfig.svg)](https://pub.dev/packages/flatconfig)
[![Tests](https://github.com/grumpypixel/flatconfig/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/grumpypixel/flatconfig/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart Version](https://img.shields.io/badge/dart-%3E%3D3.0.0-blue.svg)](https://dart.dev)
[![Pub Points](https://img.shields.io/pub/points/flatconfig?label=pub%20points)](https://pub.dev/packages/flatconfig/score)

flatconfig is a flat, minimal `key = value` configuration format for Dart and Flutter — easy to read, trivial to hand-edit, and simple to round-trip.
Inspired by 👻 [Ghostty](https://ghostty.org)-style configuration files.

It offers a clean, predictable alternative to verbose formats like YAML or JSON,
with support for duplicate keys, comments, and empty values (`key =`) that act as explicit (null) resets.
Perfect for tools, CLIs, and Flutter apps that need structured settings without heavy dependencies.

## Highlights

- 🧩 **Tiny syntax:** `key = value` (values may be quoted)
- 📦 **Pure Dart**, minimal dependencies (`meta`; `path` for includes)
- 📝 **Supports duplicates**, preserves entry order
- 🔐 **Strict or lenient parsing**, optional callbacks for invalid lines
- 📁 **Async/sync file I/O**, handles UTF-8 BOM and any line endings
- 🧠 **Typed accessors** for durations, bytes, colors, URIs, JSON, enums, ratios, percents, lists, sets, maps, and ranges
- 🧱 **Collapse helpers** to deduplicate keys (first occurrence or last write)
- 🧰 **Pretty-print and debug dumps**
- 🔁 **Round-tripping** with configurable quoting and escaping
- 🧮 **Factories for easy creation** — build documents from maps, entries, or single pairs
- ✅ **Strict validation** for non-empty keys, toggleable via `strict: false`

## Usage

Add `flatconfig` as a dependency to your `pubspec.yaml`:

```yaml
dependencies:
  flatconfig: ^0.1.3 # check pub.dev for the latest version
```

Then import it in your Dart code:

```dart
import 'package:flatconfig/flatconfig.dart';
```

## Quick Start 🚀

```dart
import 'package:flatconfig/flatconfig.dart';

void main() {
  // Each key can appear multiple times; latest value wins.
  const raw = '''
  # Example configuration
  background = 343028
  foreground = f3d735
  shader = bloom
  shader = vignette
  texture =
  ''';

  final doc = FlatConfig.parse(raw);

  print(doc['background']);         // → 343028
  print(doc['foreground']);         // → f3d735
  print(doc['shader']);             // → vignette (latest value wins)
  print(doc.valuesOf('shader'));    // → ["bloom", "vignette"]
  print(doc.has('shader'));         // → true
  print(doc['texture']);            // → null (explicit reset)
  print(doc.hasNonNull('texture')); // → false
}
```

## Syntax

flatconfig uses a minimal `key = value` syntax, designed to be easy to read and edit by hand.

```conf
# The syntax is "key = value".
# Whitespace around "=" is ignored.
background = 343028
foreground = f3d735

# Comments start with "#" and are valid only on their own line.
# Blank lines are ignored.

shader = bloom
shader = vignette

# Empty values reset the key to null.
texture =
```

Notes:

- Keys are case-sensitive: background ≠ Background
- Values can be quoted or unquoted:

```conf
font-family = "FiraCode Nerd Font"
font-family = FiraCode Nerd Font
```

- Quoted values preserve inner whitespace and `=`
- Empty (unquoted) values are interpreted as explicit resets (`null`)
- Lines without = are ignored unless `strict: true` is enabled
- The comment prefix (`#`) and the key-value separator (`=`) can be customized

## Validation & Strict Mode

`FlatEntry` and `FlatDocument` validate all keys by default — empty or whitespace-only keys
throw an error. You can disable this behavior by passing `strict: false`.

```dart
// Throws an ArgumentError:
FlatEntry.validated('   ', 'oops');

// Works fine:
final relaxed = FlatDocument.fromMap({'': 'x', 'theme': 'dark'}, strict: false);
print(relaxed.toMap()); // {theme: dark}
```

All factory constructors respect `strict`:

- `FlatDocument.fromMap(...)`
- `FlatDocument.fromEntries(...)`
- `FlatDocument.merge([...])`
- `FlatDocument.single('key', value: 'x')`

## Data Model

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
  String? operator [](String key);  // same as toMap()[key]
  Iterable<String> get keys;        // first occurrence order
  List<String?> valuesOf(String key);
  bool has(String key);
  bool hasNonNull(String key);
}
```

### Document Factories

`FlatDocument` provides several constructors for flexible creation:

```dart
// From a Map
final fromMap = FlatDocument.fromMap({'theme': 'dark', 'font-size': '14'});

// From a list of entries
final fromEntries = FlatDocument.fromEntries([
  FlatEntry('theme', 'dark'),
  FlatEntry('accent', 'mint'),
]);

// Merge multiple documents
final merged = FlatDocument.merge([fromMap, fromEntries]);

// Single key/value
final single = FlatDocument.single('theme', value: 'dark');
```

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

## Splitting into Multiple Files

flatconfig supports **recursive includes** using the `config-file` key, just like [Ghostty](https://ghostty.org/docs/config).

Use `File.parseWithIncludes()` or `parseFileWithIncludes()` to automatically load and merge related configuration files.

This lets you split your configuration into smaller files that are loaded automatically — with support for **optional includes**, **nested includes**, and **cycle detection**.

```conf
# main.conf
app-name = MyFlutterApp
version = 1.0.1
config-file = theme.conf
config-file = ?user.conf  → optional
theme = custom  → won't override included theme
```

```conf
# theme.conf
theme = dark
background = 343028
foreground = f3d735
```

```conf
# reset.conf (example of null value blocking)
background =  → resets background to null
theme = light
```

When `reset.conf` is included, the empty `background =` line sets the background to `null`.
This means any later `background = ...` entries in the main file are blocked — effectively resetting the background value inherited from includes.

```dart
import 'dart:io';
import 'package:flatconfig/flatconfig.dart';

Future<void> main() async {
  final doc = await File('main.conf').parseWithIncludes();
  print(doc['theme']);       // → dark
  print(doc['background']);  // → null (reset by reset.conf)
  print(doc['user-name']);   // from optional include
}
```

### Include Semantics

- **One include per line** — each `config-file = ...` line may reference exactly one file path. Comma-separated or space-separated include lists (e.g. `config-file = a.conf, b.conf`) are *not supported* and will be treated as a single literal path.
- **Includes are processed after the current file**, so later lines in the current file do *not override* keys from included files.
- **Null values from includes block later entries** — when an included file sets a key to `null` (empty value like `key =`), any later entries in the main file with the same key are blocked. This is part of the "Tail does not override includes" semantics and allows includes to explicitly reset configuration values.
- **Multiple includes** are allowed. When several included files define the same key, *the later include wins*.
- Includes are **recursive**, with a defensive maximum depth (`maxIncludeDepth`, default *64*). The root file starts at depth 0.
- A leading `?` marks an include as *optional* (`config-file = ?user.conf`) — missing optional files are silently skipped.
- Relative include paths are resolved relative to the including file's directory.
- Absolute paths are used as-is.
- Circular includes raise a `CircularIncludeException`.

> Customize the key name via `FlatParseOptions(includeKey: 'include')`.

Notes:

- On *Windows* (and optionally macOS), include cycle detection uses *case-insensitive paths*.
- Quoted include paths (e.g. `config-file = "path/to/theme.conf"`) are supported. Escapes inside quotes (like `\"` or `\\`) are not decoded unless explicitly implemented.
- Web builds are supported for in-memory parsing (`FlatConfig.parse()`), but *file includes* require `dart:io` and are not available in Flutter Web.

## Encoding & Round-Tripping

```dart
final out = doc.encode(
  options: const FlatEncodeOptions(
    quoteIfWhitespace: true,  // quote values with outer spaces
    alwaysQuote: false,        // force quotes on all non-null values
    escapeQuoted: false,       // escape \" and \\ while encoding
  ),
);
```

> Note: Encoding does not include a BOM and does not preserve comments or blank lines.

### Writing to Files

```dart
await File('out.conf').writeFlat(doc);
File('out.conf').writeFlatSync(doc);
```

- Lossy by design: comments and blank lines are not preserved
- `null` values are written as key `=`

## Duplicate Keys → Collapse

```dart
final collapsedFirst = doc.collapse(); // keep first position, last value wins
final collapsedLast  = doc.collapse(order: CollapseOrder.lastWrite);

final keepMulti = doc.collapse(multiValueKeys: {'shader'});
final dynamicMulti = doc.collapse(isMultiValueKey: (k) => k.startsWith('mv_'));

final dropResets = doc.collapse(dropNulls: true); // omit keys with null
```

## Typed Accessors (Examples)

```dart
final b  = doc.getBytes('size');          // SI (kB/MB/...) and IEC (KiB/MiB/...)
final cc = doc.getColor('color');         // {a, r, g, b}
final d  = doc.getDuration('timeout');    // "150ms", "2s", "5m", "3h", "1d"
final e  = doc.getEnum('mode', {'prod': 1, 'dev': 2}); // case-insensitive
final hc = doc.getHexColor('color');      // #rgb, #rgba, #rrggbb, #aarrggbb → 0xAARRGGBB
final j  = doc.getJson('payload');        // parsed JSON object
final p  = doc.getPercent('alpha');       // "80%", "0.8", "80" → 0.8
final r  = doc.getRatio('video');         // "16:9" → 1.777...
final u  = doc.getUri('endpoint');        // relative or absolute URI

// Collections
final l = doc.getList('features');        // "A, b , a" → ["A","b","a"]
final s = doc.getSet('features');         // → {"a","b"} (case-insensitive)

// Ranges
final dir = doc.getDoubleInRange('gamma', min: 0.5, max: 2.0);
final iir = doc.getIntInRange('retries', min: 0, max: 10);

// Require* methods throw FormatException on missing/invalid values
final siz = doc.requireBytes('size');
final tim = doc.requireDuration('timeout');
final hex = doc.requireHexColor('color');
final pct = doc.requirePercent('alpha');
```

### Mini-Documents & Pairs

```dart
// Single key=value inside a value
final pair = doc.getKeyValue('shader');
// e.g. "bloom=intense" → ('bloom', 'intense')

// Mini-document in a single value
final sub = doc.getDocument('db'); // "host=localhost, port=2358"
print(sub.toMap());                // {host: localhost, port: 2358}

// List of mini-documents
final effects = doc.getListOfDocuments('shaders');
// "name=bloom,intensity=0.8 | name=vignette,intensity=0.5"
// → List<FlatDocument>

// Host[:port]
final hp = doc.getHostPort('listen'); // "127.0.0.1:8080" → ('127.0.0.1', 8080)
```

> **🧠 Note:**
> `getMap()` performs a simple, non-quoted split by commas and equals signs — it is _not quote-aware_.
> For parsing quoted key-value pairs (e.g. `name="My App", version="1.0"`), use `getDocument()` or `getListOfDocuments()`, which are quote-aware and handle escaped quotes correctly.

```dart
// getMap() - NOT quote-aware (simple splitting)
final map = doc.getMap('data'); // "key1="value, with, commas", key2=normal"
// Result: {'key1': '"value', 'key2': 'normal'} // Wrong! Missing middle part

// getDocument() - IS quote-aware (respects quotes)
final sub = doc.getDocument('data'); // "key1="value, with, commas", key2=normal"
// Result: [FlatEntry('key1', 'value, with, commas'), FlatEntry('key2', 'normal')]
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

## Format Rules & Limits

- Only full-line comments (default prefix `#`)
- Inline comments are not supported
- Lines without `=` are ignored in non-strict mode
- Unquoted values are trimmed; quoted values preserve whitespace and `=`
- Empty unquoted values become `null` (explicit reset)
- Encoding is lossy (comments and blank lines are dropped)

## See Also

- 👻 [Ghostty Configuration Format](https://ghostty.org/docs/config)
- 🧰 [Dart Configuration File Libraries on pub.dev](https://pub.dev/packages?q=config)

## License

[MIT](LICENSE)

---

Made with ❤️ in Dart.
Contributions welcome on [GitHub → grumpypixel/flatconfig](https://github.com/grumpypixel/flatconfig)
