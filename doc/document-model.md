# The document model

A `FlatDocument` is an ordered list of `FlatEntry` values. It is immutable:
every operation here returns a new document and leaves the original alone.

```dart
class FlatEntry {
  final String key;
  final String? value;   // null is an explicit reset: the line `key =`
}
```

## Two views of the same document

A key may appear more than once, which is a feature of the format rather than
an accident — it is how a later file overrides an earlier one. So there are two
ways to read a document, and most confusion comes from mixing them up.

The **entry view** is every line, in file order. The **resolved view** is one
value per key, the last one written.

```dart
final doc = FlatDocument.parse('''
shader = bloom
shader = vignette
''');

doc.entries;             // both entries, in order
doc.allValues('shader'); // ['bloom', 'vignette']

doc['shader'];           // 'vignette' — the resolved view
doc.toMap();             // {shader: vignette}
doc.keys;                // key order of first occurrence
```

`length`, `isEmpty` and `isNotEmpty` describe the entry view. The document is
deliberately not an `Iterable`: inheriting it put roughly forty members on the
type that silently meant "entries", including a `doc.contains(x)` sitting next
to a key lookup and meaning something else entirely. Write `doc.entries.…` and
it is clear which view you mean.

## Three states, not two

`doc['k'] == null` cannot tell apart a key nobody mentioned from one a file
deliberately cleared with `k =`. The difference usually decides whether your
default still applies, so it has its own return type.

```dart
final fontSize = switch (doc.lookup('font-size')) {
  FlatPresent(:final value) => int.parse(value),
  FlatReset() => systemDefault,   // a file cleared it on purpose
  FlatAbsent() => appDefault,     // nobody mentioned it
};
```

`FlatLookup` is sealed, so the switch is exhaustive without a fallback case.
`containsKey` answers the same question more coarsely: it is `true` for both
present and reset.

`operator []` stays as the nullable convenience for the common case where the
distinction does not matter.

## Editing

```dart
doc.withValue('theme', 'dark');   // one entry for the key, first position kept
doc.withValue('theme', null);     // writes `theme =`, an explicit reset
doc.without('theme');             // every occurrence goes
doc.withEntry(FlatEntry('shader', 'bloom'));  // appends, keeps the earlier one
```

`withValue` and `withEntry` differ in exactly the way the two views do.
`withEntry` is the format's own notion of a write: a later line shadows an
earlier one without erasing it. `withValue` leaves one entry, which is what you
want before writing a file back out — otherwise a program that edits and saves
in a loop grows the file on every run.

`without` removes an explicit reset too, so the key reads as absent afterwards,
not as cleared.

## Combining documents

In a last-write-wins format, appending already is merging.

```dart
final effective = base.concat(user);   // or base + user

effective.toMap();  // == {...base.toMap(), ...user.toMap()}
```

`concat` keeps every entry, so a key both documents write appears twice: the
later wins on lookup and both survive in `allValues`. That is what you want
while assembling. Before writing the result out, `collapse()` reduces it to one
entry per key.

There is no `override:` flag, because `a.merge(b, override: false)` is just
`b.concat(a)` read from the other end.

## Collapsing duplicates

```dart
doc.collapse();                                  // first position, last value
doc.collapse(order: CollapseOrder.lastWrite);    // move the key to its last write
doc.collapse(dropNulls: true);                   // drop resets entirely
doc.collapse(multiValueKeys: {'shader'});        // keep every value of these
doc.collapse(isMultiValueKey: (k) => k.startsWith('mv_'));
```

Collapsing is idempotent and never changes what the resolved view says; it only
changes how many entries carry it.

## Working with prefixes

The format has no sections. A prefix on a key does the same job, and two
helpers work with it on the resolved view.

```dart
final doc = FlatDocument.parse('''
window.width = 1200
window.height = 800
theme = dark
''');

doc.slice('window.');        // keys: window.width, window.height
doc.stripPrefix('window.');  // keys: width, height

doc.slice('window.').stripPrefix('window.');  // both, for a focused subdocument
```

Matching is literal and case-sensitive, so pass the separator yourself
(`'window.'`, not `'window'`). An empty prefix clones the document, duplicates
and order included. A key equal to the prefix would strip to an empty key, which
no document can hold, so `stripPrefix` drops that entry rather than producing a
line that cannot be read back.

Both return documents. For picking entries out rather than reshaping the
document, `whereKey(key)`, `whereKeys(keys)` and `whereValue(value)` match
exactly and yield an `Iterable<FlatEntry>` — the entry view, so a repeated key
yields each of its occurrences.

## Inspecting

```dart
print(doc.debugDump());
// [0] a = 1
// [1] b = null

print(doc.toPrettyString(includeIndexes: true, sortByKey: true, alignColumns: true));
```

Both are for humans reading a terminal. `encode()` is the one that produces
something the parser can read back; see [round-tripping](building.md#round-tripping).

## Caching

`toMap()` and `allValues()` build their result on first use and keep it. Calling
`cache()` does that work up front, for a document read in a hot loop:

```dart
final doc = FlatDocument.parse(source)..cache();
```

The cached views are unmodifiable, so handing one out cannot let a caller change
a document documented as immutable.
