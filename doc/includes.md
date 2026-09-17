# Includes

A document can name other documents to pull in, with a `config-file` directive.
Where those live is a resolver's business: a file on disk, a map in memory, a
Flutter asset, an HTTP endpoint, a row in a database.

```conf
app-name = MyApp

config-file = theme.conf
config-file = ?user.conf    # optional: missing is fine
```

Reading includes from disk needs `dart:io` and is on the
[platform I/O page](platform-io.md). Everything else works anywhere, including
the browser:

```dart
import 'package:flatconfig/flatconfig_includes.dart';

final doc = parseWithIncludesSync(
  'config-file = theme.conf\nfont-size = 14',
  resolver: MemoryIncludeResolver({'theme.conf': 'background = 343028'}),
);
```

`parseWithIncludes` is the asynchronous entry point and takes an
`IncludeResolver`; `parseWithIncludesSync` takes a `SyncIncludeResolver`.

## The directive

- **One include per line.** `config-file = a.conf, b.conf` is not a list; it is
  a single path that happens to contain a comma.
- **A leading `?` marks it optional.** `config-file = ?user.conf` contributes
  nothing when the resolver has no answer, instead of throwing.
- **A directive naming nothing contributes nothing.** `config-file =`,
  `config-file = ?` and `config-file = ""` ask no resolver anything.
- **Quoted paths work**, and escapes for quotes and backslashes are decoded in
  them, subject to `decodeEscapesInQuoted` like any other quoted value. The
  quotes wrap the name; a name that contains quote characters of its own keeps
  them.
- **The key is configurable** through `FlatIncludeOptions(includeKey: 'include')`.

## Where the entries land

This is the part worth reading twice, because the default is inherited from
Ghostty and is not what most formats do.

Under `IncludeMergePolicy.ghostty`, the default, an included document's entries
come **after** the whole of the including document. A line written below an
include therefore cannot override a key that include sets.

```conf
# main.conf
config-file = theme.conf
theme = custom            # has no effect if theme.conf sets `theme`
```

```conf
# theme.conf
theme = dark
```

The result is `theme = dark`. Moving the line above the include does not change
that: an include's entries always land after the including document's own, so
whatever an include sets wins on lookup wherever your line sits.

Position decides something smaller — whether your line survives at all.

```dart
// theme = custom  above the include
doc.entries;             // theme=custom, theme=dark
doc['theme'];            // dark
doc.allValues('theme');  // [custom, dark]

// theme = custom  below the include
doc.entries;             // theme=dark — the local line is gone
doc.allValues('theme');  // [dark]
```

A line below an include is dropped outright when an include sets the same key,
and kept when none does. So the rule is: **under this policy, a key any include
mentions belongs to the includes.** To own a key locally, either do not let an
include set it, or switch policy.

Under `IncludeMergePolicy.lastWins`, each include expands where it is written
and ordinary last-write-wins applies, which is what a line below an include
looks like it should do:

```dart
parseWithIncludesSync(
  source,
  resolver: resolver,
  includeOptions: const FlatIncludeOptions(
    mergePolicy: IncludeMergePolicy.lastWins,
  ),
);
```

With several includes, the later one wins under both policies.

## Resets do not block later includes

An included file that clears a key with `key =` clears the current value without
locking it. A later include can set it again.

```conf
# main.conf
config-file = theme.conf    # background = 343028
config-file = reset.conf    # background =
config-file = late.conf     # background = 101010  ← wins
```

A reset is a value like any other, so it wins over an earlier include and loses
to a later one.

That also means a reset is a key an include set, with everything the previous
section says about such keys. Under the default policy, replacing `late.conf`
above with a local `background = 101010` after the includes leaves the key
reset, because the tail is dropped for keys the includes mention. Under
`lastWins` the local line wins.

## Depth and cycles

Includes are recursive, with a defensive maximum depth
(`FlatIncludeOptions.maxIncludeDepth`, default 64; the root document is depth 0).
Exceeding it raises `MaxIncludeDepthExceededException`.

A cycle raises `CircularIncludeException`. Detection uses each unit's canonical
id — the resolved path for files, `IncludeUnit.id` for anything else. For
in-memory content, give units stable ids (`mem:base.conf`) and pass `originId`
for the root, or two different documents can look like the same one.

On Windows, and on macOS volumes that are actually case-insensitive, path
identity folds case. The filesystem is asked rather than assumed, once per
directory: lowercasing every macOS path made `Foo.conf` and `foo.conf` collapse
into one id on a case-sensitive APFS volume, which invented cycles that were not
there.

## Resolvers

| Resolver | Source | Synchronous |
|---|---|---|
| `MemoryIncludeResolver` | a `Map<String, String>` | yes |
| `FileIncludeResolver` | the filesystem, needs `flatconfig_io.dart` | yes |
| `SyncCompositeIncludeResolver` | several synchronous resolvers, first hit wins | yes |
| `CompositeIncludeResolver` | several resolvers, at least one asynchronous | no |

```dart
final resolver = MemoryIncludeResolver({
  'mem:base.conf': 'theme = dark',
  'mem:user.conf': 'theme = mint',
}, prefix: 'mem:');

final doc = parseWithIncludesSync(
  'config-file = mem:base.conf\nconfig-file = ?mem:user.conf',
  resolver: resolver,
  originId: 'mem:main.conf',
);

print(doc['theme']);  // mint
```

Mixing sources is what the composites are for: a `SyncCompositeIncludeResolver`
over a memory resolver and a file resolver gives you defaults baked into the
binary with on-disk overrides, and tests that never touch a temp file.

### Writing one

A resolver that can answer immediately extends `SyncIncludeResolver`:

```dart
final class MyResolver extends SyncIncludeResolver {
  @override
  IncludeUnit? resolveSync(IncludeRequest request) =>
      IncludeUnit(id: request.target, content: _read(request.target));
}
```

The asynchronous `resolve` is derived from `resolveSync`, so one synchronous
resolver works with both entry points and needs no wrapper.

A resolver that has to await — an HTTP endpoint, a database, a Flutter asset
behind `rootBundle.loadString()` — implements `IncludeResolver` instead and is
used with the asynchronous entry point. A bundle is the clearest case, because
a synchronous resolver cannot be written against one at all:

```dart
final class AssetResolver implements IncludeResolver {
  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async {
    final text = await rootBundle.loadString('config/${request.target}');
    return IncludeUnit(id: request.target, content: text);
  }
}

final doc = await parseWithIncludes(
  await rootBundle.loadString('config/app.conf'),
  resolver: AssetResolver(),
  originId: 'asset:app.conf',
);
```

`IncludeRequest.target` is what the directive named and `IncludeRequest.fromId`
is the canonical id of the unit it appeared in, which is how a path-based
resolver resolves a relative target without tracking state of its own.

Returning `null` is not an error. It means "not found", and whether that throws
is decided by the `?` marker on the directive, not by the resolver. Anything
else that goes wrong — no permission, a malformed response, bytes that will not
decode — should be thrown, because the `?` marker says the include is optional,
not that failures are.

A resolver also owns the decoding of what it returns, since it hands over text.
`FlatStreamReadOptions.encoding` therefore does not reach it, and
`FileIncludeResolver` takes an encoding of its own:

```dart
FileIncludeResolver(encoding: latin1)
```

[`example/flatconfig_flutter`](../example/flatconfig_flutter) runs the bundle
version of this: `assets/config/app.conf` includes a theme asset and an
optional one that does not exist, and the tests cover both.

## Options

| Option | Default | Effect |
|---|---|---|
| `includeKey` | `'config-file'` | the directive key |
| `maxIncludeDepth` | `64` | recursion limit; the root is depth 0 |
| `mergePolicy` | `ghostty` | where an include's entries land |

These live on `FlatIncludeOptions` rather than `FlatParseOptions`, because
parsing a string never follows an include — only the entry points that take a
resolver or a path do. They take `includeOptions:` alongside `options:`.

## Caching

A document reached twice within one call is read once. That cache lives for the
length of the call and cannot be passed in, because its correctness depends on
the parse options, the encoding, the include key, the merge policy and what the
resolver answered — none of which a path-keyed map you hold across calls would
notice changing. An include edited between two calls is seen by the second.
