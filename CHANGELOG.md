# Changelog

## 1.0.0

A breaking release, and the one that fixes the format's own defects rather
than only its API. `SPEC.md` is now the normative definition, and Appendix A
records where the implementation still departs from it.
[`doc/migration.md`](doc/migration.md) is the complete table of what to type
instead, derived from the public API delta against the `v0.5.0` tag.

Most of what follows is a compiler error on upgrade, which makes it easy to
work through. The dangerous part is the rest: quoted values now close at the
first unescaped quote, the empty string round-trips, and backslashes survive
the inline grammar — so a valid 0.5.x file can parse to something different
without anything failing to build. Section 10 of the migration guide collects
those.

Added:

- **The Flutter example resolves includes out of the asset bundle.** Its
  `app.conf` includes a theme asset and an optional one that does not exist,
  through an `AssetBundleIncludeResolver` that can only be asynchronous —
  a bundle hands out its contents through a `Future`, so no synchronous
  resolver can be written against one. `MyApp` is a `StatefulWidget` now and
  caches the load, instead of starting a fresh one on every rebuild.
- **A documentation set under `doc/`** — `parsing.md`, `document-model.md`,
  `accessors.md`, `includes.md`, `building.md`, `platform-io.md` and
  `development.md`. The README drops from 932 lines to 194 and indexes them.
  Every example was written against a running probe rather than from memory,
  which is how the two defects above were found.
- **`doc/migration.md`** — the complete 0.5.x table of what to type instead,
  derived from the public API delta against the `v0.5.0` tag rather than from
  memory. Its last section lists the changes that compile and behave
  differently, which is the half the compiler cannot point at.
- **`FlatDocument.parseLineStream`** — the asynchronous counterpart to
  `parseLines`, for a source that hands out lines rather than bytes. The split
  into four libraries left it unexported while the synchronous `parseLines`
  stayed public, which was a hole rather than a decision.
- **`FlatDocument.withValue`, `without` and `withEntry`** — editing a document
  no longer means rebuilding its entry list by hand. All three return a new
  document and leave the original alone. `withValue` leaves exactly one entry
  for the key, keeping the place of its first occurrence, so calling it in a
  loop before writing a file out does not grow the file; `withEntry` appends
  and keeps the earlier entry, which is the format's own notion of a write.
- **`FlatIssue`, `FlatIssueKind` and `FlatParseOptions.onIssue`** — one channel
  for every problem the parser finds, carrying the kind, the 1-based line and
  column, and the raw line.
- **`FlatIncludeOptions.maxIncludes` and `maxIncludedEntries`** — budgets for a
  whole include traversal, raising `IncludeBudgetExceededException`. Depth
  bounds how far an include graph reaches, not how much it amounts to: a
  document whose includes each pull in the previous one twice doubles per
  level, and because a repeated unit is parsed once and then copied into every
  parent that names it, sixteen such levels stay at 32 directives while
  reaching 65,536 entries — from under a kilobyte of source, well inside the
  default depth. The entry budget is charged as entries are handed up, so the
  refusal happens before the allocation rather than after it.
- **`FlatIncludeOptions.mergePolicy`** — Ghostty precedence is a setting now
  rather than the only behaviour. `IncludeMergePolicy.lastWins` expands each
  include where it is written and lets a later entry win, which is what most
  formats do and what a line written below an include looks like it should do.
- **Key transformation in `FlatEnvOptions`** — `stripMatchedPrefix`,
  `keySplitOn`/`keyJoinWith` and `lowercaseKeys` turn `APP_WINDOW_WIDTH` into
  `window.width` without post-processing. They run after interpolation, so a
  `${VAR}` names an environment variable rather than a rewritten key, and they
  apply to `defaults` and `merge` too — otherwise a default could not override
  the variable it is a default for.
- **`MultilineValuePolicy`** — an environment variable whose value contains a
  line break can now be skipped instead of throwing, for a process whose
  environment carries something like a PEM key it never reads. The default
  stays `error`.
- **`package:flatconfig/flatconfig_accessors.dart`** — ready-made accessors for
  `DateTime`, `Duration`, `Uri`, JSON and enums, in the same three shapes as the
  core catalog. A program reading strings and numbers no longer carries a date
  parser it never calls.
- **`allAs`, `getListOr`, `requireList`, `getDateTimeOr`, `getUriOr`,
  `getJsonOr`, `getEnumOr`** — the shapes that were missing from types that
  already had two of the three.
- **`SPEC.md`** — the format is now specified rather than implied. Appendix A
  tracks where the implementation still deviates.
- **`InvalidKeyException`** — raised in strict mode for a key that breaks
  `SPEC.md` §3.
- **`FlatDocument.fromEnvironment()`** — build a document from environment
  variables.

Changed:

- **`SPEC.md` §8 is policy-aware.** It described in-place expansion with
  ordinary last-write-wins — which is `IncludeMergePolicy.lastWins`, not the
  `ghostty` default the API ships. The section now defines both, names
  `ghostty` as the default, and the conformance suite tests each policy
  against its own rule rather than leaving §8 untested.
- **`flatDocumentFromMapData` is no longer exported.** `FlatDocument.fromData`
  is the spelling, and shipping both in 1.0 would have made removing one a
  breaking change of its own.
- **A reset encodes as `key =`, without the trailing space.** The line used to
  end in one, which SPEC.md §7 prescribed and which nothing reading the file
  cares about — but `git diff --check` and the usual whitespace linters do, and
  a library that writes config files should not hand its users something they
  have to strip. Parsing is unaffected in both directions, so a file written by
  0.5.x still reads identically.
- **The package is four libraries instead of one.**
  `package:flatconfig/flatconfig.dart` is the web-safe core;
  `flatconfig_includes.dart` adds resolver-based includes,
  `flatconfig_accessors.dart` the `DateTime`/`Duration`/`Uri`/JSON/enum
  accessors, and `flatconfig_io.dart` everything that needs `dart:io`. Each of
  the three re-exports the core, so a program still writes one import. The
  conditional exports are gone with them: on the web you do not import
  `flatconfig_io.dart`, rather than importing a stub that compiles and then
  throws. That stub is what made `'text'.parseFlat()` — an extension on
  `Object` — look valid on every platform.
- **`File` is the only way to read or write a file.** `parseFlatFile`,
  `parseFlatFileSync`, `parseFileWithIncludes`, the top-level `writeFlat` and
  `writeFlatSync`, `FlatDocument.saveToFile` and `saveToFileSync` are gone;
  `File(path).parseFlat()`, `.parseFlatSync()`, `.parseWithIncludes()`,
  `.parseWithIncludesSync()`, `.writeFlat(doc)` and `.writeFlatSync(doc)` cover
  all of it. Three spellings of one workflow meant three places for a change to
  miss one: `parseFileWithIncludes` and `File.parseWithIncludes` both took a
  `cache:` argument, and `File.parseWithIncludesSync`, which lived in a
  different file, never grew one.
- **`FlatConfigResolverIncludes.parseStringWithIncludes` is now the top-level
  `parseWithIncludes`,** and `parseStringWithIncludesSync` is
  `parseWithIncludesSync`. They were static members on an extension, which is a
  way of spelling a top-level function that reads as if it were a method on
  `FlatDocument`.
- **`splitRespectingQuotes` and `indexOfUnquoted` are exported.** `SPEC.md` §5
  pins what they do, and they are what a custom `FlatConverter` needs to split
  an inline list the way the parser would.
- **`IncludeResolver.resolve` is now asynchronous and takes an
  `IncludeRequest`.** The sync-only interface excluded an HTTP endpoint, a
  database row and a Flutter asset behind `rootBundle.loadString()` by
  construction: a Flutter app could parse an asset config but never follow an
  include from one. A resolver that can answer without awaiting extends
  `SyncIncludeResolver`, which derives the async method, so one sync resolver
  works with both entry points without a wrapper.
- **`parseStringWithIncludes` is now the async entry point;**
  `parseStringWithIncludesSync` is the previous behaviour under its own name and
  takes a `SyncIncludeResolver`.
- **`CompositeIncludeResolver` is asynchronous**, since it cannot answer without
  awaiting when one of the sources it may consult does.
  `SyncCompositeIncludeResolver` composes synchronous ones.
- **`IncludeUnit` is immutable with value equality**, and can be `const`.
- **`FlatEnvOptions.interpolate` now defaults to `false`.** A variable's value
  is data the program did not write, and a `$` in it is more often a password
  than a reference. Turning it on is a decision, not the state you get by
  forgetting to make one.
- **A `${VAR}` naming nothing is preserved rather than emptied.**
  `{'URL': r'https://${NOPE}/api'}` used to yield `https:///api`, which looks
  like a URL and fails somewhere else entirely; the unresolved placeholder
  points at the typo instead. `MissingVariablePolicy.empty` restores the old
  behaviour and `.error` throws naming both the variable and the value that
  references it.
- **`includeKey` and `maxIncludeDepth` moved to `FlatIncludeOptions`.** They sat
  on `FlatParseOptions`, which made it look as though `FlatDocument.parse` might
  follow an include. It never did — only the entry points that take a path or a
  resolver do, and those now take `includeOptions:` alongside `options:`.
- **`FlatMapDataOptions` is now `FlatDataOptions`,** matching
  `FlatDocument.fromData`, which was renamed from `fromMapData` earlier in this
  cycle.

Fixed:

- **An unreadable include is no longer reported as a missing one.** The
  implementation asked whether a file existed and then read it, so a permission
  failure, a directory in the way or a symlink loop all came back as absence —
  which a required include reported as `MissingIncludeException` and an
  optional one skipped in silence. It reads first now, and only a genuine
  `PathNotFoundException` counts as missing. The gap between the two calls is
  gone with it.
- **Filesystem identity is asked for rather than inferred.** Deciding whether
  two spellings of a path were one file compared size and modification time,
  which two distinct files share as soon as they are the same length and were
  written in the same second. It uses `FileSystemEntity.identicalSync` now, and
  Windows is probed like everything else instead of being assumed
  case-insensitive.
- **`FileIncludeResolver` takes an encoding.** It always read UTF-8, so a
  Latin-1 include worked through the file API and failed through the resolver
  with the same read options. A resolver hands over text, so the decoding is
  its own business; `FlatStreamReadOptions.encoding` never reaches one, and the
  entry points say so now.
- **An empty include directive no longer duplicates the entries after it.**
  `config-file =` ended the head of the document without starting the tail, so
  everything below it was collected as both and appeared twice. Three separate
  answers to "is this line a directive?" had drifted apart; there is one now,
  and it covers all four spellings that name nothing.
- **A key beginning with a configured comment prefix is refused at encode
  time.** `;secret` is a valid key — validity is judged against the default `#`
  so that a document does not become invalid because of the options of whoever
  reads it — and it encoded to `;secret = value`, which re-parses as a comment
  with a non-default prefix. The entry disappeared without a trace, and
  `SPEC.md` §3 always required the encoder to catch this.
- **`collapse(ignoreResets: true)` now ignores resets.** An ignored reset still
  claimed a position, so a key written only as a reset survived as one, and a
  trailing reset moved the value it was supposed to leave alone.
- **`stripPrefix` refuses a key it cannot rename instead of dropping it.**
  `window.#secret` and `window. padded` are valid keys that strip to invalid
  ones, and the entry used to vanish silently.
- **Data that contains itself is refused.** `FlatDocument.fromData` recursed
  until the stack ran out; a cyclic map or list now raises an `ArgumentError`
  naming the key path. Sharing the same map twice is not a cycle and still
  works.
- **`FlatDocument.parseBytes` and `streamEntries` accept a
  `Stream<Uint8List>`.** Both transformed the stream with a decoder, which is a
  `StreamTransformer<List<int>, String>` and throws when bound to a stream of
  the subtype — the stream `utf8.encode`, a socket and an HTTP body all hand
  out. Every test passed its stream straight to the parameter, where inference
  made it a `Stream<List<int>>` and hid the crash from the suite; naming the
  stream in a variable first was enough to hit it.
- **The README no longer contradicts itself about resets.** It stated that a
  tail entry cannot override a key an include set, and then showed a
  non-blocking reset example doing exactly that. A reset is a value like any
  other: it loses to a later include and, under the default Ghostty policy,
  still owns the key against a line written below the includes.
  `doc/includes.md` now documents what the code does, verified against it.
- **The dartdoc examples compile again.** Twenty-one of them still called
  `FlatConfig`, deleted earlier in this cycle, so the documentation for the
  parser, the options and the document itself demonstrated an API that no
  longer exists.
- **`config-file = "` no longer crashes.** A lone quote satisfies both "starts
  with a quote" and "ends with a quote", so the unquoting asked for
  `substring(1, 0)` and a hand-edited file reached the caller as a
  `RangeError`. It is now treated as the unterminated quote it is.
- **An include directive that names nothing asks no resolver anything.**
  Emptiness was judged before the `?` marker and the quotes were stripped, so
  `config-file = ?` and `config-file = ""` were resolved as a unit named `""` —
  for a network resolver, a request for an empty URL. All four spellings now
  contribute nothing.
- **`FlatDataOptions` is a value type like the rest.** It was the one options
  class with no `==`, `hashCode`, `toString` or `copyWith`, missed because it
  lives in `from_map_data.dart` rather than `options.dart`. Two instances with
  identical fields compared unequal unless both were `const`, where
  canonicalization hid it.
- **The include cache no longer serves a document built from other inputs.**
  The `cache:` parameter on every include entry point is gone; each call now
  keeps its own cache for the length of the traversal. The key was a canonical
  path or unit id, but the result behind it also depended on the parse options,
  the encoding, the include key, the merge policy and what the resolver
  answered. Handing the same map to a second call with any of those changed
  returned the earlier document: parsing with `decodeEscapesInQuoted: false`
  after a default parse gave back the decoded value, and reusing an `originId`
  for different text gave back the earlier text. A file reached twice within one
  call is still read once, and an include edited between two calls is now seen
  by the second one.
- **The options classes behave like values.** All five now implement `==`,
  `hashCode` and `toString`, so two option sets built the same way compare equal
  and a failing test prints what it was configured with. `copyWith` can clear a
  nullable field rather than only set one: passing `prefix: null` to
  `FlatEnvOptions.copyWith` now removes the prefix instead of being
  indistinguishable from omitting the argument.
- **`FlatEnvOptions` copies the maps it is given.** `defaults` and `merge` were
  stored by reference, so mutating the caller's map changed the behaviour of
  options that had already been constructed and used. The constructor is no
  longer `const` as a result.
- **Invalid options are rejected where they are written.** An empty
  `lineTerminator`, a `commentPrefix` containing a line break, a negative
  `maxIncludeDepth` and a `varPattern` that is not a valid regex with a capture
  group all used to be accepted and then misbehave somewhere later. An empty
  `FlatEnvOptions.prefix` now means the same as none, which is what it already
  did in practice.
- **Lenient parsing no longer drops lines in silence.** `onMissingEquals` and
  `onEmptyKey` covered two of the five things that can go wrong; an invalid key,
  an unterminated quote and trailing characters after a quote were skipped with
  no way to find out. One `onIssue` handler now reports all five, and a sixth
  kind becomes additive rather than a third callback on `FlatParseOptions`.
  Strict mode throws the matching `FlatParseException` for exactly the same
  inputs, so `onIssue` in development and `strict: true` in production cannot
  disagree. Throwing from the handler aborts the parse, which gives you the
  policies between the two.
  `OnErrorHandler` is replaced by `OnIssue`; `FlatParseException` is now
  exported, having been the hidden base class of five exported subclasses.

- **The accessors and document helpers are members of `FlatDocument`, not
  extensions.** An extension cannot be overridden, does not appear under the
  class in dartdoc, and silently vanishes when the wrong barrel is imported —
  none of which is worth it for members that are always available anyway.
  `FlatDocumentAccessors` and `FlatDocumentExtensions` are gone as names; their
  members are unchanged and reachable exactly as before. `CollapseOrder` and
  `FlatConverter` moved to `document.dart` with them. Extensions remain only
  where they earn it: on foreign types such as `File`, and for the optional
  entry points.

- **The accessor catalog collapses from 66 methods to 19 in core.** It had grown
  by crossing {type} × {lenient, default, strict, trimmed, ranged, clamped,
  empty}, so finding the right method meant reading a 1,460-line file. There is
  now one rule with no exceptions: for every type `X`, exactly `getX` (nullable),
  `getXOr(key, fallback)` and `requireX` (throws).

  Core keeps `String`, `int`, `double`, `bool`, `List<String>` and the `getAs`
  family. `DateTime`, `Duration`, `Uri`, JSON and enums move to
  `flatconfig_accessors.dart`. Everything else is deleted, because each encoded
  an application's notation decision that the package should not own, and each
  is a few lines behind `getAs`:

  | removed | replacement |
  |---|---|
  | `getHexColor`, `getColor`, `getColorTuple` (+ `require*`) | `doc.getAs('bg', parseMyColor)` |
  | `getPercent`, `getRatio`, `getBytes`, `getHostPort` (+ `require*`) | `getAs` with your converter |
  | `getNum`, `requireNum` | `getInt` ?? `getDouble` |
  | `getIntInRange`, `getDoubleInRange`, `getClampedInt` (+ `require*`) | a validating converter, or `clamp()` on the result |
  | `getMap`, `getMapOrEmpty`, `getDocument`, `getListOfDocuments`, `getKeyValue` | a second, undocumented grammar — out of core |
  | `getSet`, `getSetOrEmpty` | `getList(k)?.toSet()` |
  | `getTrimmed`, `getTrimmedOrEmpty` | unquoted values arrive trimmed; quoted whitespace was deliberate |
  | `getListOrEmpty` | `getListOr(k, const [])` |
  | `isEnabled`, `isDisabled` | `getBoolOr` — and `isDisabled(k, defaultValue: true)` returned `false`, because the default was negated along with the value |
  | `isOneOf` | `values.contains(doc[k])` |
  | `hasAllKeys`, `requireKeys` | `keys.every(doc.containsKey)` |
  | `getAsWith`, `requireAsWith` | the document is already in scope at the call site |
  | `getAllAs`, `requireAllAs` | `allAs` |

- **`allAs` gives repeated keys defined semantics.** `requireAllAs` returned `[]`
  for a key that was never mentioned, which is also what a key present only as a
  reset yields; `allAs` returns `null` for the first and `[]` for the second. It
  also throws on the first unconvertible value instead of dropping it, so a typo
  can no longer turn into a silently shorter list.
- **A converter's `Error` is no longer reported as malformed config.** `getAs`
  caught everything, so an `ArgumentError` or `TypeError` from a buggy converter
  came back as "this value could not be parsed". Only `Exception` is caught now.
- **`preNormalizedLowerMapping` is gone from `getEnum`.** An internal performance
  knob had leaked into a public signature.

- **`FlatConfig` is deleted; the entry points are statics on `FlatDocument`.**
  It was an instantiable `const` class holding no state, used only as a static
  namespace — and it was not even a complete one, since include parsing hung off
  separate static-extension namespaces. Dart's convention is a static factory on
  the type being produced (`Uri.parse`, `int.parse`), so there is now one type
  name to learn instead of three:

  | was | is |
  |---|---|
  | `FlatConfig.parse` | `FlatDocument.parse` |
  | `FlatConfig.parseLines` | `FlatDocument.parseLines` |
  | `FlatConfig.parseFromByteStream` | `FlatDocument.parseBytes` |
  | `FlatConfig.parseFromStringStream` | `FlatDocument.parseLineStream` |
  | `FlatConfig.parseEntries` | `FlatDocument.streamEntries` |
  | `FlatConfig.fromMap` | `FlatDocument.fromMap` (the two are now one) |
  | `FlatConfig.fromMapData` | `FlatDocument.fromData` |
  | `FlatConfig.fromEnvironment` | `FlatDocument.fromEnvironment` |

  `parseEntriesFromStringStream`, `parseLine` and `preprocessLine` were public
  only for tests and now live behind a `src/` import.
  `fromDynamicMap` is deleted. It guessed at `toString()` for arbitrary objects,
  which is a formatting decision the caller should be making; map to `String?`
  first and pass the result to `fromMap`.

- **Quoted values close at the first unescaped quote**, not the last.
  `a = "one" junk "two"` was accepted even in strict mode and yielded
  `one" junk "two`.
- **The empty string survives a round trip.** It was encoded as a bare
  `key = ` and read back as `null`.
- **Keys are validated wherever a document is built.** `FlatEntry('#x', 'v')`
  encoded to `#x = v` and read back as *zero* entries; `FlatEntry(' a ', 'v')`
  lost its padding. Both were silent.
- **Backslashes survive the inline grammar.** `getDocument` turned
  `win=C:\temp\x` into `win → C:tempx`.
- **`stripPrefix` no longer produces an unreadable line** when a key equals the
  prefix; the entry is dropped instead.
- **`toMap()` and `valuesOf()` are unmodifiable after `cache()`.** Pre-caching
  handed out a writable view of a document documented as immutable, so
  `doc.cache(); doc.toMap()['a'] = 'x';` changed the document.
- **`FlatDocument` is no longer an `Iterable<FlatEntry>`.** The inheritance put
  roughly forty members on the type that silently meant "entries", including a
  `doc.contains(x)` that tested for an entry while sitting next to a key lookup.
  `entries`, `length`, `isEmpty` and `isNotEmpty` remain; everything else is
  `doc.entries.…`, which says which view is meant.
- **`FlatEntry` is valid by construction, and `strict` is gone everywhere.** The
  constructor now rejects what the format cannot write out, so the flag had
  nothing left to switch: `fromMap`, `fromEntries`, `FlatDataOptions` and the
  deleted `single` no longer take it, `FlatEntry.validated` is the ordinary
  constructor, and `FlatDocument.validateEntries` is deleted as unreachable.
  These inputs now raise `ArgumentError` at the point they are written, rather
  than `FormatException` one layer later. `FlatEntry.reset(key)` names the
  explicit reset.
  `FlatEntry` is no longer `const`: a `const` constructor can only check through
  `assert`, which release builds drop. A `const` document was never
  constructible anyway, so the only loss is `const` lists of entries.
  Leniency stays where files actually arrive, in `FlatParseOptions.strict`.
- **The three merge APIs collapse into `concat`.** In a last-write-wins model
  appending already is the merge: `a.concat(b).toMap()` equals
  `{...a.toMap(), ...b.toMap()}`, and `merge(b, override: false)` is `b.concat(a)`
  read from the other end. Static `FlatDocument.merge`, instance `merge` and the
  `override:` flag are gone; `operator +` is an alias for `concat`.
- **`FlatDocument.lookup(key)` tells the three states apart.** `doc['k'] == null`
  cannot distinguish a key that was never mentioned from one explicitly cleared
  with `k =`, and the difference decides whether a default still applies. The
  sealed `FlatLookup` (`FlatAbsent`, `FlatReset`, `FlatPresent`) is exhaustively
  switchable; `operator []` stays as the nullable convenience.
- **Lookup renames.** `has` is now `containsKey`, matching `Map`. `valuesOf` is
  now `allValues`. `hasNonNull`, `firstValueOf` and `lastValueOf` are gone:
  they are `doc[k] != null`, `allValues(k).first` and `doc[k]`.
- **Path identity no longer assumes macOS is case-insensitive.** Every macOS
  path was lowercased, so on a case-sensitive APFS volume `Foo.conf` and
  `foo.conf` collapsed into one canonical id, inventing include cycles and
  serving cached content from the wrong file. The filesystem is now asked, once
  per directory, and case is folded only where it answers yes.
- **Guards on public input throw instead of asserting.** A `commentPrefix`
  containing a line break, a multi-character separator, and an empty line
  terminator now raise `ArgumentError` in release builds, where `assert` does
  nothing. CI runs the suite with assertions disabled to keep it that way.
- **The minimum SDK is 3.8.0**, raised from a declared 3.0.0 that could never
  resolve: `path` needs 3.4, `meta` needs 3.5, `lints` needs 3.8. CI now builds
  on the floor as well as on stable.
- **Values containing a line break are rejected.** `FlatEntry('a', 'x\ny')`
  was accepted, encoded to two physical lines, and read back as `a` → `"x`.
  Quoting cannot rescue it, because the format is line-based.
- **Non-finite numbers are rejected.** `NaN` passed every range guard, because
  all comparisons with it are false: `getDoubleInRange('p', min: 0, max: 1)`
  returned `NaN`. `NaN`, `Infinity` and `-Infinity` are now treated as invalid
  by every numeric accessor.

Changed (breaking):

- `escapeQuoted` and `decodeEscapesInQuoted` both default to `true`. Reading
  0.5.x output that contains quotes and was written with the old default needs
  `FlatParseOptions(decodeEscapesInQuoted: false)`.
- `FlatEntry.validated` rejects a padded key instead of trimming it.
- `strict: false` on the document factories drops invalid entries instead of
  keeping them — which is what its documentation always claimed.
- Building a `FlatDocument` with an invalid key throws a `FormatException`.
- `splitRespectingQuotes` returns raw tokens; `parseValue` owns escape decoding.
- `getDocument`'s `trimKey: false` is now inert, since every key whose padding
  it would preserve is invalid. It goes with those accessors in Phase 2.6.
- `FlatStreamWriteOptions.ensureTrailingNewline` is removed. It was a no-op:
  `encode()` already terminates the last line.
- `rfc4180CsvItemEncoder` is only safe for newline-free items. RFC-4180 permits
  a newline inside a quoted field; this format cannot store one.
- `FlatDocument.fromEnvironment` throws on a variable whose value contains a
  newline, rather than storing something unreadable.

## 0.5.0

Added:

- **`FlatDocument.hasAllKeys()`**  
  Checks whether all specified keys exist in the document.  
  - `ignoreNulls` (default: `true`) skips null-valued keys.  
  - `caseSensitive` (default: `true`) controls case matching.  

- **`FlatDocument.slice(prefix)`**  
  Extracts a subdocument containing only keys that start with the given prefix.  
  Operates on the resolved/latest view (unique keys; last value wins) and preserves key order.  

- **`FlatDocument.stripPrefix(prefix)`**  
  Returns a new document with all keys that start with the given prefix —  
  but removes the prefix from each key.  
  Ideal for working with grouped or sectioned configurations.  

## 0.4.0

Added:

- **In-memory include support** via the new resolver system:
  - `MemoryIncludeResolver` – define virtual configuration sources in memory (maps, generated strings, or tests).
  - `CompositeIncludeResolver` – combine multiple resolvers (e.g., files + memory) with *first-hit-wins* lookup order.
  - `FlatConfigResolverIncludes.parseStringWithIncludes()` – parse configuration text using any custom resolver.
- **Web/WASM compatibility:**
  - `FileIncludeResolver` is now an I/O-only implementation.
  - A lightweight `FileIncludeResolver` stub is automatically used on Web/WASM (always returns `null`).

Behavior:

- Matches the **Ghostty include semantics**:
  - Includes are processed at the end of the current unit (depth-first).
  - Later includes override earlier includes.
  - Entries after the first include cannot override keys defined in includes.
  - Optional includes prefixed with `?` are silently ignored if missing.
  - Cycle detection is performed via canonical `IncludeUnit.id`.

Improved:

- Expanded README:
  - Detailed “Include Semantics” and new “In-Memory and Hybrid Includes” sections.
  - Clarified **non-blocking reset** behavior (`key =` clears but doesn’t block later assignments).
  - Added examples for resolver composition and hybrid (file + memory) setups.

Notes:

- The resolver system shares the same merge, caching, and validation rules as file-based includes.
- Fully compatible with `FlatDocument`, `FlatEntry`, and all accessors.
- Backwards-compatible with existing file-based parsing APIs.

## 0.3.1

Improved:

- Polished README section for accessors (`get*`, `require*`, ranges, and quote awareness)
- Added concise "Accessors – At a Glance" overview
- Unified comment style and clarified boolean handling and range validation
- Minor formatting and consistency improvements across examples

Fixed:

- Corrected README description of include semantics:
  - Includes are merged **depth-first at the insertion point**; **later entries override earlier ones** (“later wins”).
  - An **unquoted empty value** (`key =`) is an **explicit reset** and **does not block** later assignments (**non-blocking by default**).
  - Optional includes via `config-file = ?file.conf` now explicitly documented as “missing files are ignored”.
- Added an example to demonstrate non-blocking resets and later overrides.

## 0.3.0

Added:

- Deep flattening via `FlatConfig.fromMapData()`.
- `FlatMapDataOptions` for list mode, CSV encoding, null handling, key escaping.
- RFC-4180 CSV utilities (`rfc4180Quote`, `rfc4180CsvItemEncoder`).
- `keyEscaper` for safe nested key handling.
- New tests: full coverage for map flattening, list modes, and CSV quoting.

Improved:

- Documentation and README examples for `fromMapData` and document factories.
- Barrel exports (`flatconfig.dart`) now include all public constructors.
- Internal structure cleanup and error context clarity.

Fixed:

- Proper key escaping on root keys in `fromMapData`.
- Accurate multi-value list flattening order.

## 0.2.0

Added:

- Generic & context-aware accessors:
  - `getAs<T>(key, converter)` – lenient “try” variant; returns `null` on missing/empty/invalid.
  - `getAsOr<T>(key, converter, default)` – lenient with fallback.
  - `requireAs<T>(key, converter)` – strict; throws `FormatException` with context.
  - `getAsWith<T>(key, (raw, key, doc) => T?)` – advanced, document-aware converter.
  - `requireAsWith<T>(...)` – strict variant for advanced converters.
  - `getAllAs<T>(key, converter)` – lazy, lenient conversion for duplicate keys.
  - `requireAllAs<T>(key, converter)` – strict conversion for all values.
- README: New **Custom Converters** section with examples.
- README: **Comparison to INI/TOML** and **Design Philosophy** sections.

Improved:

- Consistent, idiomatic error semantics:
  - Lenient `get*` accessors never throw; strict `require*` accessors throw with `.explain(key, got, cause)` context.

Notes:

- No breaking changes. Web/WASM-safe core remains unchanged; I/O helpers are still VM-only.

## 0.1.4

Added:

- **Web/WASM Stubs:** Added `includes_stub.dart` and `io_stub.dart` to safely
  throw `UnsupportedError` on non-IO platforms. The package now loads cleanly
  in Flutter Web / WASM projects (core parsing remains available).

Changed:

- **Barrel Exports:** Simplified conditional exports — the full units for
  `io.dart` and `includes.dart` are exported so that all extensions are
  visible on IO platforms.
- **README & Example:** Updated to use the recommended path-based helpers:
  `parseFlatFile`, `parseFlatFileSync`, `parseFileWithIncludes`,
  `writeFlat`, `writeFlatSync` (no more `src/` imports).
  File-based extensions remain available as ergonomic sugar.

Fixed:

- Pub.dev analysis warning: Missing `lints` dependency in `example/` package.
- Web/WASM analysis: no longer fails due to missing `dart:io` references.

Notes:

- This release is **non-breaking** (`0.1.x` → `0.1.4`).

## 0.1.3

Added:

- Added full support for *recursive* `config-file` *includes* (Ghostty-compatible).
  - Supports optional includes (`?path`), nested includes, relative paths, and cycle detection.
  - Defensive maximum include depth (`maxIncludeDepth`, default 64).
  - Async/sync I/O via `File.parseWithIncludes()` and `parseFileWithIncludes()`.
- Introduced example and documentation for *null-reset semantics* (`key = → null`, blocks later assignments).
- Clarified behavior for *one include per line* — comma-separated paths are treated as a single literal.
- Improved README with clear *include semantics*, usage examples, and quote-awareness notes (`getMap()` vs `getDocument()`).

Improved:

- Internal include handling now normalizes paths and detects circular dependencies more robustly.
- Minor parser cleanups and docstring refinements for consistency.

## 0.1.2

Documentation & metadata improvements:

- Updated dependency constraints and topics for pub.dev
- Updated README with slightly clearer description

## 0.1.1

Added:

- `FlatEntry.validated` factory for safe key creation
- Strict factories (`fromMap`, `fromEntries`, `merge`, `single`) with `strict` toggle
- Updated README with validation and factory examples

Improved:

- Internal key validation logic
- Documentation clarity and formatting

## 0.1.0

🎉 Initial public release.
