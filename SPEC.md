# flatconfig format — version 1

**Status:** normative target for flatconfig 1.0.0.
**Scope:** the on-disk/in-memory text format only. Dart API shape is out of scope
(see `ROADMAP_1.0.md`).

This document defines exactly one answer for every case the 0.5.0 parser leaves
ambiguous. Where the current implementation disagrees, the disagreement is
recorded in [Appendix A](#appendix-a--deviations-in-050) rather than silently
adopted — each row there is a Phase 1 work item.

"MUST", "MUST NOT" and "MAY" carry their usual normative force.

---

## 1. Character model

A flatconfig document is a sequence of Unicode scalar values. Byte input MUST be
decoded before parsing; UTF-8 is the default.

A single U+FEFF (BOM) at the very start of the input MUST be discarded. A U+FEFF
anywhere else is an ordinary character. Encoders MUST NOT emit a BOM.

## 2. Line model

Input is split into lines on `\n`, `\r\n`, or `\r`. All three MUST be accepted
and are equivalent. Encoders write `\n` by default.

Each line is classified after **left-trimming** whitespace (space, tab, `\r`,
`\n`):

| Line | Classification |
|---|---|
| empty, or whitespace only | ignored |
| begins with the comment prefix | comment, ignored |
| otherwise | an entry line, parsed per §3–§5 |

There are **no inline comments.** A comment prefix appearing after the separator
is an ordinary part of the value. `a = b # c` yields the value `b # c`.

The comment prefix is configurable. It MUST be non-empty and MUST NOT contain
`\n` or `\r`. It defaults to `#`.

## 3. Keys

The key is the text before the first `=` on the line, with trailing whitespace
removed. Leading whitespace was already removed in §2.

A key MUST satisfy all of:

1. non-empty
2. contains no `=`
3. contains no `"` <!-- reserved so a future quoted-key form stays possible -->
4. contains no `\n` and no `\r`
5. does not begin or end with whitespace
6. does not begin with `#`

Rules 1–4 make the key unambiguous on the wire. Rule 5 exists because leading and
trailing whitespace cannot survive a round trip (§2 trims it). Rule 6 keeps a key
from being re-read as a comment.

Keys are validated **at construction**, not only at parse time, so an invalid key
can never reach the encoder.

> **Configurable prefixes.** Rule 6 names `#` literally, so key validity does not
> depend on parse options. If the comment prefix is configured to something other
> than `#`, the encoder MUST throw when a key begins with that prefix. This keeps
> the common case free and the uncommon case honest.

Keys are compared byte-for-byte. Matching is case-sensitive; no normalization,
trimming, or case folding is applied.

Keys are **not** quotable. A leading `"` is an ordinary character, subject to
rule 3 — that is, it is rejected.

## 4. Separator

The separator is `=`. It is **not** configurable.

The separator is the **first** `=` on the line. Because keys may not contain `=`
(§3 rule 2), the first occurrence is always the intended one, and the scan need
not be quote-aware.

A line containing no `=` is malformed: ignored in lax mode, an error in strict
mode (§9).

## 5. Values

The value is everything after the separator, with leading and trailing
whitespace removed. It is then classified:

| Trimmed token | Value |
|---|---|
| empty | `null` — an explicit reset (§6) |
| begins with `"` | quoted, per §5.1 |
| otherwise | the trimmed token, literally |

An unquoted value is taken verbatim. Backslashes, `#`, `=` and inner whitespace
are ordinary characters; no escape processing occurs outside quotes.

### 5.1 Quoted values

A quoted value opens with `"` and closes at the **first** subsequent unescaped
`"`. A `"` is escaped when preceded by an odd number of `\`.

After the closing quote, only whitespace may follow.

The value is the text between the quotes, with escapes decoded per §5.2. Quoted
values preserve inner whitespace, `=`, and the comment prefix exactly.

A token that opens with `"` but does not form a well-formed quoted value — no
closing quote, or non-whitespace after it — is malformed:

- **lax:** the entire trimmed token is used as a literal, unquoted value.
- **strict:** an error (§9).

> **First closer, not last.** `a = "one" junk "two"` is malformed. Closing at the
> last quote would make it a silently accepted value of `one" junk "two`, which
> is why §5.1 fixes the closer at the first one.

### 5.2 Escapes

Inside a quoted value, exactly two escapes are recognized:

| Sequence | Decodes to |
|---|---|
| `\"` | `"` |
| `\\` | `\` |

Every other backslash is a literal backslash and is preserved. `"C:\temp\x"`
therefore yields `C:\temp\x` unchanged — there is no `\t` escape, by design, so
Windows paths and regexes survive without doubling.

Decoding is **on by default**, matching the encoder, which escapes by default
(§7). The two MUST agree; a document written by a conforming encoder and read by
a conforming parser with default options MUST round-trip.

## 6. The three states of a key

A key is in exactly one of three states, and the format distinguishes all three:

| State | Text | Parsed value |
|---|---|---|
| absent | no line for the key | — |
| reset | `key =` | `null` |
| empty string | `key = ""` | `""` |

`null` means "explicitly cleared", not "empty text". This matters for includes
(§8), where a later file resets a key set by an earlier one.

An API returning a bare nullable string cannot distinguish absent from reset;
that is an API concern, addressed by `FlatLookup` in the roadmap, not a format
concern.

## 7. Serialization

Encoding MUST be the exact inverse of parsing: for every valid document `d`,
`parse(encode(d)) == d`, including entry order, duplicates, and the distinction
between `null` and `""`.

Each entry is written as `key`, space, `=`, space, value, then the line
terminator. Entries are written in order; duplicates are preserved.

A value is quoted when, and only when, leaving it bare would change how it
parses back:

| Value | Quoted | Why |
|---|---|---|
| `null` | no — the line is `key = ` | that *is* the wire form of a reset |
| `""` | yes | a bare `key = ` would read back as `null` |
| leading or trailing whitespace | yes | §5 trims the bare form |
| contains `"` | yes | §5 would take a leading quote as an opener |
| contains `=` | yes | defensive; the first `=` is already the separator |
| begins with the comment prefix | yes | §2 would take the line for a comment |
| anything else | no | the bare form already round-trips |

Whenever a value is quoted, `\` MUST be written as `\\` and `"` as `\"`.
Escaping is **on by default**: producing output that a conforming parser would
misread MUST NOT be the default behaviour. A trailing backslash makes this
load-bearing rather than cosmetic — unescaped, `"C:\"` has no closer at all,
because the closing quote reads as escaped.

Backslashes in an *unquoted* value need no escaping, since §5 applies no escape
processing outside quotes.

Values containing `\n` or `\r` cannot be represented; they are rejected at
construction (§3 for keys, here for values) and therefore cannot reach the
encoder.

The output of a non-empty document always ends with the line terminator. An
empty document encodes to the empty string. There is consequently no
"ensure trailing newline" option on `encode` — it would have nothing to do.

## 8. Duplicate keys and includes

A document is an **ordered list of entries**, not a map. Duplicate keys are
preserved in both order and count.

The *resolved view* of a document maps each key to the value of its **last**
entry. Last write wins, including when the last entry is a reset:

```
a = 1
a = 2
a =        # resolved: a -> null
```

Includes are directives, not keys. A line whose key equals the include key
(default `config-file`) is replaced, in place, by the entries of the referenced
document, processed depth-first. A target prefixed with `?` is optional and
silently skipped when it cannot be resolved.

Because inclusion is textual and in place, include precedence falls out of the
last-write-wins rule in this section — it needs no separate mechanism.

A document MUST NOT include itself, directly or transitively. Cycles are an
error, as is exceeding the configured depth limit.

## 9. Errors

Strict mode turns every malformed construct into an error. Lax mode applies the
stated recovery and continues. Both modes MUST report the same set of conditions;
they differ only in whether reporting is fatal.

| Condition | Lax recovery |
|---|---|
| line has no `=` | line ignored |
| key is empty | line ignored |
| key violates §3 | line ignored |
| quoted value has no closing quote | token used literally |
| non-whitespace after closing quote | token used literally |
| include cycle | always an error |
| include depth exceeded | always an error |

Every report carries the 1-based line number, a 1-based column, and the raw line.

---

## Appendix A — deviations in 0.5.0

Measured against 0.5.0, not inferred from the source. Each row is a Phase 1 task.

### Fixed

| § | Rule | What 0.5.0 did |
|---|---|---|
| 5.1 | first closer wins | Searched for the **last** unescaped quote, so `a = "one" junk "two"` was accepted even in strict mode, yielding `one" junk "two`. |
| 5.2 | decoding on by default | `decodeEscapesInQuoted` defaulted to `false`. |
| 6 | `""` survives a round trip | Encoded to `key = `, which re-parsed as `null`. |
| 7 | escaping on by default | `escapeQuoted` defaulted to `false`. |

| 5 | backslashes preserved | `splitRespectingQuotes` consumed every backslash as an escape marker without copying it, so `getDocument` turned `win=C:\temp\x` into `win → C:tempx`. It now only locates boundaries; `parseValue` owns decoding. `indexOfUnquoted` carried a second copy of the same rule and now shares one helper. |
| 3 | keys validated at construction | Only emptiness was checked, and only while parsing. `FlatEntry('#x', 'v')` encoded to `#x = v` and re-parsed to **zero entries**; `FlatEntry(' a ', 'v')` lost its padding; `"a b" = v` kept its quotes in the key. |

These four had to move together. Unescaped output was only readable back
*because* the parser closed at the last quote; switching §5.1 on its own would
have broken inputs that previously worked. The round-trip property test and
`test/spec_conformance_test.dart` pin the result.

`FlatEntry` stays a `const` pair, because a `const` constructor may only assert
compile-time constant expressions and `key.contains('=')` is not one. The check
therefore sits on every path that builds a `FlatDocument`, which is the only way
to reach the encoder. `strict: false` on the document factories now drops
invalid entries, as its documentation always claimed.

### Open

| § | Rule | 0.5.0 actually does | Severity |
|---|---|---|---|
| 7 | newlines rejected | `FlatEntry('a', 'x\ny')` is accepted and encodes to two physical lines; re-parsing yields `a` → `"x` | corrupts |
| 7 | no trailing-newline option | `ensureTrailingNewline` exists but is a no-op, since output already ends with `\n` | dead option |

Behaviour that already conforms, confirmed by probe: line-ending handling (`\n`,
`\r\n`, `\r`), BOM stripping, comment classification including custom prefixes,
absence of inline comments, `=` inside quoted values, duplicate-key ordering, and
last-write-wins resolution.
