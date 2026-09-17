# Building documents

Parsing is one direction. This page is the other: building a `FlatDocument` in
code, from a map, from the environment, or from nested data, and writing it back
out as something a human can edit.

## From a map or a list of entries

```dart
final shallow = FlatDocument.fromMap({
  'theme': 'dark',
  'font-size': '14',
});

final entries = FlatDocument.fromEntries([
  FlatEntry('theme', 'dark'),
  FlatEntry('accent', 'mint'),
]);

final one = FlatDocument([FlatEntry('theme', 'dark')]);
final none = FlatDocument.empty();
```

`fromMap` is **shallow**: one map entry becomes one document key, and a nested
map or list is not traversed. For structured data, see
[`fromData`](#from-nested-data) below.

Values are `String?`, and stringifying is left to you, so the formatting
decision stays where the type is known:

```dart
final settings = {'version': 2.0, 'enabled': true};

final doc = FlatDocument.fromMap({
  for (final e in settings.entries) e.key: e.value.toString(),
});
```

A key these factories cannot represent raises an `ArgumentError` where you wrote
it, rather than producing a file that reads back as something else. See
[parsing](parsing.md#entries-are-valid-by-construction).

## From the environment

`FlatDocument.fromEnvironment` reads an environment-like map. It is pure — it
touches no ambient state, so pass `Platform.environment` yourself. That keeps it
usable on the web and in tests, where there is no such thing.

```dart
final doc = FlatDocument.fromEnvironment(
  Platform.environment,
  options: FlatEnvOptions(
    prefix: 'APP_',
    stripMatchedPrefix: true,
    keySplitOn: '_',
    keyJoinWith: '.',
    lowercaseKeys: true,
  ),
);
// APP_WINDOW_WIDTH=1280  becomes  window.width = 1280
```

Precedence runs `defaults` → environment → `merge`. The key rewrite runs last,
after interpolation, so a `${VAR}` names an environment variable rather than
whatever that variable's key was rewritten into.

Two defaults are deliberately cautious.

**Interpolation is off.** A variable's value is data your program did not write,
and a `$` in it is more often a password than a reference. When you turn it on,
`missingVariable` decides what `${NOPE}` becomes: `preserve` (the default)
leaves the placeholder visible so it points at the typo, `empty` behaves like a
POSIX shell, and `error` throws, naming both the variable and the value that
references it.

**A value containing a line break is an error.** No document can hold one,
because the format is line-based. Set
`multilineValue: MultilineValuePolicy.skip` to drop such a variable and keep the
rest — useful when the environment carries a PEM key your program never reads.

## From nested data

`FlatDocument.fromData` flattens maps and lists into key paths.

```dart
final doc = FlatDocument.fromData({
  'theme': 'dark',
  'window': {'width': 5120, 'height': 2160},
  'features': ['a', 'b', 'c'],
});

// theme = dark
// window.width = 5120
// window.height = 2160
// features = a
// features = b
// features = c
```

A list becomes one entry per item by default, which is why `doc.toMap()` reports
only the last one — `allValues('features')` is the view that shows all three.
Switch to `FlatListMode.csv` for a single entry instead.

### Options

| Option | Default | Effect |
|---|---|---|
| `separator` | `'.'` | joins nested key segments |
| `listMode` | `FlatListMode.multi` | one entry per item, or one CSV entry |
| `csvSeparator` | `', '` | separator in CSV mode |
| `csvNullToken` | `''` | how `null` appears in a CSV list |
| `dropNulls` | `false` | omit `null` values entirely |
| `maxDepth` | `64` | how deep nesting may go |
| `maxEncodedNodes` | `1048576` | how much a composite may expand to |
| `valueEncoder` | `null` | override for any value; highest priority |
| `onUnsupportedListItem` | `encodeJson` | composite list items: `encodeJson`, `skip` or `error` |
| `keyEscaper` | `null` | escapes a key containing the separator |
| `csvItemEncoder` | `null` | quoting and escaping hook for CSV items |

```dart
final doc = FlatDocument.fromData(
  {
    'window': {'w': 5120, 'h': 2160},
    'colors': ['red', 'mint,green', 'blue'],
  },
  options: FlatDataOptions(
    listMode: FlatListMode.csv,
    csvSeparator: ',',
    csvItemEncoder: rfc4180CsvItemEncoder(','),   // safe quoting
    keyEscaper: (k) => k.replaceAll('.', r'\.'),  // dots in keys
  ),
);

doc['colors'];  // red,"mint,green",blue
```

Only the item that needs it is quoted. Encoding that document quotes the whole
value in turn, because it now contains quotes of its own:

```conf
colors = "red,\"mint,green\",blue"
```

Reading it back gives the value unchanged, and `splitRespectingQuotes` turns it
into the three items again.

`rfc4180Quote` and `rfc4180CsvItemEncoder` are exported for this: they escape a
quote as `""` and wrap any item containing the separator, a quote or a newline.

### The two budgets

`fromData` walks whatever you hand it, and two shapes cost more than they look.
A structure that reaches itself is refused outright; one that is merely deeper
than `maxDepth` is refused as well, because the JSON encoder walks it
recursively and would otherwise run out of stack — as a `StackOverflowError`,
which nothing can usefully catch.

`maxEncodedNodes` covers the other direction. JSON has no sharing, so a value
two parents point at is written out under each. A node holding the same child
twice doubles per level: forty levels of that is eighty objects in memory and a
trillion in the output. Both limits raise an `ArgumentError` naming the key
path, and neither is reached by data that came from parsing JSON, which is
always a tree.

## Encoding

```dart
final text = doc.encode(
  options: const FlatEncodeOptions(
    quoteIfWhitespace: true,  // default: quote values with outer spaces
    escapeQuoted: true,       // default: escape \" and \\ on the way out
    alwaysQuote: false,       // force quotes on every non-null value
  ),
);
```

Encoding is **lossy by design**: comments and blank lines are not preserved, and
no BOM is written. A `null` value is written as `key =`, the explicit reset, and
the line stops there rather than carrying a trailing space. The last line is
always terminated.

Writing to a file is on the [platform I/O page](platform-io.md).

## Round-tripping

```text
structured data  ⇄  FlatDocument  ⇄  .conf file
```

Parsing what `encode` produced returns an equal document. The interesting part
is that this holds for the values that look like they should break it:

```dart
final doc = FlatDocument([
  FlatEntry('empty', ''),                 // not the same thing as a reset
  FlatEntry('reset', null),               // the line `reset =`
  FlatEntry('spaced', '  padded  '),
  FlatEntry('quoted', 'say "hi"'),
  FlatEntry('hash', '# not a comment'),
  FlatEntry('equals', 'a = b'),
  FlatEntry('backslash', r'C:\temp\x'),
]);

FlatDocument.parse(doc.encode()) == doc;  // true
```

Each of those is quoted, escaped or left alone according to what it contains:

```conf
empty = ""
reset =
spaced = "  padded  "
quoted = "say \"hi\""
hash = "# not a comment"
equals = "a = b"
backslash = C:\temp\x
```

Note `empty` against `reset`. A bare `key =` is a reset by definition, so the
empty string has to be written `""` or the two would be the same line. In 0.5.x
it was not, and an empty string came back as `null`.

The backslash is not escaped because the value is not quoted, and an unquoted
value is taken literally. This is why a Windows path survives without doubling.

The property is checked over generated documents in `test/round_trip_test.dart`
rather than over the handful of cases anyone thought to write down.
