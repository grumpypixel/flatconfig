# Migrating from 0.5.x to 1.0.0

1.0.0 is a breaking release. It renames or removes a large part of the public
API, and a handful of things keep their spelling while changing what they do.
This guide is the table of what to type instead; `CHANGELOG.md` is the record of
why each change was made.

The work splits into two halves. The first is mechanical: the compiler names
every call site, you rename it, and you are done. The second is
[section 10](#10-changes-that-compile-and-behave-differently), which the
compiler cannot help with, because the code still compiles and does something
else. Read that section even if nothing else here applies to you.

A suggested order:

1. Fix the import (section 1). Most of the "undefined name" errors disappear.
2. Work through the compiler errors using sections 2 to 9.
3. Read section 10 and check your configuration files against it.

## 1. Fix the import first

0.5.x was one library. 1.0.0 is four, because the single library forced
`dart:io` onto every program that imported it, including web and WASM builds,
which got a stub that compiled and then threw at runtime.

| Import | Adds to the core | Web-safe |
|---|---|---|
| `package:flatconfig/flatconfig.dart` | the core itself: parsing, encoding, documents, core accessors | yes |
| `package:flatconfig/flatconfig_includes.dart` | resolver-based includes | yes |
| `package:flatconfig/flatconfig_accessors.dart` | `DateTime`, `Duration`, `Uri`, JSON, enum accessors | yes |
| `package:flatconfig/flatconfig_io.dart` | reading and writing files, and the includes library | no, needs `dart:io` |

Each of the three re-exports the core, so one import usually does. They are not
a chain, though: `flatconfig_io.dart` brings the includes library with it, but
the optional accessors are on their own branch. A program that reads files
*and* wants `requireDuration` imports two.

Pick the smallest one that covers what you use: if you touch the filesystem,
that is `flatconfig_io.dart`; if you never leave memory, `flatconfig.dart`.

```dart
// 0.5.x
import 'package:flatconfig/flatconfig.dart';

// 1.0.0, for a program that reads a file
import 'package:flatconfig/flatconfig_io.dart';
```

The conditional exports are gone with the split. On the web you no longer
import `flatconfig_io.dart` at all, rather than importing a stub that pretends
to work. If you relied on `'some text'.parseFlat()` — an extension on `Object`
the stub made look valid everywhere — use `FlatDocument.parse('some text')`.

## 2. `FlatConfig` is gone

It was an instantiable class holding no state, used as a static namespace. The
entry points are statics on the type they produce, the way `int.parse` and
`Uri.parse` are.

| 0.5.x | 1.0.0 |
|---|---|
| `FlatConfig.parse(s)` | `FlatDocument.parse(s)` |
| `FlatConfig.parseLines(lines)` | `FlatDocument.parseLines(lines)` |
| `FlatConfig.parseFromByteStream(s)` | `FlatDocument.parseBytes(s)` |
| `FlatConfig.parseFromStringStream(s)` | `FlatDocument.parseLineStream(s)` |
| `FlatConfig.parseEntries(s)` | `FlatDocument.streamEntries(s)` |
| `FlatConfig.parseEntriesFromStringStream(s)` | no public equivalent; use `streamEntries` on the bytes |
| `FlatConfig.fromMap(m)` | `FlatDocument.fromMap(m)` |
| `FlatConfig.fromMapData(m)` | `FlatDocument.fromData(m)` |
| `FlatConfig.fromEnvironment(env)` | `FlatDocument.fromEnvironment(env)` |
| `FlatConfig.fromDynamicMap(m)` | deleted, see below |
| `FlatConfig.parseLine`, `preprocessLine` | internal, behind a `src/` import |

`fromDynamicMap` guessed at `toString()` for arbitrary objects, which is a
formatting decision belonging to the caller. Map your values to `String?`
yourself and pass the result to `fromMap`.

## 3. Accessors: one rule, three shapes

The catalog had grown to 66 methods by crossing type against lenient, default,
strict, trimmed, ranged, clamped and empty. There is now one rule with no
exceptions: for every supported type `X`, exactly three methods.

| Shape | Returns |
|---|---|
| `getX(key)` | the value, or `null` |
| `getXOr(key, fallback)` | the value, or `fallback` |
| `requireX(key)` | the value, or throws |

`String`, `int`, `double`, `bool`, `List<String>` and the `getAs` family stay in
the core library. `DateTime`, `Duration`, `Uri`, JSON and enums move to
`flatconfig_accessors.dart` — same three shapes, one extra import.

Nothing about the call site changes for a method that survived: these were
extension members and are now members of `FlatDocument`, so `doc.getInt('n')`
reads the same. The extension names `FlatDocumentAccessors` and
`FlatDocumentExtensions` are gone, which matters only if you named them.

### Deleted, with replacements

Each of these encoded a notation decision the package should not own, and each
is a few lines behind `getAs`.

| 0.5.x | 1.0.0 |
|---|---|
| `getHexColor`, `getColor`, `getColorTuple` (+ `require*`) | `doc.getAs('bg', parseMyColor)` |
| `getPercent`, `getRatio`, `getBytes`, `getHostPort` (+ `require*`) | `getAs` with your own converter |
| `getNum`, `requireNum` | `doc.getInt(k) ?? doc.getDouble(k)` |
| `getIntInRange`, `getDoubleInRange`, `requireIntInRange`, `requireDoubleInRange` | a validating converter passed to `getAs` |
| `getClampedInt` | `doc.getInt(k)?.clamp(lo, hi)` |
| `getMap`, `getMapOrEmpty`, `getDocument`, `getListOfDocuments`, `getKeyValue` | a second, undocumented grammar; use `splitRespectingQuotes` and `indexOfUnquoted`, both now exported |
| `getSet`, `getSetOrEmpty` | `doc.getList(k)?.toSet()` |
| `getTrimmed`, `getTrimmedOrEmpty` | nothing: unquoted values already arrive trimmed, and whitespace inside quotes was deliberate |
| `getListOrEmpty` | `doc.getListOr(k, const [])` |
| `isEnabled`, `isDisabled` | `doc.getBoolOr(k, false)` |
| `isOneOf` | `values.contains(doc[k])` |
| `hasAllKeys`, `requireKeys` | `keys.every(doc.containsKey)` |
| `getAsWith`, `requireAsWith` | `getAs`; the document is already in scope where you call it |
| `getAllAs`, `requireAllAs` | `allAs` |

Two of these are worth a closer look before you replace them mechanically.

`isDisabled(k, defaultValue: true)` returned `false`, because the default was
negated along with the value. If you passed a default to it, the behaviour you
are replacing may not be the behaviour you wanted.

`allAs` is not a rename of `requireAllAs`. The old method returned `[]` for a
key that was never mentioned, which is also what it returned for a key present
only as a reset. `allAs` returns `null` for the first and `[]` for the second,
and throws on the first unconvertible value instead of dropping it, so a typo
in a list can no longer shorten it in silence.

## 4. A document is no longer an `Iterable`

`FlatDocument` used to extend `Iterable<FlatEntry>`, which put roughly forty
members on the type that silently meant "entries" — including a
`doc.contains(x)` testing for an entry while sitting next to a key lookup.

`entries`, `length`, `isEmpty` and `isNotEmpty` remain on the document.
Everything else moves to `doc.entries`, which says which view you mean.

```dart
// 0.5.x
for (final entry in doc) { … }
final first = doc.first;

// 1.0.0
for (final entry in doc.entries) { … }
final first = doc.entries.first;
```

Lookup also gained the names `Map` uses:

| 0.5.x | 1.0.0 |
|---|---|
| `doc.has(k)` | `doc.containsKey(k)` |
| `doc.valuesOf(k)` | `doc.allValues(k)` |
| `doc.hasNonNull(k)` | `doc[k] != null` |
| `doc.firstValueOf(k)` | `doc.allValues(k).first` |
| `doc.lastValueOf(k)` | `doc[k]` |
| `doc.iterator` | `doc.entries.iterator` |

## 5. `merge` is `concat`, and `collapse` is the other half

In a last-write-wins format, appending already is merging:
`a.concat(b).toMap()` equals `{...a.toMap(), ...b.toMap()}`. So the three merge
APIs collapse into one, and `merge(b, override: false)` is `b.concat(a)` read
from the other end.

| 0.5.x | 1.0.0 |
|---|---|
| `FlatDocument.merge([a, b])` | `a.concat(b)`, or `a + b` |
| `a.merge(b)` | `a.concat(b)` |
| `a.merge(b, override: false)` | `b.concat(a)` |

`concat` keeps every entry, so a key written by both documents appears twice:
the later one wins on lookup, and both survive in `allValues`. That is the
format's own semantics, and it is what you want while assembling.

When you are about to write the result back out, `collapse()` reduces it to one
entry per key. Without it, a program that merges and saves in a loop grows the
file on every run.

```dart
final effective = base.concat(user).concat(overrides);

print(effective['font-size']);          // the winner, no collapse needed
await File('out.conf').writeFlat(effective.collapse());
```

`collapse()` keeps the position of the first occurrence by default and takes
the winning value; pass `CollapseOrder.lastWrite` to move the key to where it
was last written instead.

Editing a single key has its own methods now, rather than rebuilding the entry
list by hand. `withValue(k, v)` leaves exactly one entry for the key,
`withEntry(e)` appends and keeps the earlier one, and `without(k)` removes every
occurrence. All three return a new document.

## 6. Reading and writing files

0.5.x had three spellings of one workflow: top-level functions, two extensions
on `File` in two different files, and save methods on `FlatDocument`. That is
three places for a change to miss one, and it did — `parseFileWithIncludes` and
`File.parseWithIncludes` both took a `cache:` argument while
`File.parseWithIncludesSync` never grew one. Everything now hangs off `File`.

| 0.5.x | 1.0.0 |
|---|---|
| `parseFlatFile(path)` | `File(path).parseFlat()` |
| `parseFlatFileSync(path)` | `File(path).parseFlatSync()` |
| `parseFileWithIncludes(path)` | `File(path).parseWithIncludes()` |
| `FlatConfigIncludes.parseWithIncludesFromPath(path)` | `File(path).parseWithIncludes()` |
| `FlatConfigIncludes.parseWithIncludesFromPathSync(path)` | `File(path).parseWithIncludesSync()` |
| `writeFlat(path, doc)` | `File(path).writeFlat(doc)` |
| `writeFlatSync(path, doc)` | `File(path).writeFlatSync(doc)` |
| `doc.saveToFile(path)` | `File(path).writeFlat(doc)` |
| `doc.saveToFileSync(path)` | `File(path).writeFlatSync(doc)` |

All of it needs `import 'package:flatconfig/flatconfig_io.dart';` and
`dart:io`.

## 7. Includes

Resolvers are asynchronous now. The sync-only interface excluded an HTTP
endpoint, a database row and a Flutter asset behind `rootBundle.loadString()`
by construction — a Flutter app could parse an asset config but never follow an
include from one.

| 0.5.x | 1.0.0 |
|---|---|
| `FlatConfigResolverIncludes.parseStringWithIncludes(…)` | top-level `parseWithIncludesSync(…)` — see the warning below |
| `IncludeResolver.resolve(String path)` | `Future<IncludeUnit?> resolve(IncludeRequest)` |
| a sync resolver | extend `SyncIncludeResolver`, implement `resolveSync` |
| `CompositeIncludeResolver` over sync resolvers | `SyncCompositeIncludeResolver` |
| `FlatParseOptions.includeKey` | `FlatIncludeOptions.includeKey` |
| `FlatParseOptions.maxIncludeDepth` | `FlatIncludeOptions.maxIncludeDepth` |
| `cache:` on any include entry point | removed, see section 10 |

Watch the name when you rename that first row. 0.5.x had one entry point,
`parseStringWithIncludes`, and it was synchronous. 1.0.0 has two, and the one
that kept the shorter name is the asynchronous one. Renaming to
`parseWithIncludes` therefore compiles and hands you a `Future<FlatDocument>`
where you had a document; `parseWithIncludesSync` is the direct replacement.

A resolver that can answer without awaiting extends `SyncIncludeResolver` and
implements `resolveSync`; the async `resolve` is derived from it, so one
resolver works with both entry points and needs no wrapper.

```dart
// 0.5.x
class MyResolver implements IncludeResolver {
  @override
  IncludeUnit? resolve(String path) => IncludeUnit(id: path, content: _read(path));
}

// 1.0.0
final class MyResolver extends SyncIncludeResolver {
  @override
  IncludeUnit? resolveSync(IncludeRequest request) =>
      IncludeUnit(id: request.target, content: _read(request.target));
}
```

`IncludeRequest` carries the `target` the directive named and the `fromId` of
the document that named it, so a resolver can resolve relative targets without
tracking state of its own.

`includeKey` and `maxIncludeDepth` moved because they sat on `FlatParseOptions`,
which made it look as though `FlatDocument.parse` might follow an include. It
never did. The entry points that do take `includeOptions:` alongside `options:`.

## 8. Error reporting is one channel

`onMissingEquals` and `onEmptyKey` covered two of the five things that can go
wrong in a line. An invalid key, an unterminated quote and trailing characters
after a quote were skipped with no way to find out.

```dart
// 0.5.x
FlatParseOptions(
  onMissingEquals: (line, raw) => log('no = on line $line'),
  onEmptyKey: (line, raw) => log('empty key on line $line'),
);

// 1.0.0
FlatParseOptions(onIssue: (issue) => log('${issue.line}: ${issue.message}'));
```

| 0.5.x | 1.0.0 |
|---|---|
| `OnErrorHandler` | `OnIssue` |
| `onMissingEquals` | `onIssue`, filtering `FlatIssueKind.missingEquals` |
| `onEmptyKey` | `onIssue`, filtering `FlatIssueKind.emptyKey` |
| nothing | `invalidKey`, `unterminatedQuote`, `trailingAfterQuote` |

A `FlatIssue` carries the kind, the 1-based line and column, the raw line and an
optional detail. Strict mode throws the matching `FlatParseException` for
exactly the same inputs, so `onIssue` in development and `strict: true` in
production cannot disagree about what counts as broken. Throwing from the
handler aborts the parse, which gives you the policies in between.

`FlatParseException` is now exported. It was the hidden base class of five
exported subclasses, so catching "any parse problem" meant listing them.

## 9. Renamed and removed elsewhere

| 0.5.x | 1.0.0 |
|---|---|
| `FlatMapDataOptions` | `FlatDataOptions` |
| `FlatEntry.validated(k, v)` | `FlatEntry(k, v)` — the ordinary constructor validates |
| `FlatEntry(k, null)` for a reset | `FlatEntry.reset(k)` reads clearer, both work |
| `FlatDocument.single(k, value: v)` | `FlatDocument.fromMap({k: v})` |
| `FlatDocument.validateEntries(…)` | deleted; the constructor validates |
| `strict:` on `fromMap`, `fromEntries`, `FlatDataOptions`, `single` | deleted; see section 10 |
| `FlatStreamWriteOptions.ensureTrailingNewline` | deleted; the encoder always terminates the last line |
| `getEnum(…, preNormalizedLowerMapping: …)` | deleted, an internal performance knob |
| `FileIncludes`, `FlatDocumentIO`, `FlatConfigIOStub`, `FileIncludesStub` | deleted with the conditional exports |

## 10. Changes that compile and behave differently

Nothing in this section will produce a compiler error. Each one is a case where
0.5.x accepted something and produced a result you probably did not want.

**A quoted value ends at its first unescaped quote, not the last.** In 0.5.x,
`a = "one" junk "two"` was accepted even in strict mode and yielded
`one" junk "two`. Check any configuration file with more than one quote on a
line.

**The empty string survives a round trip.** `FlatEntry('a', '')` used to encode
to a bare `a = ` and read back as `null` — that is, as a reset. It is now
quoted on the way out, so the distinction between "empty" and "cleared"
survives. Files written by 0.5.x still read the old way, because a bare `a = `
is a reset by definition; if you relied on it meaning the empty string, rewrite
those lines as `a = ""`.

**Escapes in quoted values are decoded by default.** `decodeEscapesInQuoted` and
`escapeQuoted` both default to `true` now. A value written with a `\n` in quotes
comes back as a line break rather than as two characters.

**Invalid keys throw instead of being written out.** `FlatEntry('#x', 'v')`
encoded to `#x = v` and read back as zero entries; `FlatEntry(' a ', 'v')` lost
its padding. Both were silent. The constructor now raises an `ArgumentError`,
and this is the change most likely to surface at runtime in code that builds
documents from user input — validate before constructing, or catch it.

Note the exception type: these are `ArgumentError` raised where the value is
written, not the `FormatException` 0.5.x raised one layer later. If you catch
`FormatException` around document construction, widen it.

**Values containing a line break are rejected.** `FlatEntry('a', 'x\ny')` was
accepted, encoded to two physical lines, and read back as `a` → `"x`. Quoting
cannot rescue it: the format is line-based.

**`strict` is gone from the factories, and they behave as `strict: true` did.**
Leniency now lives only in `FlatParseOptions.strict`, where hand-edited files
actually arrive. A document built in code from a key the format cannot
represent is a bug at the call site, not an input to tolerate.

**`FlatEntry` is no longer `const`.** A `const` constructor can only check
through `assert`, which release builds drop. A `const` document was never
constructible anyway, so the loss is limited to `const` lists of entries.

**Non-finite numbers are rejected.** `NaN` passed every range guard, because
every comparison with it is false. `NaN`, `Infinity` and `-Infinity` are now
invalid for every numeric accessor.

**Environment interpolation is off by default, and is now a value rather than a
flag.** `FlatEnvOptions.interpolate`, `missingVariable` and `varPattern` are one
`EnvInterpolation`, and its absence is what "off" means. A variable's value is
data your program did not write, and a `$` in it is more often a password than a
reference. If you used interpolation, pass
`interpolation: const EnvInterpolation()`; `FlatEnvOptions.defaultVarPattern` is
now `EnvInterpolation.defaultPattern`.

**A `${VAR}` naming nothing is preserved, not emptied.**
`{'URL': r'https://${NOPE}/api'}` used to yield `https:///api`, which looks like
a URL and fails somewhere else entirely. The unresolved placeholder now points
at the typo. `MissingVariablePolicy.empty` restores the old behaviour, and
`.error` throws, naming both the variable and the value referencing it.

**`FlatEnvOptions` copies the maps it is given.** `defaults` and `merge` were
stored by reference, so mutating your map changed the behaviour of options
already constructed. The constructor is no longer `const` as a result.

**The include cache is per-call and the `cache:` parameter is gone.** Its key
was a canonical path or unit id, but the result behind it also depended on the
parse options, the encoding, the include key, the merge policy and what the
resolver answered. Passing the same map to a second call with any of those
changed returned the earlier document. A file reached twice within one call is
still read once; an include edited between two calls is now seen by the second.

**Path identity no longer assumes macOS is case-insensitive.** Every macOS path
was lowercased, so on a case-sensitive APFS volume `Foo.conf` and `foo.conf`
collapsed into one canonical id, inventing include cycles and serving cached
content from the wrong file. The filesystem is asked once per directory now.

**Guards on public input throw in release builds.** A `commentPrefix` containing
a line break, a multi-character separator and an empty line terminator were
`assert`s, which release builds drop. They raise `ArgumentError` now, so a
release build rejects what a debug build rejected.

**The minimum SDK is 3.8.0.** It was a declared 3.0.0 that could never resolve:
`path` needs 3.4, `meta` needs 3.5 and `lints` needs 3.8.

## What you may want to adopt

Not required, but this release exists partly for these.

`doc.lookup(key)` tells apart a key that was never mentioned from one
explicitly cleared with `key =`. `doc[k] == null` cannot, and the difference
decides whether your default still applies. The sealed `FlatLookup`
(`FlatAbsent`, `FlatReset`, `FlatPresent`) switches exhaustively.

```dart
final fontSize = switch (doc.lookup('font-size')) {
  FlatPresent(:final value) => int.parse(value),
  FlatReset() => _systemDefault,   // deliberately cleared
  FlatAbsent() => _appDefault,     // never mentioned
};
```

`IncludeMergePolicy.lastWins` expands each include where it is written and lets
a later entry win, which is what most formats do and what a line written below
an include looks like it should do. The default stays `ghostty`.

`FlatEnvOptions` can transform keys: `EnvPrefix.strip`, `EnvKeySplit` and
`lowercaseKeys` turn `APP_WINDOW_WIDTH` into `window.width` without
post-processing. Settings that only mean something together travel together, so
"strip a prefix I never set" and "join without splitting" cannot be written —
the two `ArgumentError`s that used to answer them are gone, and an empty prefix
is refused rather than silently read as no prefix.

`splitRespectingQuotes` and `indexOfUnquoted` are exported. `SPEC.md` §5 pins
what they do, and they are what a custom `FlatConverter` needs in order to split
an inline list the way the parser would.
