# flatconfig

*A minimal `key = value` configuration parser for Dart and Flutter.*

[![Pub Version](https://img.shields.io/pub/v/flatconfig.svg)](https://pub.dev/packages/flatconfig)
[![Tests](https://github.com/grumpypixel/flatconfig/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/grumpypixel/flatconfig/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Dart Version](https://img.shields.io/badge/dart-%3E%3D3.8.0-blue.svg)](https://dart.dev)
[![Pub Points](https://img.shields.io/pub/points/flatconfig?label=pub%20points)](https://pub.dev/packages/flatconfig/score)

> Flat, human-friendly `key = value` configuration — inspired by 👻 [Ghostty](https://ghostty.org), simpler than INI or TOML.

Configuration files people edit by hand should be boring to read and impossible
to misread. **flatconfig** keeps the whole format at `key = value`: one flat
namespace, no sections, no nesting, no parser magic. Every line means what it
says.

It is built for tools, CLIs and Flutter apps that need structured settings
without a heavy dependency — with duplicate keys, comments, explicit resets,
recursive includes and lossless round-tripping.

## Highlights

- 🧩 **Tiny syntax** — `key = value`, quoted when it has to be
- 📦 **Pure Dart**, two small dependencies (`meta`, and `path` for includes)
- 🌍 **Web and WASM safe**, with file I/O in a library you simply do not import
- 📝 **Duplicate keys** preserved, in order — which is how overriding works
- 🔐 **Strict or lenient**, with one `onIssue` channel for every problem
- ✅ **Valid by construction** — an entry the format cannot write out cannot be built
- 🧠 **One accessor rule** — `getX`, `getXOr`, `requireX`, for every type
- 🔌 **`getAs` for everything else** — your converter, the same three shapes
- 🔁 **Round-trips**, including the values that look like they should break it
- 📁 **Includes** from disk, memory, assets or the network, through a resolver

## Install

```sh
dart pub add flatconfig
```

```dart
import 'package:flatconfig/flatconfig.dart';
```

### Which library to import

The package is four libraries. Each of the three below re-exports the core, so
one import usually does.

| Import | Adds to the core | Web / WASM |
| --- | --- | --- |
| `package:flatconfig/flatconfig.dart` | the core: documents, parsing, encoding, accessors | ✅ |
| `package:flatconfig/flatconfig_includes.dart` | following `config-file` through a resolver | ✅ |
| `package:flatconfig/flatconfig_accessors.dart` | `DateTime`, `Duration`, `Uri`, JSON, enum accessors | ✅ |
| `package:flatconfig/flatconfig_io.dart` | reading and writing files | ❌ needs `dart:io` |

Only `flatconfig_io.dart` touches `dart:io`, so a browser build simply does not
import it. There is no stub that compiles and then throws at runtime.

## Quick start

```dart
import 'package:flatconfig/flatconfig.dart';

void main() {
  const raw = '''
# Example configuration
background = 343028
foreground = f3d735
shader = bloom
shader = vignette
texture =
''';

  final doc = FlatDocument.parse(raw);

  print(doc['background']);         // 343028
  print(doc['shader']);             // vignette — the last write wins
  print(doc.allValues('shader'));   // [bloom, vignette]
  print(doc['texture']);            // null
  print(doc.lookup('texture'));     // FlatLookup.reset() — cleared on purpose
}
```

Typed reads follow one rule: `getX` returns `null`, `getXOr` returns your
fallback, `requireX` throws.

```dart
final port     = doc.getIntOr('port', 8080);
final gamma    = doc.requireDouble('gamma');
final features = doc.getList('features');            // "a, b, c" → [a, b, c]
final accent   = doc.getAs('accent', parseMyColor);  // anything else
```

Files hang off `File`, so a path is spelled the way it is everywhere else in
Dart:

```dart
import 'dart:io';
import 'package:flatconfig/flatconfig_io.dart';

final doc = await File('main.conf').parseWithIncludes();
await File('out.conf').writeFlat(doc.withValue('font-size', '16'));
```

## The format in one screen

```conf
# Comments start with "#" and take a whole line.
# Whitespace around "=" is ignored.

background = 343028
font-family = "FiraCode Nerd Font"   # quotes preserve spaces, "=" and "#"

# A key may appear more than once. The last one wins,
# and every value stays readable through allValues().
shader = bloom
shader = vignette

# An empty value is an explicit reset, not an empty string.
texture =
empty = ""

# Pull in another file. Later includes win; "?" marks it optional.
config-file = theme.conf
config-file = ?user.conf
```

Keys are case-sensitive. The comment prefix is configurable; the `=` separator
is not. [`SPEC.md`](SPEC.md) is the normative definition, and its Appendix A
tracks where the implementation still deviates from it.

## Compared to INI and TOML

| Feature | INI / TOML | flatconfig |
| --- | --- | --- |
| Sections / tables | ✅ `[section]` | 🚫 one flat namespace |
| Nested data | ✅ tables or dotted keys | 🚫 flat, but `fromData` flattens for you |
| Comments | `#` or `;` | `#` only, whole-line |
| Lists | ✅ `[1, 2, 3]` | ✅ `getList()`, or repeat the key |
| Types | explicit | strings plus typed accessors |
| Includes | ❌ (TOML: preprocessors only) | ✅ built in, recursive, pluggable |
| Duplicate keys | ❌ usually an error | ✅ the mechanism for overriding |

Leaving out sections is the point rather than a shortcut: a single flat
namespace makes merging, overriding and diffing trivial, and keeps the files
readable for people who do not write code.

> Think of it as the portable 20% of INI that covers 90% of real configuration.

## Documentation

| Page | What is in it |
| --- | --- |
| [Parsing](doc/parsing.md) | entry points, options, strict vs lenient, reporting problems |
| [The document model](doc/document-model.md) | entries and the resolved view, the three states, editing, collapse, prefixes |
| [Accessors](doc/accessors.md) | the three shapes, custom converters, the optional accessors |
| [Includes](doc/includes.md) | `config-file`, merge policies, writing a resolver |
| [Building documents](doc/building.md) | from maps, the environment and nested data; encoding and round-tripping |
| [Files and platforms](doc/platform-io.md) | the `File` API, and what runs on the web |
| [Migrating from 0.5.x](doc/migration.md) | the complete rename and removal table |
| [Working on flatconfig](doc/development.md) | tests, coverage, CI, house rules |
| [`SPEC.md`](SPEC.md) | the format, normatively |

Runnable examples live in [`example/`](example), including a Flutter app in
[`example/flatconfig_flutter`](example/flatconfig_flutter).

## Design philosophy

Flat, simple, predictable. No nested scopes, no hidden semantics, no parser
magic. The goal is not to replace JSON, YAML or TOML, but to be the lightweight
middle ground: friendly enough to hand-edit, strict enough to automate.

Where that forces a choice, it is resolved towards the reader of the file. A
malformed line is reported rather than swallowed, a value that cannot survive a
round trip is refused when it is written rather than mangled when it is read,
and a key that was cleared on purpose is distinguishable from one nobody ever
mentioned.

> flatconfig keeps your config files boring — in the best possible way. 😌

## See also

- 👻 [Ghostty configuration format](https://ghostty.org/docs/config)
- 🧰 [Configuration libraries on pub.dev](https://pub.dev/packages?q=config)

## License

[MIT](LICENSE)

---

Made with ❤️ in Dart.
Contributions welcome on [GitHub → grumpypixel/flatconfig](https://github.com/grumpypixel/flatconfig)
