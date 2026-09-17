# Flatconfig Package Review

Date: 2026-09-17  
Package version: 1.0.0  
Reviewed revision: `17dd7cdf` (`chore(release): 1.0.0`)  
Dart SDK used for verification: 3.13.3 stable

## Executive summary

The package has a strong engineering baseline: its public libraries are clearly
separated by platform capability, the document model is immutable, static
analysis is strict, and the test suite covers VM, release, browser, JavaScript,
Wasm, and Flutter consumers.

Despite those strengths, the current 1.0.0 release should not be published
unchanged. The review confirmed one high-severity resource-exhaustion issue and
multiple medium-severity correctness, round-trip, filesystem identity, and API
contract defects. Several documentation examples also contradict the parser.

No files were changed as part of the review other than adding this report.

## Verification performed

- `dart analyze --fatal-infos --fatal-warnings`: passed
- `dart format --output=none --set-exit-if-changed ...`: passed
- VM test suite: 839 tests passed
- Assertions-disabled suite (`dart test --compiler exe`): 839 tests passed
- Chrome suite: 564 tests passed
- Flutter example: analysis passed; 10 tests passed
- JavaScript compilation: passed
- Wasm compilation: passed
- Clean-checkout `dart pub publish --dry-run`: passed with zero warnings
- Clean package archive size: 206 KB
- `dart doc --validate-links`: completed with 34 warnings
- Working copy was clean before this report was added

The committed coverage report records 1304 of 1310 executable lines covered
(99.54%). The findings below demonstrate why high line coverage does not replace
edge-case and property-based contract tests.

## Severity definitions

- **High:** Can exhaust resources or substantially compromise processing of a
  small, valid-looking input. Fix before release.
- **Medium:** Causes silent data loss, incorrect document contents, API
  divergence, or a broken normative contract. Fix before release where
  practical.
- **Low:** Narrow edge case, diagnostics defect, documentation defect, or
  release-hardening opportunity.

## Findings

### F-01 — Include graphs can expand exponentially

**Severity:** High

**Affected code:**

- `lib/src/include_traversal.dart:40-84`
- `lib/src/parse_with_resolver.dart:94-121`
- `lib/src/parse_with_resolver.dart:143-170`
- `lib/src/include_assembly.dart:84-124`

**Observed behavior:**

An eight-level acyclic graph in which each unit includes the preceding unit
twice produces 256 copies of the leaf entry. The default depth limit permits
much deeper paths and therefore does not provide a practical output bound.

The traversal cache avoids reparsing a completed unit, but every include
directive still copies the complete expanded entry list into its parent.
Maximum depth limits recursion only; it does not limit include edges, expanded
entries, decoded bytes, or assembled bytes.

**Impact:**

A small configuration or resolver response can consume excessive memory and
CPU. This applies to file, memory, asset, database, and network-backed
resolvers.

**Recommendation:**

Add traversal-wide limits for:

- resolved units or include edges;
- total expanded entries;
- total source bytes or characters;
- optionally total assembled output size.

Enforce each limit before `addAll`, list spreading, or further recursive
resolution. Add bounded tests that assert rejection before substantial
allocation.

### F-02 — Empty include directives duplicate following entries

**Severity:** Medium

**Affected code:**

- `lib/src/include_assembly.dart:31-59`
- `lib/src/include_assembly.dart:130-150`
- `test/regressions_test.dart:153-172`

**Reproduction:**

```dart
final doc = parseWithIncludesSync(
  'a = 1\nconfig-file =\nb = 2\n',
  resolver: MemoryIncludeResolver(const {}),
);
```

Under the default `ghostty` merge policy, `doc.entries` is equivalent to
`[a=1, b=2, b=2]`.

`collectIncludes` does not mark an empty directive as an include, so `b` enters
`preIncludeEntries`. `_tailEntries`, however, treats every entry using the
include key as the tail boundary and adds `b` again.

Existing tests inspect only `toMap()`, which hides the duplicate.

**Recommendation:**

Define one shared predicate for an actionable include directive and use it for
target collection, pre-include collection, and tail detection. Assert exact
entry order and count for empty, `?`, `""`, and `?""` directives.

### F-03 — Custom comment prefixes can silently delete encoded keys

**Severity:** Medium

**Affected code:**

- `lib/src/validation.dart:21-47`
- `lib/src/document.dart:851-893`
- `SPEC.md:62-68`

**Reproduction:**

```dart
final source = FlatDocument([
  FlatEntry(';secret', 'value'),
]).encode(
  options: const FlatEncodeOptions(commentPrefix: ';'),
);

final parsed = FlatDocument.parse(
  source,
  options: const FlatParseOptions(commentPrefix: ';'),
);
```

The key is valid at construction, encodes as `;secret = value`, and is then
discarded as a comment. The specification explicitly requires the encoder to
throw in this case.

**Recommendation:**

Before encoding, reject any key beginning with the configured non-empty comment
prefix. Add round-trip tests for custom prefixes.

### F-04 — Cyclic map input causes a stack overflow

**Severity:** Medium

**Affected code:**

- `lib/src/from_map_data.dart:158-234`

**Reproduction:**

```dart
final map = <String, Object?>{};
map['self'] = map;
FlatDocument.fromData(map);
```

This ends in `StackOverflowError`. A multi-node map cycle behaves similarly.
Very deep acyclic structures also have no explicit flattening depth guard.

**Recommendation:**

Track active map and list identities during recursion, reject cycles with a
controlled `ArgumentError`, and add a configurable or documented maximum
flattening depth.

### F-05 — Filesystem case probing can merge distinct files

**Severity:** Medium

**Affected code:**

- `lib/src/path_utils.dart:40-89`
- `lib/src/include_traversal.dart:40-84`

On a case-sensitive filesystem, two distinct case-variant files are considered
the same file when their size and modification timestamp match. The result is
cached for the entire directory.

This can produce a false cache hit, substitute one configuration for another,
or report a false include cycle. Windows is also assumed to be uniformly
case-insensitive despite support for case-sensitive directories.

**Recommendation:**

Use real filesystem identity, such as `FileSystemEntity.identicalSync`, rather
than metadata equality. Keep the conservative case-sensitive fallback when
identity cannot be established.

### F-06 — Include paths are decoded twice

**Severity:** Medium

**Affected code:**

- `lib/src/parser_utils.dart:65-130`
- `lib/src/include_path_utils.dart:34-53`
- `SPEC.md:90-134`

Quoted values are decoded by the normal parser and then unconditionally decoded
again by `processIncludePath`. Unquoted include paths are also decoded even
though the specification defines unquoted backslashes as literal.

A quoted UNC-style path can reach the resolver with one leading backslash
instead of two.

**Recommendation:**

Preserve whether the parsed token was quoted and whether escapes have already
been decoded. Decode quoted include paths exactly once and never escape-process
unquoted paths.

### F-07 — The normative include contract contradicts the default behavior

**Severity:** Medium

**Affected code and documentation:**

- `SPEC.md:195-218`
- `lib/src/options.dart:115-170`
- `lib/src/include_assembly.dart:73-124`
- `CHANGELOG.md:3-8`

The specification requires textual, in-place include expansion followed by
ordinary last-write-wins resolution. The public API deliberately defaults to
`IncludeMergePolicy.ghostty`, where includes are moved after local entries and
can remove local tail entries.

The API guide documents the Ghostty behavior, so this is not an accidental
implementation branch. It is a normative contract contradiction, especially
because the changelog claims complete specification conformance.

**Recommendation:**

Choose and document one of these approaches before release:

1. Make `lastWins` the default to conform to the existing specification.
2. Make the specification policy-aware and explicitly define `ghostty` as the
   API default.

Also update conformance tests so they compare the selected policy with the
corresponding normative rule.

### F-08 — `collapse(ignoreResets: true)` still emits and reorders resets

**Severity:** Medium

**Affected code:**

- `lib/src/document.dart:736-829`
- `test/document_extensions_test.dart:210-248`

A document containing only `FlatEntry('a', null)` still contains that reset
after collapse. With `CollapseOrder.lastWrite`, an ignored trailing reset moves
the retained earlier value to the reset's position.

Ignored resets create anchors and update `lastIndex`, while no value is added to
`lastVal`. The missing map value is later interpreted as a reset.

**Recommendation:**

When `ignoreResets` is true, reset entries must not create or update anchors.
Track whether a non-reset value exists separately. Add reset-only and trailing
reset ordering tests.

### F-09 — Symlinked includes resolve differently across public APIs

**Severity:** Medium

**Affected code:**

- `lib/src/includes.dart:151-162`
- `lib/src/includes.dart:186-196`
- `lib/src/include_resolver_io.dart:17-42`
- `lib/src/parse_with_resolver.dart:10-20`

The direct `File` API resolves a nested relative include against the symlink's
lexical directory. `FileIncludeResolver` returns the symlink target's canonical
path as the unit ID, so the next relative include resolves against the target
directory.

The two APIs therefore produce different documents from the same files despite
being documented as equivalent.

**Recommendation:**

Separate canonical identity from the path used as the next resolution base.
Store both in `IncludeUnit` or in resolver-specific context, and apply one
documented rule consistently.

### F-10 — Permission failures can be reported as missing files

**Severity:** Medium

**Affected code:**

- `lib/src/includes.dart:151-154`
- `lib/src/includes.dart:186-189`
- `lib/src/includes.dart:239-244`
- `lib/src/includes.dart:278-284`
- `lib/src/include_resolver_io.dart:26-40`

The implementation checks `exists` before reading. Filesystem access failures
may therefore appear as `false`, causing:

- optional includes to be silently skipped;
- required includes to throw `MissingIncludeException`;
- `FileIncludeResolver` to return `null`.

This also introduces an existence-check/read race.

**Recommendation:**

Attempt the read directly. Convert only genuine not-found failures into a
missing include and propagate permission or policy errors unchanged.

### F-11 — Resolver-based file parsing ignores the requested encoding

**Severity:** Medium

**Affected code:**

- `lib/src/parse_with_resolver.dart:32-73`
- `lib/src/parse_with_resolver.dart:174-180`
- `lib/src/include_resolver_io.dart:40`
- `lib/src/includes.dart:283-287`
- `doc/platform-io.md:31-32`

Resolver entry points accept `FlatStreamReadOptions`, but included text has
already been decoded by the resolver. `FileIncludeResolver` always uses
`readAsStringSync()` with the default UTF-8 encoding.

A Latin-1 include succeeds through the direct file API with Latin-1 read
options and fails through `FileIncludeResolver` with the same read options.

**Recommendation:**

Either:

- give `FileIncludeResolver` an explicit encoding;
- let resolvers return bytes plus an identity;
- or remove the ineffective encoding option from text/resolver entry points.

### F-12 — `stripPrefix` silently drops valid source entries

**Severity:** Medium

**Affected code:**

- `lib/src/document.dart:1143-1168`

A valid source key such as `window.#secret` or `window. padded` becomes invalid
after removing `window.`. The method silently skips the entry.

**Recommendation:**

Preflight the transformation and throw an informative `ArgumentError`, or add
an explicit invalid-result policy. Silent dropping should not be the default.

### F-13 — An obsolete top-level API remains public

**Severity:** Medium

**Affected code and documentation:**

- `lib/flatconfig.dart:31-42`
- `lib/src/from_map_data.dart:157-171`
- `test/barrel_core_test.dart:41-44`
- `ROADMAP_1.0.md:335-342`

`flatDocumentFromMapData` remains exported even though the 1.0 roadmap says it
was replaced by `FlatDocument.fromData`.

**Impact:**

If 1.0.0 is published with this symbol, removing it later requires another
breaking release.

**Recommendation:**

Remove the export before release if it is accidental. If compatibility is
intentional, document it and mark its future status explicitly.

### F-14 — `varPattern` validation does not validate a capture group

**Severity:** Low

**Affected code:**

- `lib/src/options.dart:465-481`
- `lib/src/parser.dart:350-381`

Validation checks only whether the pattern source contains `(`. A non-capturing
group passes and later causes `RangeError` at `group(1)`. An optional first
capture can produce a null-check type error.

**Recommendation:**

Validate the actual first capture when matches occur, or require a named,
non-optional capture and convert violations into a controlled `ArgumentError`.

### F-15 — Large finite durations can escape the nullable accessor contract

**Severity:** Low

**Affected code:**

- `lib/src/optional_accessors.dart:53-82`

A very large but finite parsed number can overflow to infinity after multiplying
by the unit scale. Calling `round()` then throws `UnsupportedError` instead of
returning `null` or the fallback.

**Recommendation:**

Check the scaled result for finiteness and range before rounding.

### F-16 — Parser entry points disagree on Unicode-only whitespace

**Severity:** Low

**Affected code:**

- `lib/src/parser.dart:47-59`
- `lib/src/parser_utils.dart:139-144`

In strict mode, `FlatDocument.parse('\u00A0')` returns an empty document because
the whole-source shortcut uses `String.trim()`. `parseLines(['\u00A0'])` and the
line-stream path report a missing separator because the grammar recognizes only
space, tab, CR, and LF.

**Recommendation:**

Remove the whole-source shortcut and route every input shape through the shared
line grammar.

### F-17 — Arbitrary line terminators can corrupt output

**Severity:** Low

**Affected code:**

- `lib/src/options.dart:252-268`
- `lib/src/validation.dart:82-87`
- `lib/src/document.dart:910-922`

Only an empty terminator is rejected. `lineTerminator: '|'` writes multiple
entries onto one physical line, which reparses as one entry.

**Recommendation:**

Restrict the option to `\n`, `\r`, and `\r\n`.

### F-18 — Diagnostic columns and `FormatException.offset` are incorrect

**Severity:** Low

**Affected code:**

- `lib/src/parser.dart:470-534`
- `lib/src/parser_utils.dart:73-121`
- `lib/src/exceptions.dart:14-23`

Leading indentation is discarded before some positions are calculated. Strict
quoted-value exceptions omit the key/value offset that lenient issues include.
Invalid-key exceptions default to column zero. Finally, the displayed 1-based
column is passed directly to the zero-based `FormatException.offset`.

Malformed input is still detected, but editor highlighting and error locations
are unreliable.

**Recommendation:**

Preserve the raw-line offset, calculate one absolute zero-based offset, and
derive the displayed 1-based column from it for both strict and lenient paths.

### F-19 — `getList` documentation promises unsupported quoting

**Severity:** Low

**Affected code and documentation:**

- `lib/src/document.dart:530-550`
- `lib/src/parser_utils.dart:302-329`
- `doc/accessors.md:28-38`

The guide says quoted items may contain the separator, but `getList` uses plain
`String.split`. For example, `a,"b,c",d` becomes four fragments rather than
three items.

**Recommendation:**

Use the package's quote-aware splitting and value decoding helpers, or narrow
the guide to the actual plain-split contract.

### F-20 — BOM handling contradicts the normative format

**Severity:** Low

**Affected code and documentation:**

- `lib/src/parser.dart:550-561`
- `SPEC.md:16-23`
- `test/stream_reading_test.dart:73-106`

The specification says only the BOM at the beginning of the entire input is
discarded. The parser strips a BOM at the beginning of every line, and the test
suite explicitly pins that contradictory behavior.

**Recommendation:**

Track whether the parser is processing the first document line, or revise the
normative character model and conformance claim.

### F-21 — Empty comment-prefix behavior contradicts the specification

**Severity:** Low

**Affected code and documentation:**

- `lib/src/options.dart:41-46`
- `lib/src/validation.dart:89-100`
- `SPEC.md:40-43`

The implementation deliberately allows an empty prefix to disable comments.
The normative specification requires a non-empty prefix.

**Recommendation:**

Choose one behavior and align the implementation, tests, specification, and
migration guide.

### F-22 — Published documentation contains behaviorally incorrect examples

**Severity:** Low

**Affected documentation and examples:**

- `README.md:108-127`
- `doc/includes.md:5-12`
- `doc/includes.md:103-110`
- `doc/parsing.md:39-54`
- `doc/migration.md:337-339`
- `example/io.dart:13-22`
- `example/ghostty_semantics_tail_blocking.dart:7-16`

Problems include:

- unsupported inline comments that become part of values or include paths;
- claims that `\n` inside quotes decodes to a line break, although only `\"`
  and `\\` are recognized;
- annotations in executable configuration strings that change demonstrated
  results.

**Recommendation:**

Move annotations to full comment lines and document exactly the two supported
escape sequences.

### F-23 — The error-handling example does not demonstrate its claims

**Severity:** Low

**Affected code:**

- `example/error_handling.dart:6-76`

The first four examples use the default lenient mode, so their exception
handlers never run. The fifth section claims to show warnings but supplies no
`onIssue` callback.

Observed output contains empty sections 1 through 4 and no warnings.

**Recommendation:**

Enable strict mode for exception examples and install an `onIssue` handler for
the lenient reporting example. Add example execution to CI.

### F-24 — The Flutter example README is stale

**Severity:** Low

**Affected documentation:**

- `example/flatconfig_flutter/README.md`

It references the removed `FlatConfig.parse` API, says the `debug` setting is
unused although it controls the debug banner, requires a leading `#` for colors
although the converter accepts both forms, and advertises native platforms even
though only web scaffolding is present.

**Recommendation:**

Rewrite the README against the current implementation and web-only project, or
add the advertised platform projects.

### F-25 — Public API documentation does not validate cleanly

**Severity:** Low

**Affected areas:**

- `lib/src/optional_accessors.dart`
- `lib/src/document.dart`
- `lib/src/options.dart`
- public barrel re-exports
- links from the package README

`dart doc --validate-links` reports 34 warnings. They include unresolved symbol
references, ambiguous canonical re-exports, and broken generated links.

**Recommendation:**

Correct stale references, add `{@canonicalFor ...}` annotations where
appropriate, and make Dartdoc link validation a CI gate.

### F-26 — Generated API documentation is not excluded from publishing

**Severity:** Low

**Affected configuration:**

- `.pubignore`

Running `dart doc` creates hundreds of files under `doc/api`. Because
`.pubignore` does not exclude that directory, a subsequent publish dry run
includes them, grows the archive from 206 KB to approximately 508 KB, and
reports hundreds of modified or added files.

**Recommendation:**

Add `doc/api/` to `.pubignore` and the repository ignore rules unless generated
API documentation is intentionally versioned and published.

### F-27 — Platform-specific path behavior lacks platform CI

**Severity:** Low

**Affected configuration:**

- `.github/workflows/test.yml`
- `lib/src/path_utils.dart`

All CI jobs run on Ubuntu, while filesystem identity and path code has behavior
specific to Windows, macOS, symlinks, and filesystem case sensitivity.

**Recommendation:**

Add focused Windows and macOS jobs for include, symlink, canonicalization, and
case-sensitivity tests.

### F-28 — Resolver caching happens after content is fetched

**Severity:** Low

**Affected code and documentation:**

- `lib/src/parse_with_resolver.dart:94-121`
- `lib/src/parse_with_resolver.dart:143-170`
- `lib/src/include_traversal.dart:65-84`
- `doc/includes.md:225-231`

The resolver must fetch and return an `IncludeUnit` before the traversal can
check its ID cache. Repeating the same include therefore calls the resolver
again, despite the guide saying a repeated document is read once.

**Recommendation:**

Either narrow the documentation to "parsed and expanded once", memoize
identical requests, or split identity resolution from content loading.

### F-29 — Invalid custom include keys silently disable resolution

**Severity:** Low

**Affected code:**

- `lib/src/options.dart:136-165`
- `lib/src/include_traversal.dart:20-28`

Values such as an empty string, a padded key, or a key containing `=` are
accepted by `FlatIncludeOptions`. No valid parsed entry can match them, so
include processing silently stops.

**Recommendation:**

Validate `includeKey` with the same key rules used by `FlatEntry`.

## Design advisories not classified as defects

### Filesystem containment

The file include APIs intentionally accept absolute paths and parent traversal.
That is normal for a trusted local configuration loader and is documented.
It is not inherently a vulnerability.

If applications may process untrusted configuration, provide or document a
restricted file resolver that:

- enforces a canonical allowed root after resolving symlinks;
- rejects non-regular files;
- limits bytes read;
- declines relative file resolution from non-file namespaces.

### Synchronous file resolver

`FileIncludeResolver` inherits the asynchronous adapter from
`SyncIncludeResolver`, so calling `resolve()` still performs synchronous
filesystem work. This is explicitly part of the synchronous resolver contract,
and callers have the direct asynchronous `File.parseWithIncludes()` API.
It is a performance characteristic, not a correctness defect.

### Unsafe encoder options

`escapeQuoted: false` and `quoteIfWhitespace: false` can deliberately produce
non-round-trippable output. Because callers explicitly opt into these settings,
they are not classified as implementation defects. Their documentation should
state the data-loss and malformed-output consequences prominently.

## Strengths

- Clear separation between web-safe core, optional accessors, resolver-based
  includes, and `dart:io` APIs.
- Immutable `FlatDocument` entry storage and defensive map caching.
- Strong default parser/encoder round-trip coverage.
- Good distinction between absent, reset, and empty-string states.
- Strict analyzer configuration with no suppressions in production code.
- Release-mode testing catches guards that accidentally rely on assertions.
- Browser, JavaScript, Wasm, and Flutter consumer checks.
- Clean package metadata, dependency bounds, license, and clean-checkout
  publishing archive.
- Barrel tests verify that package-owned public signature types are exported.

## Recommended remediation order

1. Add include expansion budgets and fix empty-directive assembly.
2. Fix custom-prefix round trips, map cycle handling, and reset collapsing.
3. Replace metadata-based filesystem identity and fix one-time include-path
   decoding.
4. Reconcile the normative include contract and other specification drift.
5. Make direct file and resolver file behavior consistent for symlinks,
   encoding, and filesystem errors.
6. Decide the final 1.0 public API, especially `flatDocumentFromMapData`.
7. Fix narrow validation and diagnostics issues.
8. Correct and execute published examples.
9. Make Dartdoc validation and platform-specific tests part of CI.

## Suggested release criteria

Before publishing 1.0.0:

- all High and Medium findings above are fixed or explicitly accepted and
  documented;
- every fix has a regression test asserting exact entries, not only `toMap()`;
- `SPEC.md`, implementation, changelog, and migration guide agree;
- all current analyzer, formatter, VM, release, browser, Flutter, JS, Wasm, and
  publish checks remain clean;
- `dart doc --validate-links` has no actionable warnings;
- the final publish dry run is performed from a clean working copy.
