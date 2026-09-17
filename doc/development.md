# Working on flatconfig

The repository uses [`just`](https://github.com/casey/just) for the routine
commands. Everything it does is a plain `dart` invocation, so nothing here
depends on having it installed.

```sh
just test        # dart test
just analyze     # dart analyze .
just format      # dart format .
just doit        # pub get, fix, format, analyze with fatal infos, test
just examples    # run every example in example/
just bench       # micro-benchmark, optional iteration and entry counts
just coverage    # line coverage to coverage/lcov.info
```

Before describing a change as done, `dart analyze` and
`dart format --set-exit-if-changed` both have to be clean. Neither catches
duplicated logic, so that stays a review concern.

## What CI checks

Six jobs run on every push and pull request. They exist because each one has
caught something the others could not.

| Job | Checks |
|---|---|
| Test (Dart stable, Dart 3.8) | analyzer and the suite, on stable and on the declared SDK floor |
| Test without assertions | the same suite with assertions stripped, as a release build runs it |
| Format | `dart format --set-exit-if-changed`, for the package and the examples |
| Web and WASM | the three web-safe barrels compile to JavaScript and to WASM, and the browser-safe tests run in Chrome |
| Publish dry run | `dart pub publish --dry-run` |
| Flutter example | `flutter analyze` and `flutter test` in `example/flatconfig_flutter` |

The assertions-disabled run is not redundant. A guard written as `assert` does
nothing in a release build, and this package shipped exactly that bug: an empty
line terminator and a multi-character separator were rejected in development
and accepted in production. Those guards now throw, and this job is what keeps
them that way.

The web job compiles `tool/web_entrypoint.dart`, which touches each web-safe
library so tree shaking cannot quietly drop one and hide a `dart:io` import in
the part that was removed.

A test that needs `dart:io` carries `@TestOn('vm')`. Without it the browser job
fails, which is how the annotation gets remembered.

## Coverage

```sh
just coverage        # writes coverage/lcov.info
just coverage-html   # renders it, needs genhtml
```

Line coverage sits at 99.54%. Branch coverage is not collected: the SDK accepts
`--branch-coverage` and then emits no branch records, so the recipe leaves the
flag out rather than appearing to measure something it does not.

There is no generated `full_coverage` barrel any more. Since the package was
split into four libraries, every file under `lib/` is reachable from a real
test, so a file importing all of them would only pad the number.

## Tests worth knowing about

Most files test one thing and are named after it. Four are structural:

- `test/barrel_*_test.dart` import exactly one barrel each, so a type that
  appears in a public signature but is not exported fails here rather than in
  somebody's project.
- `test/round_trip_test.dart` checks `parse(encode(d)) == d` over generated
  documents, across encodings, line terminators and byte streams.
- `test/editing_algebra_test.dart` checks the laws the editing operations obey,
  also over generated documents.
- `test/regressions_test.dart` pins shipped defects that no other file covers,
  and asserts thrown errors rather than `assert`s, because one of those defects
  was a guard that existed only as an assertion.

The generators use a fixed seed, so a failure is reproducible.

## The format itself

[`SPEC.md`](../SPEC.md) is normative. Appendix A records where 0.5.0 deviated
from it and how each deviation was closed; nothing is open there any more, and
every entry is pinned by a test. A change to parsing or encoding belongs in the
spec first; if the two disagree, the spec is right and the code is the bug.

## Version control

The repository is a colocated `jj`/`git` checkout. Work happens through
[Jujutsu](https://jj-vcs.github.io/jj/): edit, then `jj commit -m "…"`. There is
no staging area, bookmarks do not advance on their own, and `main` (0.5.x) and
`v1` are separate lines on purpose. Commit messages follow Conventional Commits.

## House rules

Everything written to a file is in English — comments, dartdoc, identifiers,
commit messages, test names, error messages. Non-English test *data* is fine and
sometimes required; `'ünïcödé'` is a fixture, not prose.

A comment explains a constraint the code cannot state itself. It does not
restate the next line, and it does not record who changed what.
