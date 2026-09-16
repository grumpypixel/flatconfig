# Changelog

## Unreleased — towards 1.0.0

On the `v1` bookmark, not on `main`. These are breaking and are meant to land
together as `1.0.0`. See `SPEC.md` for the rules and `ROADMAP_1.0.md` for what
is still outstanding.

Added:

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

Fixed:

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
  | `FlatConfig.parseEntries` | `FlatDocument.streamEntries` |
  | `FlatConfig.fromMap` | `FlatDocument.fromMap` (the two are now one) |
  | `FlatConfig.fromMapData` | `FlatDocument.fromData` |
  | `FlatConfig.fromEnvironment` | `FlatDocument.fromEnvironment` |

  `parseFromStringStream` and `parseEntriesFromStringStream` are internal: the
  byte-stream entry points cover the public need, and a caller holding lines
  already has `parseLines`. `parseLine` and `preprocessLine` were public only for
  tests and now live behind a `src/` import.
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
  nothing left to switch: `fromMap`, `fromEntries`, `FlatMapDataOptions` and the
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
