# Parsing

How text becomes a `FlatDocument`, and what happens to a line the format cannot
read. For the rules themselves — what a key may contain, when a value is
quoted, what `key =` means — see [`SPEC.md`](../SPEC.md).

## Entry points

A source is text, lines, lines arriving over time, or bytes. There is one entry
point per shape and no second spelling for any of them.

```dart
import 'package:flatconfig/flatconfig.dart';

final fromText   = FlatDocument.parse('theme = dark\n');
final fromLines  = FlatDocument.parseLines(['theme = dark']);
final fromLineStream = await FlatDocument.parseLineStream(lines);  // Stream<String>
final fromBytes  = await FlatDocument.parseBytes(bytes);           // Stream<List<int>>
```

Reading files is [its own page](platform-io.md), because it needs `dart:io`.

For a document too large to hold at once, `streamEntries` yields entries as they
are read instead of building a document:

```dart
await for (final entry in FlatDocument.streamEntries(bytes)) {
  print('${entry.key} = ${entry.value}');
}
```

Byte sources are decoded before they are split, so a UTF-8 BOM is stripped and
`\n`, `\r\n` and `\r` all work, including when a chunk boundary falls in the
middle of one.

## Options

```dart
final doc = FlatDocument.parse(
  source,
  options: const FlatParseOptions(
    strict: false,                // the default: skip a malformed line
    commentPrefix: '#',           // '' disables comments entirely
    decodeEscapesInQuoted: true,  // the default: "a\\nb" holds a line break
  ),
);
```

| Option | Default | Effect |
|---|---|---|
| `strict` | `false` | throw on a malformed line instead of skipping it |
| `commentPrefix` | `'#'` | a line starting with this is ignored; `''` turns comments off |
| `decodeEscapesInQuoted` | `true` | decode `\"`, `\\` and friends inside quotes |
| `onIssue` | `null` | called for every problem found while parsing |

`commentPrefix` may not contain a line break, and `FlatParseOptions` rejects one
that does. This is checked rather than asserted, because a release build drops
assertions and the bad prefix would otherwise be used.

## Strict or lenient

The two modes disagree about one thing: what to do with a line that cannot be
read. Which lines those are is the same in both.

```dart
const broken = 'good = 1\nno equals here\n';

FlatDocument.parse(broken);                                   // 1 entry, no error
FlatDocument.parse(broken, options: FlatParseOptions(strict: true));  // throws
```

Strict mode throws a `FlatParseException` subclass: `MissingEqualsException`,
`EmptyKeyException`, `InvalidKeyException`, `UnterminatedQuoteException` or
`TrailingCharactersAfterQuoteException`. All five share that base class, so
catching "any parse problem" is one `on FlatParseException`.

## Reporting problems in lenient mode

Skipping a line does not have to mean skipping it silently. `onIssue` is called
for each one, with everything needed to point at it.

```dart
final doc = FlatDocument.parse(
  source,
  options: FlatParseOptions(
    onIssue: (issue) => stderr.writeln(
      '${issue.line}:${issue.column} ${issue.message}',
    ),
  ),
);
```

A `FlatIssue` carries the `kind`, the 1-based `line` and `column`, the `rawLine`
as it appeared, and sometimes a `detail`. The kinds are `missingEquals`,
`emptyKey`, `invalidKey`, `unterminatedQuote` and `trailingAfterQuote`. More may
be added, so match the ones you care about rather than switching exhaustively.

Strict mode throws for exactly the inputs `onIssue` reports, which is the point:
you can develop against `onIssue` and ship with `strict: true` without meeting
new failures in production.

Throwing from the handler aborts the parse. That is how to build a policy
between the two modes — intolerant of one kind, forgiving of the rest:

```dart
FlatParseOptions(onIssue: (issue) {
  if (issue.kind == FlatIssueKind.invalidKey) {
    throw FormatException(issue.message, issue.rawLine, issue.column);
  }
});
```

## Entries are valid by construction

Leniency stops at the parser. A `FlatEntry` built in code rejects anything the
format cannot write out and read back: an empty or padded key, a key containing
`=`, `#` or a quote, and a value spanning a line break.

```dart
FlatEntry('   ', 'oops');   // ArgumentError: key has leading whitespace
FlatEntry('a=b', 'v');      // ArgumentError: key must not contain '='
FlatEntry('k', 'a\nb');     // ArgumentError: value must not contain a line break
FlatEntry.reset('theme');   // fine: writes `theme =`
```

There is no lenient mode for this and no `strict:` flag to pass, because such an
entry cannot be built at all. A hand-edited file is input to be tolerated; a key
your own code assembled that the format cannot represent is a bug at the call
site, and it used to be a silent one — `FlatEntry('#x', 'v')` encoded to `#x = v`
and read back as zero entries.

This is also why `FlatEntry` is not `const`: a `const` constructor can only
check through `assert`, which release builds drop.
