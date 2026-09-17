# Pre-1.0 review, and what came of it

Three external reviews of the 1.0.0 candidate, and the disposition of every
finding. This supersedes the review documents themselves, which are gone; their
findings are listed below with their identifiers intact, because the
remediation commits refer to them.

| | |
|---|---|
| Reviewed | `17dd7cdf` — the commit that was going to be 1.0.0, at 839 tests |
| Re-reviewed | `0813492a` after the first round, `f945525d` after the second |
| Findings | 29 original (1 high, 12 medium, 16 low), 5 follow-up, 1 found while testing |
| Closed | every high and medium, and the low ones the guides got wrong |
| Open | 13 low, listed at the end |

The candidate was never published. pub.dev served 0.5.0 throughout, and the
premature `v1.0.0` tag was removed from both the local repository and origin.

## What the exercise was worth

All 839 tests and all seven CI jobs were green on `17dd7cdf`. The review found
thirteen high and medium defects in it, including one that turned under a
kilobyte of configuration into a million entries, and three that lost data
without a word.

That is not an argument against the test suite; it is what a test suite is. It
answers "does what I checked still hold", never "was what I checked the right
thing". Two of the defects are worth remembering for that reason:

- the duplicate entry from an empty include directive was invisible because the
  tests compared `toMap()`, where a key repeated with the same value resolves
  identically;
- the `ignoreResets` defect was invisible because both existing tests happened
  to end their key on a real value, the one shape in which the stale anchor is
  overwritten again.

The follow-up review then found that five of the thirteen fixes stopped one
layer short of the contract — most tellingly, the include budget was charged
where the recursion entered rather than where the request went out, and the
regression test written alongside it pinned the off-by-one as if it were the
intent.

A third round found that the depth limit added for one of those five covered
maps and not lists, which reach the JSON encoder instead of recursing. Writing
the test for that turned up the last one, **V-06**, which no review had named:
depth bounds how far a value nests, not how much it expands.

## High

### F-01 — Include graphs expand exponentially — closed

Each level including the one below it twice doubles the result. Because a
repeated unit is parsed once and then copied into every parent naming it,
sixteen levels stayed at 32 directives while reaching 65,536 entries — measured
from 708 characters of source, at depth 16 against a limit of 64. Twenty levels
is a million.

`FlatIncludeOptions.maxIncludedEntries` (100,000) bounds the result and is
charged as entries are handed up, so the refusal lands before the allocation.
`maxIncludes` (256) bounds how many directives are followed.

Follow-up **V-01**: `maxIncludes` was charged on entering the resolved unit, so
a directive the resolver could not answer cost nothing and a limit of zero
still permitted any number of requests. It is charged before the request now,
whether or not anything answers.

## Medium

### F-02 — Empty include directives duplicated the entries after them — closed

`config-file =` ended the head of the document without starting the tail, so
every entry below it was collected as both. Three separate answers to "is this
line a directive?" had drifted apart; `collectIncludes` gives one, in a single
pass, for every spelling that names nothing.

### F-03 — A custom comment prefix silently deleted encoded keys — closed

`;secret` is a valid key — validity is judged against the default `#` so that a
document does not become invalid because of the options of whoever reads it —
and it encoded to `;secret = value`, which re-parses as a comment under a
non-default prefix. `SPEC.md` §3 always required the encoder to refuse this.

### F-04 — Cyclic map input overflowed the stack — closed

A map or list containing itself now raises an `ArgumentError` naming the key
path. Detection is by identity, so the same map used twice as a sibling is
sharing rather than recursion.

Follow-up **V-02**: deep but finite nesting still recursed until the stack ran
out. `FlatDataOptions.maxDepth` (64) bounds it — for maps at first, and then
for lists too, which never recurse through the flattener at all: a composite
item goes to the JSON encoder, and that walks it recursively. Both are checked
level by level now, so the check itself cannot be what overflows.

**V-06**, found while testing V-02 and named in no review: depth bounds how far
a value nests, not how much it expands. JSON has no sharing, so a node holding
the same child twice doubles per level — forty levels is eighty objects in
memory and 2^40 written out, which hung the test suite for four minutes.
`FlatDataOptions.maxEncodedNodes` (1,048,576) bounds the output, counted as the
walk goes rather than by trying every path.

### F-05 — Filesystem case probing could merge distinct files — closed

Whether two spellings were one file was inferred from size and modification
time, which two distinct files share as soon as they are the same length and
were written in the same second. `FileSystemEntity.identicalSync` answers it
now.

Follow-up **V-03**: an undecidable probe fell back to `Platform.isWindows`,
against this class's own stated preference for the conservative answer. It
falls back to "case-sensitive" everywhere, and the fallback is injectable so
the branch is testable off the host filesystem.

### F-06 — Include paths were decoded twice — closed

Every path was escape-decoded, quoted or not, so a bare Windows UNC path
reached the resolver with one leading backslash instead of two.

Follow-up **V-04**: deciding by appearance took a second layer off a name that
genuinely contains quotes. Quotes are removed only behind a `?` marker, which
is the one case the parser cannot see through; without it the parser has
already unquoted the value.

### F-07 — The spec contradicted the default include behaviour — closed

`SPEC.md` §8 described in-place expansion with ordinary last-write-wins, which
is `IncludeMergePolicy.lastWins`, not the `ghostty` default. The section defines
both policies and names the default, and the conformance suite — which had no
include tests at all — checks each against its own rule.

### F-08 — `collapse(ignoreResets: true)` emitted and reordered resets — closed

An ignored reset still claimed a position, so a key written only as a reset
survived as one and a trailing reset moved the value it was supposed to leave
alone.

### F-09 — Symlinked includes resolved differently across APIs — closed

`File.parseWithIncludes` resolved a nested relative include against the
directory the symlink sits in; `FileIncludeResolver` against the directory it
points at. Both follow the link now, which suits how configuration is kept: a
file symlinked out of a dotfiles repository finds its neighbours there.

Follow-up **V-05**: only included children were covered; a symlinked root still
parted ways. `FileIncludeResolver` resolves a file-backed origin before taking
its directory, falling back to the lexical form for an origin that is not a
path.

### F-10 — Permission failures were reported as missing files — closed

An existence check answered for a moment that had passed by the time of the
read, and reported every other failure — no permission, a directory in the way,
a symlink loop — as absence, which a required include turned into
`MissingIncludeException` and an optional one skipped in silence. It reads
first, and only `PathNotFoundException` counts as missing.

### F-11 — Resolver file parsing ignored the requested encoding — closed

`FileIncludeResolver` always read UTF-8. It takes an encoding now. A resolver
hands the traversal text, so `FlatStreamReadOptions.encoding` cannot reach one
at all, and the entry points say so.

### F-12 — `stripPrefix` silently dropped entries — closed

`window.#secret` and `window. padded` are valid keys that strip to invalid
ones. The operation throws and names the key instead of losing the entry.

### F-13 — An obsolete top-level API stayed public — closed

`flatDocumentFromMapData` is no longer exported. `FlatDocument.fromData` is the
spelling.

## Low

Closed, because a guide claimed something the code did not do:

- **F-19** — `getList` split on every separator while the guide promised the
  format's inline grammar. It reads that grammar now and unquotes each item.
- **F-22** — two separate problems. `doc/parsing.md` claimed `"a\nb"` holds a
  line break and that "`\"`, `\\` and friends" are decoded; there are exactly
  two escapes, and a value cannot hold a line break at all. Separately, the
  published examples annotated configuration lines with inline comments, which
  this format does not have: `config-file = ?user.conf  # optional` asked for a
  file whose name ends in the annotation, and the quoted examples in `README.md`
  and `example/io.dart` raised `trailingAfterQuote`. Every annotation now sits
  on a comment line of its own.

Also handled in passing:

- **F-26** — `.pubignore` now excludes `doc/api/`, which `dart doc` fills and
  which tripled the archive.

Still open, thirteen of them, to be assessed before the tag: **F-14** through
**F-18**, **F-20**, **F-21**, **F-23** through **F-25**, **F-27** through
**F-29**. Two are specification deviations and matter most: a BOM is stripped
from every line rather than only at the start of the document, and an empty
comment prefix is accepted although the specification requires a non-empty one.
Until those are settled, no claim of complete conformance belongs in the
changelog.

**F-19** counts as closed above, but on a narrowed contract: `getList` reads
the format's single-character inline grammar, where it used to take any
separator and split on every occurrence. The alternatives — RFC 4180, or a
plainer list grammar — were not chosen, and that decision is worth recording
rather than rediscovering.

`dart doc --validate-links` reports 34 warnings (**F-25**), and every CI job
runs on Ubuntu while the path code branches on Windows and on case-insensitive
volumes (**F-27**) — the identity test written for F-05 skips on macOS for
exactly that reason.
