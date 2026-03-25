# flatconfig — Road to 1.0.0

Single execution plan. Supersedes the earlier `PACKAGE_REVIEW.md` and
`improvements.md` notes, which were removed from the repo — their findings are
folded in below, with reproductions.

**Baseline:** 0.5.0 published, plus unreleased `fromEnvironment` on `main`.
**Target:** one deliberate breaking release, `1.0.0`.
**Estimate:** 12–16 focused days.

## Decisions (locked)

| # | Decision | Consequence |
|---|----------|-------------|
| 1 | Direct to 1.0.0 | No deprecation cycle, no forwarding aliases, no legacy presets. Migration is a written guide only. |
| 2 | Newlines in values are forbidden | Rejected at construction *and* encode time. No multiline syntax in the grammar. |
| 3 | Full entry-point split | `flatconfig.dart` / `_io` / `_includes` / `_accessors`. |
| 4 | Async-first include resolvers | `Future<IncludeUnit?> resolve(...)`, separate sync interface for the file case. |
| 5 | Breaking the API freely is acceptable | Optimize for the best possible final surface, not for the smallest diff. |

## Guiding principles

1. **Correctness before shape.** Nothing new is built until the round-trip and
   immutability guarantees hold. Every feature layered on a lossy encoder
   inherits the loss.
2. **One way to do each thing.** Where two APIs overlap, one is deleted.
3. **Mechanical naming.** If a rule has exceptions, the rule is wrong.
4. **Delete before adding.** The current surface is roughly 140 members
   reachable on a `FlatDocument`. Target is ~45.

---

## Phase 0 — Freeze the format spec

**Output:** `SPEC.md`, versioned as *flatconfig format v1*.
**Effort:** ~½ day. **Blocks everything else.**

Without this, "correct" is undefined and the current ambiguities reappear in new
code. Each item needs exactly one stated answer:

- [ ] Valid key charset. May a key contain `=`, whitespace, quotes, newlines, or
      be empty? (Proposed: no to all.)
- [ ] Quoted-value grammar. Where does a quoted value legally end — first valid
      closer or last? What may follow it? (Proposed: first closer; only
      whitespace may follow; anything else errors in strict mode.)
- [ ] Escape rules inside quoted values, and whether decoding is on by default.
- [ ] The three states: missing key, explicit reset (`key =`), empty string
      (`key = ""`). Exact encode and parse behavior for each.
- [ ] Duplicate keys: preserved in order; resolved view is last-write-wins.
- [ ] Newlines in values: forbidden. Which error type, thrown where.
- [ ] Comment rules. The prefix is configurable; the `=` separator is **not**
      (README currently claims otherwise).
- [ ] Trailing-newline behavior of `encode()`.

---

## Phase 1 — Correctness and data integrity

**Effort:** 2–3 days. Each item needs a regression test.

### 1.1 Restore immutability

- [ ] `cache()` must store `Map.unmodifiable(_buildLatest())`
      (`lib/src/document.dart:256`). Same for the `valuesOf` cache.
- [ ] Test: `toMap()` is unwritable both with and without explicit pre-caching.

**Reproduction:** `doc.cache(); doc.toMap()['a'] = 'HACKED';` succeeds and
changes `doc['a']`. Without `cache()` it correctly throws `UnsupportedError`.

### 1.2 Make encoding lossless

| Value | Encoded | Parsed back |
|---|---|---|
| `""` | `a = ` | `null` — type silently changes |
| `"line1\nline2"` | `a = "line1⏎line2"` | `FlatEntry(a, "line1)` — truncated |
| key `a=b` | `a=b = v` | `FlatEntry(a, b = v)` — key corrupted |

- [ ] Encode an empty string as `""`, never as a bare `key =`.
- [ ] Validate keys at construction so `=`, newlines, and empty keys can never
      reach the encoder.
- [ ] Reject newline-containing values (decision 2) at construction and encode.
- [ ] Make safe escaping the default; unescaped output becomes opt-in.
- [ ] `encode()` always writes a trailing newline, so
      `ensureTrailingNewline: false` cannot remove one. Make the flag honest.

### 1.3 Stop eating backslashes

`splitRespectingQuotes()` (`lib/src/parser_utils.dart:251`) consumes every
backslash as an escape marker without copying it, regardless of
`decodeEscapesInQuoted`.

**Reproduction:** `paths = win=C:\temp\x,unix=/tmp` → `{win: C:tempx, unix: /tmp}`.

- [ ] Use backslashes only to decide whether a quote is escaped; preserve them.
- [ ] Let `parseValue()` own all optional escape decoding.
- [ ] Tests: Windows paths, regexes, trailing backslashes, escaped quotes, both
      values of `decodeEscapesInQuoted`.

> Note: the affected callers (`getDocument`, `getListOfDocuments`) are removed
> from core in Phase 2. Fix the utility anyway — it is shared with `parseValue`.

### 1.4 Guard prefix operations against empty keys

**Reproduction:** `'app = x\napp.host = y'.stripPrefix('app')` yields
`[FlatEntry(, x), FlatEntry(.host, y)]`, which encodes to `" = x"` — a line the
parser can never read back.

### 1.5 Define and enforce the quoted grammar

**Reproduction:** `parse('a = "one" junk "two"', strict: true)` is accepted,
yielding `one" junk "two`, because `parseValue` searches for the *last*
unescaped quote.

- [ ] Implement the Phase 0 grammar (first valid closer).
- [ ] Reject trailing non-whitespace in strict mode.

### 1.6 Reject non-finite numbers

**Reproduction:** `getDoubleInRange('p', min: 0, max: 1)` returns `NaN`. All
comparisons with NaN are false, so every range guard is bypassed.

### 1.7 Correct path canonicalization

`lib/src/path_utils.dart:12` lowercases every macOS path. APFS can be
case-sensitive, collapsing `Foo.conf` and `foo.conf` into one canonical ID —
producing false include cycles and wrong cache hits.

- [ ] Lowercase on Windows only, or detect filesystem case sensitivity.
- [ ] Put the strategy behind an injectable interface so it is testable off
      Windows.

### 1.8 Replace assertions on public input

`assert` vanishes in release builds. Currently unguarded in production:
`commentPrefix` containing newlines (`parser.dart:66,98,151,210`),
`sep.length == 1` (`parser_utils.dart:253`), `ch.length == 1`
(`parser_utils.dart:306`), `lineTerminator.isNotEmpty` (`parser_utils.dart:215`).

- [ ] Validate in public constructors, throw `ArgumentError`.
- [ ] CI job that runs the suite with assertions disabled.

### 1.9 Fix the SDK floor

`pubspec.yaml` declares `>=3.0.0`, but `path ^1.9.1` needs `^3.4.0`,
`meta 1.17.0` needs `^3.5.0`, `lints 6.0.0` needs `^3.8.0`. The floor cannot
resolve.

- [ ] Raise to 3.8. Add a minimum-SDK CI job so the number stays honest.

---

## Phase 2 — The 1.0 API

**Effort:** 6–8 days. This is the substance of the release.

### 2.0 Proposed final surface

```dart
// ═══ package:flatconfig/flatconfig.dart ═══════════════════════════════

/// A single `key = value` pair. Always valid: key is non-empty, contains no
/// `=`, quote, or newline. A null value is an explicit reset (`key =`).
final class FlatEntry {
  factory FlatEntry(String key, String? value);
  factory FlatEntry.reset(String key);
  String  get key;
  String? get value;
}

/// The three states a key can be in. Exhaustively switchable.
sealed class FlatLookup {
  const factory FlatLookup.absent()            = FlatAbsent;
  const factory FlatLookup.reset()             = FlatReset;
  const factory FlatLookup.present(String v)   = FlatPresent;
}

typedef FlatParse<T> = T Function(String value);

/// Ordered, duplicate-preserving, deeply immutable.
final class FlatDocument {
  // ── from text ───────────────────────────────────────────────────────
  static FlatDocument parse(String source, {FlatParseOptions options});
  static FlatDocument parseLines(Iterable<String> lines, {FlatParseOptions options});
  static Future<FlatDocument> parseBytes(
      Stream<List<int>> bytes, {FlatParseOptions options, FlatDecodeOptions decode});
  static Stream<FlatEntry> streamEntries(
      Stream<List<int>> bytes, {FlatParseOptions options, FlatDecodeOptions decode});

  // ── from data ───────────────────────────────────────────────────────
  static const FlatDocument empty;
  factory FlatDocument.of(Iterable<FlatEntry> entries);
  factory FlatDocument.fromMap(Map<String, String?> values);
  factory FlatDocument.fromEnvironment(Map<String, String> env, {FlatEnvOptions options});
  factory FlatDocument.fromData(Map<String, Object?> data, {FlatDataOptions options});

  // ── raw view ────────────────────────────────────────────────────────
  List<FlatEntry> get entries;     // unmodifiable
  int  get length;
  bool get isEmpty;
  bool get isNotEmpty;

  // ── resolved view (last write wins) ─────────────────────────────────
  Map<String, String?> toMap();    // unmodifiable
  Iterable<String> get keys;

  // ── lookup ──────────────────────────────────────────────────────────
  String?      operator [](String key);   // convenience; null = absent OR reset
  FlatLookup   lookup(String key);        // use when the distinction matters
  bool         containsKey(String key);
  List<String?> allValues(String key);

  // ── typed reads: exactly three shapes per type, no exceptions ───────
  String? getString(String k);  String getStringOr(String k, String d);  String requireString(String k);
  int?    getInt(String k);     int    getIntOr(String k, int d);        int    requireInt(String k);
  double? getDouble(String k);  double getDoubleOr(String k, double d);  double requireDouble(String k);
  bool?   getBool(String k);    bool   getBoolOr(String k, bool d);      bool   requireBool(String k);

  List<String>? getList(String k, {String separator = ','});
  List<String>  getListOr(String k, List<String> d, {String separator = ','});
  List<String>  requireList(String k, {String separator = ','});

  // ── generic escape hatch ────────────────────────────────────────────
  T?      getAs<T>(String k, FlatParse<T> parse);
  T       getAsOr<T>(String k, FlatParse<T> parse, T d);
  T       requireAs<T>(String k, FlatParse<T> parse);
  List<T> allAs<T>(String k, FlatParse<T> parse);

  // ── immutable editing ───────────────────────────────────────────────
  FlatDocument add(String key, String? value);        // append one entry
  FlatDocument set(String key, String? value);        // remove all, append one
  FlatDocument remove(String key);                    // remove all occurrences
  FlatDocument rename(String from, String to);
  FlatDocument concat(FlatDocument other);            // append raw entries
  FlatDocument operator +(FlatDocument other);        // alias for concat
  FlatDocument collapse({CollapseOrder order, bool dropResets});
  FlatDocument whereKey(bool Function(String key) test);
  FlatDocument slice(String prefix);                  // resolved view
  FlatDocument stripPrefix(String prefix);            // resolved view

  // ── output ──────────────────────────────────────────────────────────
  String    encode({FlatEncodeOptions options});
  List<int> encodeBytes({FlatEncodeOptions options, FlatEncodeStreamOptions stream});
  String    toDebugString({bool indexes, bool sortByKey, bool align});
}
```

### 2.1 Delete `FlatConfig` entirely

`FlatConfig` is an instantiable `const` class with no state, used purely as a
static namespace — and include parsing doesn't even live there, it hangs off
static extension namespaces like `FlatConfigResolverIncludes.parseStringWithIncludes()`.

Dart's convention is a static factory on the type being produced: `Uri.parse`,
`DateTime.parse`, `int.parse`. Moving everything to `FlatDocument` means users
learn **one type name** instead of three, and the static-extension-namespace
pattern disappears.

- [ ] `FlatConfig.parse` → `FlatDocument.parse`
- [ ] `FlatConfig.parseLines` → `FlatDocument.parseLines`
- [ ] `FlatConfig.parseFromByteStream` → `FlatDocument.parseBytes`
- [ ] `FlatConfig.parseEntries` → `FlatDocument.streamEntries`
- [ ] `FlatConfig.fromMap` and `FlatDocument.fromMap` → one `FlatDocument.fromMap`
- [ ] `FlatConfig.fromDynamicMap` → deleted (callers map to `String?` themselves)
- [ ] `FlatConfig.fromMapData` / `flatDocumentFromMapData` → `FlatDocument.fromData`
- [ ] `FlatConfig.fromEnvironment` → `FlatDocument.fromEnvironment`
- [ ] `FlatConfig.parseFromStringStream`, `parseEntriesFromStringStream` →
      internal; the byte-stream entry points cover the public need
- [ ] `parseLine` / `preprocessLine` are `@visibleForTesting` but public —
      move to a `src/` test import

### 2.2 Stop extending `Iterable<FlatEntry>`

`FlatDocument extends Iterable<FlatEntry>` adds ~45 inherited members to
autocomplete and creates a genuine trap: `doc.contains(x)` tests whether an
**entry** is present, sitting right next to `doc.has(key)` which tests a **key**.
`doc.map`, `doc.where`, `doc.first`, `doc.length` all silently mean "entries".

- [ ] Drop the `extends`. Expose `entries`, `length`, `isEmpty`, `isNotEmpty`.
- [ ] Users write `doc.entries.where(...)` — explicit about which view they mean.

### 2.3 Delete `strict` from every factory

Today `strict: false` means "drop invalid keys" in `fromMap` but "keep invalid
keys" in `fromEntries`, `merge`, and `single` — contradicting their own dartdoc:

```dart
FlatDocument.fromEntries([FlatEntry('  ', 'x')], strict: false)
  →  [FlatEntry(  , x)]     // docs say such entries are "ignored"
```

The cleanest resolution is not to make the flag consistent, but to **remove it**.
A `FlatDocument` always holds valid entries; `FlatEntry` validates in its
constructor. Leniency belongs exclusively to the parser, where hand-edited files
actually arrive — and `FlatParseOptions` already covers it.

- [ ] Remove `strict` from `fromMap`, `fromEntries`, `merge`, `single`, and
      `FlatMapDataOptions`.
- [ ] Remove the public `FlatDocument.validateEntries` static.
- [ ] Remove `FlatEntry.validated` — the default constructor validates.
- [ ] `FlatDocument.single(key, value:)` → deleted; use
      `FlatDocument.of([FlatEntry(key, value)])`.

### 2.4 Delete `merge`

There are three merge-ish APIs: static `FlatDocument.merge(docs)`, instance
`doc.merge(other, override: true)`, and `doc.merge(other, override: false)`
which does something else entirely.

But in a last-write-wins model, **concatenation already is the resolved merge**:
`a.concat(b).toMap() == {...a.toMap(), ...b.toMap()}`. And `override: false` is
just `b.concat(a)` read from the other end. So the whole family collapses into
two orthogonal operations that were already there:

- `concat(other)` — append raw entries
- `collapse()` — one entry per key

- [ ] Delete both `merge` methods and the `override:` boolean.
- [ ] Document the `concat` + `collapse` idiom in the migration guide.

### 2.5 Model lookup explicitly

`doc['x']` returning `null` currently means "absent", "explicitly reset", or —
via typed getters — "present but unparseable". This is the root of several
downstream inconsistencies.

- [ ] Add sealed `FlatLookup` and `doc.lookup(key)`.
- [ ] Keep `operator []` as the nullable convenience, documented as unsuitable
      for presence detection.
- [ ] Rename `has` → `containsKey` (matches `Map`), delete `hasNonNull`.
- [ ] `firstValueOf` / `lastValueOf` → deleted. `lastValueOf` is an exact alias
      for `[]`; `firstValueOf` becomes `allValues(key).first`.
- [ ] `valuesOf` → `allValues` (pairs with `allAs`).

### 2.6 Collapse the accessor catalog

`document_accessors.dart` is 1,460 lines and 66 methods. The blowup comes from
crossing {type} × {lenient, default, strict, trimmed, ranged, clamped, empty}.
Fixing this is the single biggest usability win available.

**The rule, with no exceptions:** for every supported type `X`, exactly three
methods — `getX` (nullable), `getXOr(key, fallback)`, `requireX` (throws).

**Keep in core** (4 types × 3 + list × 3 + generic × 4 = 19 methods):
`String`, `int`, `double`, `bool`, `List<String>`, and the `getAs` family.

**Move to `flatconfig_accessors.dart`**, same three-shape rule:
`DateTime`, `Duration`, `Uri`, JSON, enum mapping.

**Delete outright** — each is an app-level semantic decision the package should
not own, and all are trivially expressible via `getAs`:

| Removed | Replacement |
|---|---|
| `getHexColor`, `getColor`, `getColorTuple` (+3 `require*`) | `doc.getAs('bg', parseMyColor)` |
| `getPercent`, `requirePercent` | `getAs` |
| `getRatio`, `requireRatio` | `getAs` |
| `getHostPort` | `getAs` |
| `getBytes`, `requireBytes` | `getAs` |
| `getNum`, `requireNum` | `getInt` ?? `getDouble` |
| `getMap`, `getMapOrEmpty`, `getDocument`, `getListOfDocuments`, `getKeyValue` | second undocumented grammar — out of core |
| `getSet`, `getSetOrEmpty` | `getList(k)?.toSet()` |
| `getTrimmed`, `getTrimmedOrEmpty` | unquoted values are already trimmed; quoted whitespace was intentional |
| `getIntInRange`, `getDoubleInRange`, `getClampedInt` (+2 `require*`) | `getAs` with a validating parser, or caller-side `clamp()` |
| `getListOrEmpty` | `getListOr(k, const [])` |
| `isEnabled`, `isDisabled` | `getBoolOr` — and `isDisabled(k, defaultValue: true)` currently returns `false`, because the default is negated with the value |
| `isOneOf` | `values.contains(doc[k])` |
| `hasAllKeys`, `requireKeys` | `keys.every(doc.containsKey)` |
| `getAsWith`, `requireAsWith` | document-aware converters: niche, and the document is already in scope at the call site |

Also:

- [ ] `requireAllAs` currently returns `[]` for a missing key. `allAs` replaces
      it with defined semantics via `FlatLookup`.
- [ ] Narrow every `catch (_)` so `Error` subclasses thrown by user converters
      are not misreported as malformed config.
- [ ] Drop `preNormalizedLowerMapping` / `preNormalizedLowerValues` — internal
      performance knobs leaking into public signatures.

**Result: 66 methods → 19 in core, ~15 in the optional accessors library.**

### 2.7 Put everything on the class

Members are currently spread across `FlatDocument` plus four extensions
(`FlatDocumentAccessors`, `FlatDocumentExtensions`, `FlatDocumentIO`, and the
web `Object` stubs). Extensions can't be overridden, don't appear under the
class in dartdoc, and break if the wrong barrel is imported.

- [ ] Everything that is always available goes on `FlatDocument` itself.
- [ ] Use an extension only where a separate entry point requires it
      (`flatconfig_accessors.dart`, `flatconfig_io.dart`).

### 2.8 One error-reporting mechanism

`FlatParseOptions` currently carries `strict`, `onMissingEquals`, and
`onEmptyKey` — two typed callbacks that must grow a third every time a new
issue kind appears.

```dart
enum FlatIssueKind { missingEquals, emptyKey, unterminatedQuote, trailingAfterQuote }

final class FlatIssue {
  FlatIssueKind get kind;
  int get line;
  int get column;
  String get rawLine;
}

class FlatParseOptions {
  const FlatParseOptions({
    this.commentPrefix = '#',
    this.strict = false,
    this.decodeEscapes = true,      // was decodeEscapesInQuoted: false
    this.onIssue,
  });
  final void Function(FlatIssue issue)? onIssue;
}
```

- [ ] Replace both callbacks with `onIssue`. New issue kinds become additive.
- [ ] Export `FlatParseException` (currently the base class of exported
      subclasses is itself hidden).

### 2.9 Options as proper value types

- [ ] Sentinel-based `copyWith` so nullable fields can be cleared. Today
      `FlatEnvOptions(prefix: 'APP_').copyWith(prefix: null)` still returns `APP_`.
- [ ] Defensively copy `FlatEnvOptions.defaults` and `merge` — they currently
      retain caller-owned mutable maps.
- [ ] Add value equality and useful `toString()`.
- [ ] Validate invalid combinations at construction.
- [ ] Split by responsibility: `FlatParseOptions`, `FlatEncodeOptions`,
      `FlatDecodeOptions`, `FlatEncodeStreamOptions`, `FlatIncludeOptions`,
      `FlatEnvOptions`, `FlatDataOptions`. Move `includeKey` and
      `maxIncludeDepth` out of `FlatParseOptions`.

### 2.10 Safer environment defaults

`interpolate` defaults to `true` and unknown variables silently become the empty
string: `{'URL': r'https://${NOPE}/api'}` yields `https:///api`.

- [ ] Default `interpolate` to `false`.
- [ ] Add `MissingVariablePolicy { preserve, empty, error }`, default `preserve`.
- [ ] Add key transformation (`stripMatchedPrefix`, `keySplitOn`/`keyJoinWith`,
      `lowercaseKeys`) so `APP_WINDOW_WIDTH` → `window.width` without manual
      post-processing. Specify whether `${VAR}` references original env names or
      transformed keys — transform runs **after** interpolation.
- [ ] Keep `Platform.environment` access in `flatconfig_io.dart`.

### 2.11 Async-first include resolution

The sync-only resolver structurally excludes HTTP, database, and Flutter
`rootBundle` resolvers, since `rootBundle.loadString()` is async. Flutter users
can parse an asset config today but can never follow an include from one.

```dart
final class IncludeRequest {
  const IncludeRequest(this.target, {this.fromId});
  final String target;
  final String? fromId;
}

abstract interface class IncludeResolver {
  Future<IncludeUnit?> resolve(IncludeRequest request);
}

abstract interface class SyncIncludeResolver {
  IncludeUnit? resolveSync(IncludeRequest request);
}
```

- [ ] Make Ghostty precedence an explicit `IncludeMergePolicy` rather than the
      only implicit behavior.
- [ ] Expose include parsing from `flatconfig_includes.dart`, not from a static
      extension namespace.
- [ ] Make `IncludeUnit` immutable with value equality.

### 2.12 Fix the include cache

Cache keys contain only a canonical path or unit ID, but cached output also
depends on content, parse options, encoding, include key, and resolver
behavior. Reuse after any of those change silently returns stale output.

- [ ] Prefer invocation-local caches; drop the public `cache:` parameter.
- [ ] If a public cache remains, use a typed abstraction whose key includes the
      relevant inputs, with explicit invalidation.

### 2.13 Split the entry points

```text
package:flatconfig/flatconfig.dart            core: entries, document, options, primitive reads
package:flatconfig/flatconfig_io.dart         VM-only file reads/writes, Platform.environment
package:flatconfig/flatconfig_includes.dart   units, resolvers, include options, merge policies
package:flatconfig/flatconfig_accessors.dart  DateTime, Duration, Uri, JSON, enum
```

- [ ] This removes the web stub's `extension ... on Object`
      (`lib/src/io_stub.dart:71`), which currently makes `'text'.parseFlat()`
      compile cleanly and fail at runtime. On web you simply don't import
      `flatconfig_io.dart`.
- [ ] Choose **one** canonical file API. Today top-level functions, `File`
      extensions, and `FlatDocument.saveToFile()` duplicate the same workflow.
      Proposed: keep only the `File` extensions.
- [ ] Export every type appearing in a public signature. Currently
      `FlatConverter`, `FlatAdvancedConverter`, and `FlatParseException` are not
      exported.
- [ ] Delete the placeholder classes `FlatConfigIO {}` / `FlatDocumentIO {}`.

---

## Phase 3 — Testing

**Effort:** 2 days.

The existing 100% line coverage is real but proves less than it appears:
`test/full_coverage_test.dart` is an import-only file with no assertions. What
is missing is invariant testing.

- [ ] **Round-trip property test:** `parse(doc.encode()) == doc` over generated
      documents containing empty strings, quotes, backslashes, `=`, unicode,
      duplicate keys, and resets. This single test would have caught three
      Phase 1 defects.
- [ ] **Editing-algebra property tests:** `doc.set(k,v)[k] == v`;
      `doc.remove(k).containsKey(k) == false`; `doc.add(...)` leaves the
      original untouched; `a.concat(b).toMap() == {...a.toMap(), ...b.toMap()}`.
- [ ] **API-surface test** per entry point: import only that barrel, instantiate
      every type appearing in a public signature.
- [ ] Regression test for each Phase 1 defect.
- [ ] Under-exercised paths: strict vs lax stream parsing, BOM + CRLF + CR
      combined, include cycle detection, async resolver failure modes.
- [ ] Replace or document `full_coverage_test.dart`; measure branch coverage.
- [ ] CI matrix: minimum SDK + stable · `dart compile js` + `wasm` · browser
      tests · assertions-disabled run · `dart format --set-exit-if-changed` ·
      `dart pub publish --dry-run` · `flutter analyze` + `flutter test` in the
      example.

---

## Phase 4 — Release engineering and docs

**Effort:** 2 days.

### 4.1 Clean the published archive

Currently shipped to pub.dev: `PACKAGE_REVIEW.md` (39 KB), `improvements.md`
(36 KB), `tool/tmp_bench.conf` (171 KB), the `justfile`, and an empty
`coverage-review/` directory. There is no `.pubignore`.

- [ ] Add `.pubignore`. Delete `PACKAGE_REVIEW.md`, `improvements.md`,
      `coverage-review/`. Remove the unused `mocktail` dev dependency.

### 4.2 Fix the README contradictions

- [ ] Line 163 claims the `=` separator is customizable. It is hardcoded.
- [ ] Line 472 says `key =` yields `""`. It yields `null`, and line 161 already
      says so correctly.
- [ ] Line 732 documents `FlatDocument.fromDynamicMap`, which does not exist.
- [ ] The "Round-Trip Example" only demonstrates cases that happen to work.

### 4.3 Restructure the docs

- [ ] Split the 907-line README into ~200 lines plus `doc/`: `behavior.md`,
      `parsing.md`, `document-model.md`, `accessors.md`, `includes.md`,
      `environment.md`, `platform-io.md`, `migration.md`, `development.md`.

### 4.4 Fix the Flutter example

- [ ] `test/widget_test.dart` is still the generated counter template and fails.
- [ ] Convert `MyApp` to a `StatefulWidget` with the future cached in
      `initState()`; it currently recreates the future on every rebuild.
- [ ] Add an async `AssetBundleIncludeResolver` to the example — it is the
      clearest demonstration of why Phase 2.11 matters.
- [ ] Stop excluding the example from the root analyzer.

### 4.5 Versioning and migration

- [ ] Add an `[Unreleased]` changelog section now. `fromEnvironment` and
      `FlatEnvOptions` are already public on `main` while the version is still
      `0.5.0`, so two public APIs share one version number.
- [ ] `doc/migration.md`: complete 0.5.x → 1.0.0 rename/removal table with
      before/after examples. **No runtime compatibility shims.**
- [ ] `CONTRIBUTING.md`, issue templates.
- [ ] Verify the public API delta against the 0.5.0 tag before release.

---

## Phase 5 — After 1.0

- Source spans on parsed entries for richer diagnostics.
- Configurable duplicate-key policy (`preserve` | `first` | `last` | `error`).
- Resolved-map diff, in an extras library.
- `flatconfig_schema` as a companion package.

**Out of core:** schema validation, code generation, file watching, dotenv
compatibility, framework-specific colors and locales, network clients,
customizable separators.

---

## Ordering

| Phase | Content | Days | Gate to proceed |
|-------|---------|------|-----------------|
| 0 | `SPEC.md` | 0.5 | Every ambiguity has one stated answer |
| 1 | Correctness | 2–3 | Round-trip property test passes |
| 2 | 1.0 API | 6–8 | All four entry points compile for JS and WASM |
| 3 | Testing | 2 | Full CI matrix green |
| 4 | Release | 2 | Clean dry-run; migration guide complete |

## Surface budget

| | 0.5.0 | 1.0.0 target |
|---|---|---|
| Types users must learn to parse a file | 3 (`FlatConfig`, `FlatDocument`, `FlatEntry`) | 2 |
| Members reachable on a `FlatDocument` | ~140 | ~45 |
| Accessor methods | 66 | 19 core + ~15 optional |
| Ways to build from a map | 4 | 1 |
| Ways to merge | 3 | 1 (`concat`) |
| Ways to write a file | 3 | 1 |
| `strict`-style booleans in factories | 5 | 0 |
