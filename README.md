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
- 🔐 **Strict or lenient parsing**, with one `onIssue` channel for every problem  
- ✅ **Valid by construction** — an entry the format cannot write out cannot be built  
- 📁 **Async/sync file I/O**, handles UTF-8 BOM and any line endings  
- 🧠 **Typed accessors** with one rule: `getX`, `getXOr`, `requireX` for every type  
- 🔌 **`getAs` for everything else** — your converter, the same three shapes  
- 🧱 **Collapse helpers** to deduplicate keys (first occurrence or last write)  
- 🔁 **Round-tripping** with configurable quoting and escaping  
- 🧮 **Factories for easy creation** — build documents from maps, entries, or nested data (`fromData`)  
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
(`FlatDocument`, accessors, encoding, etc.) work on every platform.

🖥️ **File & Include APIs (I/O only):**
`parseFlatFile(...)`, `parseFileWithIncludes(...)`, `File.parseFlat()` etc.
require `dart:io` and **are not available on Flutter Web or WASM.**

#### Works everywhere

Use the in-memory API for web and WASM environments:

```dart
const raw = 'theme = dark';
final doc = FlatDocument.parse(raw);
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

  final doc = FlatDocument.parse(raw);

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
  final doc = FlatDocument.parse(raw);
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
| Arrays / Lists | ✅ `[1, 2, 3]` etc. | ✅ via `getList()` / a `getAs()` converter |
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

### Reporting Parse Problems

In lenient mode a malformed line is skipped. `onIssue` tells you when that
happens, so "skipped" does not have to mean "silent":

```dart
final doc = FlatDocument.parse(source, options: FlatParseOptions(
  onIssue: (issue) => stderr.writeln(
    '${issue.line}:${issue.column} ${issue.message}',
  ),
));
```

Every `FlatIssue` carries a `kind`, the 1-based `line` and `column`, and the
`rawLine` as it appeared in the file. The kinds are `missingEquals`, `emptyKey`,
`invalidKey`, `unterminatedQuote` and `trailingAfterQuote`; more may be added,
so match the ones you care about rather than switching exhaustively.

Strict mode throws the matching `FlatParseException` subclass for exactly the
same inputs, which means you can develop against `onIssue` and ship with
`strict: true` without discovering new failures.

Throwing from the handler aborts the parse. That is how you build a policy
between the two — intolerant of one kind, forgiving of the rest:

```dart
FlatParseOptions(onIssue: (issue) {
  if (issue.kind == FlatIssueKind.invalidKey) {
    throw FormatException(issue.message, issue.rawLine, issue.column);
  }
});
```

> **Note:**
> `FlatDocument.fromMap(...)` is a **shallow** factory. It converts one level of
> key-value pairs and does not traverse nested maps or lists.
> For structured data that needs to be flattened into key paths (e.g. `window.width = 5120`),
> use [`FlatDocument.fromData`](#deep-flattening-with-fromdata).

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
final doc = FlatDocument.parse(
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
- Includes are **recursive**, with a defensive maximum depth (`FlatIncludeOptions.maxIncludeDepth`, default *64*). The root file starts at depth 0.  
- A leading `?` marks an include as *optional* (`config-file = ?user.conf`) — missing optional files are silently skipped.  
- Relative include paths are resolved relative to the including file’s directory.  
- Absolute paths are used as-is.  
- Circular includes raise a `CircularIncludeException`.  
  - For in-memory resolver parsing, cycle detection uses each unit’s canonical ID (`originId` / `IncludeUnit.id`). Prefer `mem:...` IDs for in-memory content; these are used for cycle detection.

#### Resolver Order (`CompositeIncludeResolver`)

When using a `CompositeIncludeResolver`, resolution follows a **first-hit-wins** strategy.  
Resolvers are tried in the order provided; the first resolver that returns a non-null `IncludeUnit` is used.

> Customize the include key via `includeOptions: FlatIncludeOptions(includeKey: 'include')`.
> Include behaviour lives on its own options class because parsing a string
> never follows an include: only the entry points that take a path or a resolver
> do.

**Notes:**

- On *Windows* (and optionally macOS), include cycle detection uses *case-insensitive* paths.  
- **Include paths:** Quoted paths (e.g. `config-file = "path/with\\ spaces.conf"`) are supported, and simple escapes for quotes/backslashes are **decoded** for paths.  
- **Values:** Decoding of escapes inside quoted **values** is controlled by `FlatParseOptions.decodeEscapesInQuoted`.  
- Web builds are supported for in-memory parsing (`FlatDocument.parse()` and resolver-based includes), but *file includes* require `dart:io` and are not available in Flutter Web.

### In-Memory and Hybrid Includes

flatconfig also supports **in-memory include resolution**, allowing you to merge configurations without touching the filesystem.

Use `FlatConfigResolverIncludes.parseStringWithIncludesSync()` together with a
`SyncIncludeResolver`:

```dart
final resolver = MemoryIncludeResolver({
  'mem:base.conf': 'theme = dark',
  'mem:user.conf': 'theme = mint',
}, prefix: 'mem:');

final doc = FlatConfigResolverIncludes.parseStringWithIncludesSync(
  'config-file = mem:base.conf\nconfig-file = ?mem:user.conf',
  resolver: resolver,
  originId: 'mem:main.conf',
);

print(doc['theme']); // mint
```

**Available resolvers:**

- `FileIncludeResolver()` — loads includes from the filesystem
- `MemoryIncludeResolver()` — reads from an in-memory map (Web/WASM-safe)
- `SyncCompositeIncludeResolver([...])` — combines synchronous sources (first-hit-wins)
- `CompositeIncludeResolver([...])` — the same, when any source is asynchronous

#### Resolvers That Have to Await

A resolver reaching an HTTP endpoint, a database, or a Flutter asset behind
`rootBundle.loadString()` cannot answer synchronously. Implement
`IncludeResolver` and use the asynchronous entry point:

```dart
final class AssetResolver implements IncludeResolver {
  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async {
    final text = await rootBundle.loadString('config/${request.target}');
    return IncludeUnit(id: request.target, content: text);
  }
}

final doc = await FlatConfigResolverIncludes.parseStringWithIncludes(
  await rootBundle.loadString('config/app.conf'),
  resolver: AssetResolver(),
  originId: 'asset:app.conf',
);
```

`IncludeRequest.fromId` is the canonical id of the unit the directive appeared
in, which is what a path-based resolver uses to resolve relative targets.
Returning `null` is not an error; it means "not found", and whether that throws
depends on the `?` optional marker on the directive.

A resolver that *can* answer synchronously should extend `SyncIncludeResolver`
instead. It derives the async method for you, so one sync resolver works with
both entry points without a wrapper.

#### Merge Policy

`FlatIncludeOptions.mergePolicy` decides where an include's entries land:

| Policy | Behaviour |
|---|---|
| `ghostty` (default) | Every include's entries come after the file's own, and a line below an include cannot override a key it set. |
| `lastWins` | Each include expands where it is written, and later entries win. |

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
final doc = FlatDocument.parse('''
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

## Accessors

Every supported type offers exactly three shapes, with no exceptions:

| Shape | Missing, reset or unparseable | Use when |
|---|---|---|
| `getX(key)` | returns `null` | the value is genuinely optional |
| `getXOr(key, fallback)` | returns `fallback` | you have a sensible default |
| `requireX(key)` | throws `FormatException` | a missing value is a startup error |

The core library covers five types plus an escape hatch:

```dart
final name     = doc.getString('name');
final port     = doc.getIntOr('port', 8080);
final gamma    = doc.requireDouble('gamma');
final debug    = doc.getBoolOr('debug', false);
final features = doc.getList('features');       // "a, b , c" → ["a","b","c"]
```

- **Missing vs. reset vs. empty:** a missing key and a reset (`key =`) both read
  as `null`; use [`lookup()`](#data-model) when the difference matters. Write
  `key = ""` for an empty string.
- **Booleans:** `true/false`, `on/off`, `yes/no`, `1/0`, case-insensitive.
- **Doubles:** `NaN` and the infinities are rejected. They pass every range
  check by being unordered, which makes them worse than a parse failure.
- **Lists:** items are trimmed and empties dropped; both are switchable, as is
  the separator.

### Repeated Keys

`allAs()` converts every value recorded for a key, in file order:

```dart
// hosts = alpha
// hosts = beta
final hosts = doc.allAs('hosts', parseHost);   // [alpha, beta]
final none  = doc.allAs('absent', parseHost);  // null, not []
```

It returns `null` for a key that never appears, which an empty list cannot
express: a key mentioned only as a reset legitimately carries no values. One
unconvertible value throws rather than silently shortening the list.

### Custom Converters

`getAs()` extends the same three shapes to any type you can write a function
for. This is where everything beyond the five core types belongs:

```dart
// Safe: null on invalid or missing value
final color = doc.getAs('color', parseArgb);

// With a fallback
final retries = doc.getAsOr('retries', int.parse, 3);

// Strict: throws, naming the key and the offending value
final timeout = doc.requireAs('timeout', Duration.parse);
```

A converter signals rejection by throwing. An `Exception` means the config is
wrong and is reported as such; an `Error` propagates untouched, because a
`TypeError` or `ArgumentError` says the *converter* is wrong and swallowing it
would blame the user's file for your bug.

`trim` (default `true`) and `ignoreEmpty` (default `true`) control what reaches
the converter:

```dart
final title = doc.getAs('title', (s) => s.toUpperCase(), trim: false);
```

### Optional Accessors

Dates, durations, URIs, JSON and enums are common in configuration but are not
part of the format, so they ship in a separate library. Same three shapes:

```dart
import 'package:flatconfig/flatconfig_accessors.dart';

final start   = doc.getDateTime('start_at');                  // ISO-8601
final timeout = doc.getDurationOr('timeout', const Duration(seconds: 30));
final api     = doc.requireUri('endpoint');
final payload = doc.getJson('payload');
final mode    = doc.getEnum('mode', {'prod': 1, 'dev': 2});   // case-insensitive
```

`getDuration` accepts a number with an optional `ms`, `s`, `m`, `h` or `d`
suffix, defaulting to milliseconds. Fractions round to whole milliseconds, so
`1.5s` is 1500 ms.

Importing this library is optional: a program that only reads strings and
numbers does not carry a date parser it never calls.

### Anything Else Is a Converter

Colours, byte sizes, percentages, ratios, `host:port` pairs and inline
sub-documents used to ship as accessors. Each encodes a notation decision that
belongs to your application rather than to the format, and each is a few lines
behind `getAs`:

```dart
final size  = doc.getAs('cache', parseByteSize);   // "2MB" → 2000000
final color = doc.getAs('accent', parseArgb);      // "#336699cc" → 0xcc336699
final ratio = doc.getAs('video', (v) {
  final p = v.split(':');
  return double.parse(p[0]) / double.parse(p[1]);  // "16:9" → 1.777…
});
```

Range checks are the same idea — a validating converter, or `clamp()` on the
result:

```dart
final retries = doc.getAs('retries', (v) {
  final n = int.parse(v);
  if (n < 0 || n > 10) throw FormatException('out of range', v);
  return n;
});
```

See `example/accessors.dart` for worked converters.

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

// From typed values: stringify them yourself, so you decide the format
final typed = {'version': 2.0, 'enabled': true};
final fromTyped = FlatDocument.fromMap({
  for (final e in typed.entries) e.key: e.value.toString(),
});

// From a list of entries
final entries = FlatDocument.fromEntries([
  FlatEntry('theme', 'dark'),
  FlatEntry('accent', 'mint'),
]);

// Combine documents: last write wins, so appending is the merge
final merged = shallow.concat(entries);

// Single key/value pair
final single = FlatDocument([FlatEntry('theme', 'dark')]);
```

> **Note:**
> `fromMap` is *shallow* — it does not traverse nested maps or lists.
> Each map entry becomes exactly one key in the resulting document.
> For structured or nested data, use `fromData` below.

### From the Environment

`FlatDocument.fromEnvironment` builds a document from an environment-like map.
It is pure: pass `Platform.environment` yourself if that is what you mean, which
keeps it usable on Web and WASM and in tests.

```dart
final doc = FlatDocument.fromEnvironment(
  Platform.environment,
  options: FlatEnvOptions(
    prefix: 'APP_',
    stripMatchedPrefix: true,
    keySplitOn: '_',
    keyJoinWith: '.',
    lowercaseKeys: true,
  ),
);
// APP_WINDOW_WIDTH=1280 becomes window.width = 1280
```

Precedence runs `defaults` → environment → `merge`. The key rewrite runs last,
after interpolation, so a `${VAR}` names an environment variable rather than
whatever that variable's key was rewritten into.

Two defaults are deliberately cautious:

- **`interpolate` is off.** A variable's value is data the program did not
  write, and a `$` in it is more often a password than a reference. When you do
  turn it on, `missingVariable` decides what `${NOPE}` becomes: `preserve` (the
  default) leaves the placeholder visible, `empty` behaves like a POSIX shell,
  and `error` throws naming both the missing variable and the value referencing it.
- **A value containing a line break is an error.** No document can hold one
  (see [Format Rules & Limits](#format-rules--limits)). Set
  `multilineValue: MultilineValuePolicy.skip` to drop such a variable and keep
  the rest — useful when the environment carries a PEM key the program never reads.

### Deep Flattening with `fromData`

When you need to flatten nested `Map` / `List` structures into flat key-path pairs, use `FlatDocument.fromData`.
It recursively traverses maps and lists, joining paths with `.` by default.

```dart
final doc = FlatDocument.fromData({
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

`fromData` is highly customizable through `FlatDataOptions`:

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
final doc = FlatDocument.fromData(
  {
    'window': {'w': 5120, 'h': 2160},
    'colors': ['red', 'mint,green', 'blue'],
  },
  options: FlatDataOptions(
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
> Combine `fromData` with your app’s JSON models or structured settings
> to directly generate `.conf` files — ideal for CLIs, build tools, and user-editable configs.

### Round-Trip Workflow

Together with `FlatDocument.parse` and `FlatDocument.encode`,
`fromData` completes a full round-trip pipeline
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
final doc = FlatDocument.fromData({'a': 1});
final roundTrip = FlatDocument.parse(doc.encode());
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
