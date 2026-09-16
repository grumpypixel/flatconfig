# flatconfig

*A minimal `key = value` configuration parser for Dart and Flutter.*

[![Pub Version](https://img.shields.io/pub/v/flatconfig.svg)](https://pub.dev/packages/flatconfig)
[![Tests](https://github.com/grumpypixel/flatconfig/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/grumpypixel/flatconfig/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart Version](https://img.shields.io/badge/dart-%3E%3D3.8.0-blue.svg)](https://dart.dev)
[![Pub Points](https://img.shields.io/pub/points/flatconfig?label=pub%20points)](https://pub.dev/packages/flatconfig/score)

> Flat, human-friendly `key=value` configuration format for Dart & Flutter — inspired by 👻 [Ghostty](https://ghostty.org), simpler than INI or TOML.

**flatconfig** offers a flat, minimal `key = value` format for Dart and Flutter — easy to read, trivial to hand-edit, and simple to round-trip.

It provides a clean, predictable alternative to verbose formats like YAML or JSON,
with support for duplicate keys, comments, and empty values (`key =`) that act as explicit (null) resets.
Perfect for tools, CLIs, and Flutter apps that need structured settings without heavy dependencies.

## Highlights

- 🧩 **Tiny syntax:** `key = value` (values may be quoted)  
- 📦 **Pure Dart**, minimal dependencies (`meta`; `path` for includes)  
- 📝 **Supports duplicates**, preserves entry order  
- 🔐 **Strict or lenient parsing**, optional callbacks for invalid lines  
- ✅ **Valid by construction** — an entry the format cannot write out cannot be built  
- 📁 **Async/sync file I/O**, handles UTF-8 BOM and any line endings  
- 🧠 **Typed accessors** for durations, bytes, colors, URIs, JSON, enums, ratios, percents, lists, sets, maps, and ranges  
- 🧱 **Collapse helpers** to deduplicate keys (first occurrence or last write)  
- 🔁 **Round-tripping** with configurable quoting and escaping  
- 🧮 **Factories for easy creation** — build documents from maps, entries, or nested data (`fromMapData`)  
- 🧰 **Pretty-print and debug dumps**  

## Usage

Add `flatconfig` as a dependency to your `pubspec.yaml`:

```yaml
dependencies:
  flatconfig: ^0.5.0 # check pub.dev for the latest version
```

Then import it in your Dart code:

```dart
import 'package:flatconfig/flatconfig.dart';
```

### Platform Notes

`flatconfig` is fully **Web/WASM-safe** – all core parsing and document features
(`FlatConfig`, `FlatDocument`, accessors, encoding, etc.) work on every platform.

🖥️ **File & Include APIs (I/O only):**
`parseFlatFile(...)`, `parseFileWithIncludes(...)`, `File.parseFlat()` etc.
require `dart:io` and **are not available on Flutter Web or WASM.**

#### Works everywhere

Use the in-memory API for web and WASM environments:

```dart
const raw = 'theme = dark';
final doc = FlatConfig.parse(raw);
print(doc['theme']); // dark
```

> For includes on Web/WASM, use `MemoryIncludeResolver` with `FlatConfigResolverIncludes.parseStringWithIncludes()`.

#### Works on Dart VM / Flutter Desktop / CLI

File helpers and include processing are available on platforms that support the `dart:io` library:

```dart
final doc = await parseFlatFile('config.conf');
final merged = await parseFileWithIncludes('main.conf');
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
  print(doc.allValues('shader'));   // → ["bloom", "vignette"]
  print(doc.containsKey('shader')); // → true
  print(doc['texture']);            // → null (explicit reset)
  print(doc.lookup('texture'));     // → FlatLookup.reset()
}
```

## Optional Sugar (File extensions, I/O only)

```dart
import 'dart:io';
import 'package:flatconfig/flatconfig.dart';

Future<void> main() async {
  final doc = await File('config.conf').parseFlat();
  final inc = await File('main.conf').parseWithIncludes(); // includes + merges recursively
}
```

## Web/WASM usage (in-memory)

```dart
import 'package:flatconfig/flatconfig.dart';

void main() {
  const raw = 'theme = dark';
  final doc = FlatConfig.parse(raw);
  print(doc['theme']); // dark
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

**Notes:**

- Keys are case-sensitive: background ≠ Background  
- Values can be quoted or unquoted:  

  ```conf
  font-family = "FiraCode Nerd Font"
  font-family = FiraCode Nerd Font
  ```

- Quoted values preserve inner whitespace and `=`  
- Empty (unquoted) values are interpreted as explicit resets (`null`)  
- Lines without `=` are ignored unless `strict: true` is enabled  
- The comment prefix (`#`) can be customized; the key-value separator (`=`) is fixed  

## Comparison to INI and TOML

While `flatconfig` looks familiar if you’ve used INI or TOML, it’s intentionally **simpler** — focused on readability, portability, and minimal dependencies.

| Feature | INI / TOML | flatconfig |
| ------- | ---------- | ---------- |
| Sections / Tables | ✅ `[section]` or `[table]` | 🚫 none — single flat namespace |
| Nested data | ✅ via tables or dotted keys | 🚫 flat only |
| Comments | `#` or `;` | `#` only |
| Arrays / Lists | ✅ `[1, 2, 3]` etc. | ✅ via `getList()` / `getSet()` helpers |
| Data types | explicit (bool, int, float, etc.) | string-based + typed accessors |
| Includes | ❌ (TOML only via preprocessors) | ✅ built-in recursive `config-file` support |
| Complexity | moderate | minimal & predictable |

`flatconfig` intentionally omits sections and nested scopes — every key exists in a single flat namespace.
This makes merging, overriding, and diffing configurations trivial, and keeps files readable even for non-developers.

> Think of it as “*the minimal, portable 20 % of INI/TOML that covers 90 % of real-world use cases.”*

## Validation

`FlatEntry` rejects anything the format cannot write out and read back: an empty
or padded key, a key containing `=`, `#` or a quote, and a value spanning a line
break. There is no lenient mode, because there is nothing to be lenient about —
such an entry cannot be built at all.

```dart
FlatEntry('   ', 'oops');   // ArgumentError: key has leading whitespace
FlatEntry('k', 'a\nb');     // ArgumentError: value must not contain a line break
FlatEntry.reset('theme');   // fine: writes `theme =`
```

Leniency belongs to the parser, where hand-edited files actually arrive. There
`FlatParseOptions.strict` decides whether a malformed line throws or is skipped.
A document built in code from a key the format cannot represent is a bug at the
call site, not input to be tolerated.

> **Note:**
> `FlatDocument.fromMap(...)` and `FlatConfig.fromDynamicMap(...)` are **shallow** factories.
> They convert only one level of key-value pairs and do not traverse nested maps or lists.
> For structured data that needs to be flattened into key paths (e.g. `window.width = 5120`),
> use [`FlatConfig.fromMapData`](#deep-flattening-with-frommapdata).

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
  List<String?> allValues(String key);
  bool containsKey(String key);
  FlatLookup lookup(String key);    // absent vs. reset vs. present
}
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

flatconfig supports **recursive includes** using the `config-file` key, similar to Ghostty.

- Files are processed **top-to-bottom**, but include directives are expanded **at the end of the current file** (depth-first).
- **Later includes override earlier includes** (“later include wins”).
- **Tail entries after the first include cannot override keys set by includes**.
- Use `config-file = ?path.conf` for **optional includes** — missing files are ignored.
- An empty right-hand side (`key =`) is an **explicit null reset**: it clears the current value but does **not** block later assignments (non-blocking by default).
- Includes support **nesting**, **optionals**, and **cycle detection**.

```conf
# main.conf
app-name = MyApp
version = 1.0.1

config-file = theme.conf
config-file = ?user.conf   # optional

# NOTE: Tail entries after the first include cannot override keys set by includes:
theme = custom             # this will be ignored if 'theme' was set by an include
```

```conf
# theme.conf
theme = dark
background = 343028
foreground = f3d735
```

**Result for main.conf:**

- `theme` → `dark` (from `theme.conf`; tail `theme = custom` is ignored)
- `background` → `343028`
- `foreground` → `f3d735`

**Explicit null resets are non-blocking:**

```conf
# reset.conf
background =              # explicit null reset
theme = light
```

When `reset.conf` is included before a later assignment, it clears the previous value but does **not** prevent later values from being set again by **later includes** (or by tail entries that don’t conflict with include keys).

```conf
# main-with-reset.conf
config-file = theme.conf
config-file = reset.conf

background = 101010       # later wins (non-blocking reset)
```

**Result for main-with-reset.conf:**

- `theme` → `light` (from `reset.conf`, later include wins)
- `background` → `101010` (tail overrides the reset)
- `foreground` → `f3d735` (from `theme.conf`)

Define local overrides **before** any include if you want them to take effect:

```conf
# main-pre-override.conf
theme = custom            # placed before includes → allowed
config-file = theme.conf  # later include could still override if it sets theme
```

In that case, whether `custom` survives depends on whether a later include sets `theme` (later include wins).

### Include Semantics

- **One include per line** — each `config-file = ...` line may reference exactly one file path. Comma-separated or space-separated include lists (e.g. `config-file = a.conf, b.conf`) are *not supported* and will be treated as a single literal path.  
- **Includes are processed after the current file**, so later lines in the current file do *not override* keys from included files.  
- **Explicit null resets are non-blocking** — when an included file sets a key to an empty value (`key =`), it clears the current value but does *not* prevent later entries from reassigning it. This allows includes to reset or clear configuration values without permanently blocking overrides.  
- **Multiple includes** are allowed. When several included files define the same key, *the later include wins*.  
- Includes are **recursive**, with a defensive maximum depth (`maxIncludeDepth`, default *64*). The root file starts at depth 0.  
- A leading `?` marks an include as *optional* (`config-file = ?user.conf`) — missing optional files are silently skipped.  
- Relative include paths are resolved relative to the including file’s directory.  
- Absolute paths are used as-is.  
- Circular includes raise a `CircularIncludeException`.  
  - For in-memory resolver parsing, cycle detection uses each unit’s canonical ID (`originId` / `IncludeUnit.id`). Prefer `mem:...` IDs for in-memory content; these are used for cycle detection.

#### Resolver Order (`CompositeIncludeResolver`)

When using a `CompositeIncludeResolver`, resolution follows a **first-hit-wins** strategy.  
Resolvers are tried in the order provided; the first resolver that returns a non-null `IncludeUnit` is used.

> Customize the include key via `FlatParseOptions(includeKey: 'include')`.

**Notes:**

- On *Windows* (and optionally macOS), include cycle detection uses *case-insensitive* paths.  
- **Include paths:** Quoted paths (e.g. `config-file = "path/with\\ spaces.conf"`) are supported, and simple escapes for quotes/backslashes are **decoded** for paths.  
- **Values:** Decoding of escapes inside quoted **values** is controlled by `FlatParseOptions.decodeEscapesInQuoted`.  
- Web builds are supported for in-memory parsing (`FlatConfig.parse()` and resolver-based includes), but *file includes* require `dart:io` and are not available in Flutter Web.

### In-Memory and Hybrid Includes

flatconfig also supports **in-memory include resolution**, allowing you to merge configurations without touching the filesystem.

Use `FlatConfigResolverIncludes.parseStringWithIncludes()` together with an `IncludeResolver`:

```dart
final resolver = MemoryIncludeResolver({
  'mem:base.conf': 'theme = dark',
  'mem:user.conf': 'theme = mint',
}, prefix: 'mem:');

final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
  'config-file = mem:base.conf\nconfig-file = ?mem:user.conf',
  resolver: resolver,
  originId: 'mem:main.conf',
);

print(doc['theme']); // mint
```

**Available resolvers:**

- `FileIncludeResolver()` — loads includes from the filesystem
- `MemoryIncludeResolver()` — reads from an in-memory map (Web/WASM-safe)
- `CompositeIncludeResolver([...])` — combines multiple sources (first-hit-wins)

This makes it easy to:

- write fully in-memory tests (no temp files)
- mix memory + filesystem configs (hybrid mode)
- or implement your own resolver (network, database, etc.)

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

> **Note:** Encoding does not include a BOM and does not preserve comments or blank lines.

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

## Working with Sections (`slice()` & `stripPrefix()`)

Use prefix-based helpers to extract or rewrite subdocuments from the resolved/latest view  
(unique keys; last value wins):

```dart
final doc = FlatConfig.parse('''
window.width = 1200
window.height = 800
theme = dark
''');

final win = doc.slice('window.');
// -> keys: window.width, window.height

final clean = doc.stripPrefix('window.');
// -> keys: width, height

final copy = doc.slice('');
// -> full clone (including duplicates)
```

Notes:

- Empty prefix clones the document, preserving **duplicates** and **order**.
- Matching is **case-sensitive** and **literal** (pass separators explicitly, e.g. `"window."`).
- Operates on the **resolved/latest view** (unique keys; last value wins).
- The source document is **never mutated**; methods return new documents.
- Combine both for modular configs or focused UI sections:

```dart
final section = doc.slice('window.').stripPrefix('window.');
```

## Accessors – At a Glance

- **Missing vs. empty:** Missing keys return `null`. An unquoted empty value (`key =`) is an explicit reset and also returns `null`; write `key = ""` for an empty string.  
- **`get*` vs. `require*`:** `get*` returns `null` or a default; `require*` throws a `FormatException` on missing or invalid values.  
- **Trimming:** String helpers (`getTrimmed…`) strip leading and trailing spaces.  
- **Booleans:** Supported values are `true/false`, `on/off`, `yes/no`, and `1/0` (case-insensitive).  
- **Ranges:** `get*InRange` validates and returns `null` when out of bounds; `require*InRange` throws.  
- **Quote awareness:** `getMap()` is not quote-aware, while `getDocument()` and `getListOfDocuments()` are.  

### Typed Accessors (Examples)

```dart
final b  = doc.getBytes('size');          // SI (kB/MB/...) & IEC (KiB/MiB/...)
final cc = doc.getColor('color');         // {a, r, g, b}
final d  = doc.getDuration('timeout');    // "150ms", "2s", "5m", "3h", "1d"
final e  = doc.getEnum('mode', {'prod': 1, 'dev': 2}); // case-insensitive
final hc = doc.getHexColor('color');      // #rgb, #rgba, #rrggbb, #aarrggbb → 0xAARRGGBB
final j  = doc.getJson('payload');        // parsed JSON (Map/List/num/bool/String)
final p  = doc.getPercent('alpha');       // "80%", "0.8", "80" → 0.8
final r  = doc.getRatio('video');         // "16:9" → 1.777…
final u  = doc.getUri('endpoint');        // relative or absolute URI

// Collections
final l  = doc.getList('features');       // "A, b , a" → ["A","b","a"]
final s  = doc.getSet('features');        // → {"a","b"} (case-insensitive, lower-cased unique)

// Ranges
final dir = doc.getDoubleInRange('gamma', min: 0.5, max: 2.0);
final iir = doc.getIntInRange('retries', min: 0, max: 10);

// Require* throw FormatException on missing/invalid values
final siz = doc.requireBytes('size');
final tim = doc.requireDuration('timeout');
final hex = doc.requireHexColor('color');
final pct = doc.requirePercent('alpha');
```

### More Accessors

```dart
// Strings
final t0 = doc.getTrimmed('title');
final t1 = doc.getTrimmedOrEmpty('title');
final t2 = doc.getStringOr('env', 'prod');
final t3 = doc.requireString('env');

// Booleans
final b0 = doc.getBoolOr('debug', false);
final b1 = doc.requireBool('debug');
final on  = doc.isEnabled('feature_x', defaultValue: true);
final off = doc.isDisabled('feature_y');

// Numbers
final n0 = doc.getIntOr('retries', 3);
final n1 = doc.requireInt('retries');
final n2 = doc.getDoubleOr('gamma', 1.0);
final n3 = doc.requireDouble('gamma');
final n4 = doc.getNum('threshold');
final n5 = doc.requireNum('threshold');

// Date/time & URI
final dt  = doc.getDateTime('start_at');   // ISO-8601 (Z/offset supported)
final rdt = doc.requireDateTime('start_at');
final ru  = doc.requireUri('endpoint');

// Colors (extras)
final color = doc.requireColor('color');   // {a,r,g,b}
final tuple = doc.getColorTuple('color');  // (a,r,g,b)
final rtpl  = doc.requireColorTuple('color');

// Ranges & clamping
final ri = doc.requireIntInRange('retries', min: 0, max: 10);
final rd = doc.requireDoubleInRange('gamma', min: 0.5, max: 2.0);
final ci = doc.getClampedInt('retries', min: 0, max: 10);

// Collections (extras)
final ls = doc.getListOrEmpty('features');
final ss = doc.getSetOrEmpty('features');
final m  = doc.getMap('overrides');        // "a:1, b: 2" → {a:1, b:2} (not quote-aware)
final me = doc.getMapOrEmpty('overrides');

// Validation & predicates
doc.requireKeys(['host', 'port']);         // throws on missing keys
final ok = doc.isOneOf('mode', {'prod', 'dev'});
```

### Custom Converters

`flatconfig` also lets you define your own typed accessors using generic converter callbacks.
This makes it easy to handle custom value formats or structured strings.

`getAs()` / `getAsOr()` / `requireAs()`

Convert a single key using your own converter:

```dart
// Safe: returns null on invalid or missing value
final port = doc.getAs('port', int.parse);

// With default fallback
final retries = doc.getAsOr('retries', int.parse, 3);

// Strict: throws on missing or invalid value
final timeout = doc.requireAs('timeout', Duration.parse);
```

You can combine these with `trim` and `ignoreEmpty` flags:

```dart
final title = doc.getAs('title', (s) => s.toUpperCase(), trim: true);
```

`getAsWith()` / `requireAsWith()`

Pass the entire document to a context-aware converter — useful for multi-field logic or sub-documents:

```dart
final db = doc.getAsWith('db', (raw, key, d) {
  if (raw == null) return null;
  final sub = FlatConfig.parse(raw).toMap();
  final host = sub['host'];
  final port = int.tryParse(sub['port'] ?? '');
  return (host != null && port != null) ? '$host:$port' : null;
});
```

```dart
final ratio = doc.requireAsWith('video', (raw, key, d) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final w = double.tryParse(parts[0]);
  final h = double.tryParse(parts[1]);
  return (w != null && h != null && h != 0) ? (w / h) : null;
});
```

`getAllAs()` / `requireAllAs()`

Convert all values for a key (see `allValues()`):

```dart
// Lenient: skips invalid items
final sizes = doc.getAllAs('size', int.parse).toList();

// Strict: throws if any item fails
final ports = doc.requireAllAs('port', int.parse);
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
> `getMap()` performs a simple, non-quoted split by commas and equals signs — it is *not quote-aware*.
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
doc.isEnabled('feature');                // "true", "yes", "on", "1" → true
doc.isEnabled('feature');                // "false", "no", "off", "0" → false
doc.isOneOf('env', {'dev', 'prod'});     // case-insensitive
doc.requireKeys(['host', 'port']);       // throws on first missing key
doc.hasAllKeys(['a', 'b', 'c']);         // returns true if all exist
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

## Document Factories

Once you're familiar with parsing, encoding, and format rules, you can also go the other way around —
by building configuration documents programmatically from structured data.

`flatconfig` provides flexible document factories that let you create
`FlatDocument` instances directly from maps, lists, or custom data models.
This is especially useful for tools, CLIs, or apps that need to export configuration files
from in-memory settings or serialize deeply nested objects into flat key paths.

### Shallow Factories

`FlatDocument` exposes several simple constructors for one-level data:

```dart
// From a simple key-value map (one entry per key)
final shallow = FlatDocument.fromMap({
  'theme': 'dark',
  'font-size': '14',
});

// From a dynamic map (typed values converted to strings)
final dynamicMap = FlatConfig.fromDynamicMap({
  'version': 2.0,
  'enabled': true,
  'tags': ['alpha', 'beta'],
});

// From a list of entries
final entries = FlatDocument.fromEntries([
  FlatEntry('theme', 'dark'),
  FlatEntry('accent', 'mint'),
]);

// Combine documents: last write wins, so appending is the merge
final merged = shallow.concat(entries);

// Single key/value pair
final single = FlatDocument.single('theme', value: 'dark');
```

> **Note:**
> `fromMap` and `fromDynamicMap` are *shallow* — they do not traverse nested maps or lists.
> Each map entry becomes exactly one key in the resulting document.
> For structured or nested data, use `fromMapData` below.

### Deep Flattening with `fromMapData`

When you need to flatten nested `Map` / `List` structures into flat key-path pairs, use `FlatConfig.fromMapData`.
It recursively traverses maps and lists, joining paths with `.` by default.

```dart
final doc = FlatConfig.fromMapData({
  'theme': 'dark',
  'window': {
    'width': 5120,
    'height': 2160,
  },
  'features': ['a', 'b', 'c'],
});

print(doc.toMap());
// {theme: dark, window.width: 5120, window.height: 2160, features: c}

for (final e in doc.entries) {
  print('${e.key} = ${e.value}');
}
// theme = dark
// window.width = 5120
// window.height = 2160
// features = a
// features = b
// features = c
```

### Configuration Options

`fromMapData` is highly customizable through `FlatMapDataOptions`:

| Option                  | Description                                                                  | Default              |
| ----------------------- | ---------------------------------------------------------------------------- | -------------------- |
| `separator`             | Path separator between nested keys                                           | `'.'`                |
| `listMode`              | Encode lists as multiple entries (`multi`) or as a single CSV string (`csv`) | `FlatListMode.multi` |
| `csvSeparator`          | Separator for CSV mode                                                       | `', '`               |
| `csvNullToken`          | Token for `null` in CSV lists (when `dropNulls == false`)                    | `''`                 |
| `dropNulls`             | Removes `null` values entirely                                               | `false`              |
| `valueEncoder`          | Global override for *any* value (highest priority)                           | `null`               |
| `onUnsupportedListItem` | How to handle composite items in lists (`encodeJson`, `skip`, `error`)       | `encodeJson`         |
| `keyEscaper`            | Escapes keys containing the path separator                                   | `null`               |
| `csvItemEncoder`        | Optional hook for quoting/escaping CSV items                                 | `null`               |

Example with advanced options:

```dart
final doc = FlatConfig.fromMapData(
  {
    'window': {'w': 5120, 'h': 2160},
    'colors': ['red', 'mint,green', 'blue'],
  },
  options: FlatMapDataOptions(
    listMode: FlatListMode.csv,
    csvSeparator: ',',
    csvItemEncoder: rfc4180CsvItemEncoder(','), // RFC-4180 safe quoting
    keyEscaper: (k) => k.replaceAll('.', r'\.'), // escape dots in keys
  ),
);

print(doc.toMap());
// {
//   window.w: 5120,
//   window.h: 2160,
//   colors: "red","mint,green","blue"
// }
```

### Helper: RFC-4180 CSV Quoting

`flatconfig` includes a small utility for **safe CSV encoding**
when working with `listMode: csv` or custom CSV formats.

```dart
final quoted = rfc4180Quote('value,with,commas', ',');
// → "value,with,commas"

final encoder = rfc4180CsvItemEncoder(',');
print(encoder('text,with,comma')); // → "text,with,comma"
```

The encoder automatically escapes quotes (`" → ""`)
and wraps any item containing the separator, quotes, or newlines in quotes.

> **💡 Tip:**
> Combine `fromMapData` with your app’s JSON models or structured settings
> to directly generate `.conf` files — ideal for CLIs, build tools, and user-editable configs.

### Round-Trip Workflow

Together with `FlatConfig.parse` and `FlatDocument.encode`,
`fromMapData` completes a full round-trip pipeline
between structured data and human-editable config files:

```text
Structured object  ⇄  FlatDocument  ⇄  .conf file
```

This lets you:

- Parse `.conf` files into maps and models.  
- Modify or merge them in code.  
- Re-emit them back to human-friendly flat files.  

Perfect for editors, generators, and configuration UIs
that need to stay both **machine-readable** and **human-editable**.

### Round-Trip Example

You can easily verify round-trip symmetry between parsing and encoding:

```dart
final doc = FlatConfig.fromMapData({'a': 1});
final roundTrip = FlatConfig.parse(doc.encode());
print(roundTrip.toMap()); // {a: 1}
```

## Design Philosophy

`flatconfig` follows a single guiding idea:
**flat, simple, predictable.**

No nested scopes, no hidden semantics, no parser magic.
Every line means exactly what it says — `key = value`.

This makes configuration files:

- easy to hand-edit and diff,  
- trivial to merge and override,  
- and safe to parse in any environment (Flutter, CLI, Web, or server).  

The goal isn’t to replace JSON, YAML, or TOML —
but to offer a lightweight middle ground: human-friendly like INI,
yet strict and structured enough for automated tools.

> `flatconfig` keeps your config files boring — in the best possible way. 😌

## See Also

- 👻 [Ghostty Configuration Format](https://ghostty.org/docs/config)
- 🧰 [Dart Configuration File Libraries on pub.dev](https://pub.dev/packages?q=config)

## License

[MIT](LICENSE)

---

Made with ❤️ in Dart.
Contributions welcome on [GitHub → grumpypixel/flatconfig](https://github.com/grumpypixel/flatconfig)
