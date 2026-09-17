# Files, and what runs where

Reading and writing files needs `dart:io`, which is the one thing a web or WASM
program cannot have. That is why it lives in its own library.

```dart
import 'dart:io';
import 'package:flatconfig/flatconfig_io.dart';

final doc = await File('config.conf').parseFlat();
final withIncludes = await File('main.conf').parseWithIncludes();

await File('out.conf').writeFlat(doc.withValue('font-size', '16'));
```

## The file API

Everything hangs off `File`, so a path is spelled the way it is everywhere else
in Dart. There is no second spelling as a top-level function and no third as a
method on the document.

| Method | Does |
|---|---|
| `File.parseFlat()` | read and parse, asynchronously |
| `File.parseFlatSync()` | the same, synchronously |
| `File.parseWithIncludes()` | read, parse and follow `config-file` directives |
| `File.parseWithIncludesSync()` | the same, synchronously |
| `File.writeFlat(doc)` | encode and write, asynchronously |
| `File.writeFlatSync(doc)` | the same, synchronously |

They take the same `options:`, `readOptions:`, `writeOptions:` and
`includeOptions:` as their in-memory counterparts.

Reading handles a UTF-8 BOM and `\n`, `\r\n` and `\r` line endings. The encoding
is `utf8` unless `FlatStreamReadOptions.encoding` says otherwise, and writing
terminates lines with `\n` unless `FlatStreamWriteOptions.lineTerminator` does.

Includes from disk resolve relative paths against the including file's
directory; absolute paths are used as they are. Where that file is a symbolic
link, the directory is the one the link points at rather than the one it sits
in, so a configuration file symlinked out of a dotfiles repository finds its
neighbours there. `File.parseWithIncludes` and `FileIncludeResolver` follow the
same rule; they used to disagree. The rest of the include behaviour is on
[its own page](includes.md).

## Which library to import

| Import | Adds to the core | Web and WASM |
|---|---|---|
| `flatconfig.dart` | the core: parsing, encoding, documents, accessors | yes |
| `flatconfig_includes.dart` | resolver-based includes | yes |
| `flatconfig_accessors.dart` | `DateTime`, `Duration`, `Uri`, JSON, enum accessors | yes |
| `flatconfig_io.dart` | files, and the includes library with them | no |

Each of the three re-exports the core, so one import usually does. They are not
a chain: `flatconfig_io.dart` brings includes along, but the optional accessors
are their own branch, so a program that reads files *and* wants
`requireDuration` imports two.

## On the web

A web or WASM program imports anything except `flatconfig_io.dart`. There is no
stub that compiles and then throws at runtime — the library that needs
`dart:io` is simply absent from the import graph, so the failure happens at
build time if you reach for it, which is when you can still do something about it.

Includes work there too, through a resolver that reads from somewhere a browser
can reach:

```dart
import 'package:flatconfig/flatconfig_includes.dart';

final doc = parseWithIncludesSync(
  source,
  resolver: MemoryIncludeResolver({'theme.conf': 'background = 343028'}),
);
```

For Flutter assets, which have to be awaited, write an asynchronous resolver —
see [writing a resolver](includes.md#writing-one), and
[`example/flatconfig_flutter`](../example/flatconfig_flutter) for one that
resolves includes out of the asset bundle.

CI compiles the three web-safe libraries to JavaScript and to WASM on every
push, and runs the browser-compatible part of the suite in Chrome. A
`dart:io` import added three files deep would break that build rather than
someone's app.
