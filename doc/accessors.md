# Accessors

Every value in a document is a `String?`. Accessors turn one into the type you
actually want, and there is exactly one rule for how they are named.

## Three shapes, no exceptions

| Shape | Missing, reset or unparseable | Use when |
|---|---|---|
| `getX(key)` | returns `null` | the value is genuinely optional |
| `getXOr(key, fallback)` | returns `fallback` | you have a sensible default |
| `requireX(key)` | throws `FormatException` | a missing value is a startup error |

That is the whole catalog rule. If you know the type, you know the three method
names, and there is no fourth shape hiding somewhere for one type only.

## The core five

```dart
final name     = doc.getString('name');
final port     = doc.getIntOr('port', 8080);
final gamma    = doc.requireDouble('gamma');
final debug    = doc.getBoolOr('debug', false);
final features = doc.getList('features');   // "a, b , c" → ['a', 'b', 'c']
```

A few things worth knowing about them:

- **Missing and reset both read as `null`.** Use
  [`lookup()`](document-model.md#three-states-not-two) when the difference
  matters. To store an empty string rather than a reset, write `key = ""`.
- **Booleans** accept `true/false`, `on/off`, `yes/no` and `1/0`, case-insensitive.
- **Doubles** reject `NaN` and the infinities. Every comparison with `NaN` is
  false, so it passes any range check you write afterwards — which makes it
  worse than a plain parse failure.
- **Lists** trim items and drop empties by default. Splitting respects quotes,
  so `a,"b,c",d` is three items and the quotes come off the middle one; that is
  also why the separator has to be a single character. An item quoted as `""`
  is kept, because quoting is how the format says "on purpose".

## Repeated keys

`allAs` converts every value recorded for a key, in file order.

```dart
// hosts = alpha
// hosts = beta
final hosts = doc.allAs('hosts', parseHost);   // [alpha, beta]
final none  = doc.allAs('absent', parseHost);  // null, not []
```

The `null` matters: an empty list is a real answer, because a key present only
as a reset legitimately carries no values. Returning `[]` for both would merge
"never mentioned" into "mentioned and cleared".

One unconvertible value throws rather than being dropped, so a typo in a list
cannot silently shorten it.

## Anything else is a converter

`getAs` extends the same three shapes to any type you can write a function for.

```dart
final color   = doc.getAs('color', parseArgb);          // null when invalid
final retries = doc.getAsOr('retries', int.parse, 3);
final timeout = doc.requireAs('timeout', Duration.parse);  // throws, naming the key
```

A converter signals rejection by throwing. An `Exception` means the
configuration is wrong and is reported that way; an `Error` propagates
untouched, because a `TypeError` or `ArgumentError` says the *converter* is
wrong, and catching it would blame the user's file for your bug.

`trim` (default `true`) and `ignoreEmpty` (default `true`) control what reaches
the converter:

```dart
final title = doc.getAs('title', (s) => s.toUpperCase(), trim: false);
```

Colours, byte sizes, percentages, ratios and `host:port` pairs used to ship as
accessors. Each encoded a notation decision belonging to an application rather
than to the format, and each is a few lines here:

```dart
final size  = doc.getAs('cache', parseByteSize);   // '2MB' → 2000000
final ratio = doc.getAs('video', (v) {
  final parts = v.split(':');
  return double.parse(parts[0]) / double.parse(parts[1]);  // '16:9' → 1.777…
});
```

Range checks are the same idea — a validating converter, or `clamp()` on the
result:

```dart
final retries = doc.getAs('retries', (v) {
  final n = int.parse(v);
  if (n < 0 || n > 10) throw FormatException('out of range', v);
  return n;
});
```

If your converter needs to split an inline list the way the parser would,
`splitRespectingQuotes` and `indexOfUnquoted` are exported for exactly that.
[`SPEC.md`](../SPEC.md) §5 pins what they do.

## The optional accessors

Dates, durations, URIs, JSON and enums are common in configuration files but are
not part of the format, so they live in their own library. Same three shapes.

```dart
import 'package:flatconfig/flatconfig_accessors.dart';

final start   = doc.getDateTime('start_at');                 // ISO-8601
final timeout = doc.getDurationOr('timeout', const Duration(seconds: 30));
final api     = doc.requireUri('endpoint');
final payload = doc.getJson('payload');
final mode    = doc.getEnum('mode', {'prod': 1, 'dev': 2});  // case-insensitive
```

`getDuration` accepts a number with an optional `ms`, `s`, `m`, `h` or `d`
suffix and defaults to milliseconds. Fractions round to whole milliseconds, so
`1.5s` is 1500 ms.

The import is optional on purpose: a program that reads strings and numbers does
not carry a date parser it never calls.

See `example/accessors.dart` for worked converters.
