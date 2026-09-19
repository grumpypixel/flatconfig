#!/usr/bin/env bash
#
# Mutation-test every library file, one file per run, and remember which ones
# are done.
#
# A single run over all of lib/ takes hours, and losing it to a closed terminal
# or a sleeping machine means losing all of it — twice now. Worse, an
# interrupted run leaves the file it was mutating rewritten on disk, so the
# next thing to touch the repository sees corrupted source. One run per file
# bounds both: a loss costs one file, and the next invocation resumes.
#
# Files are ordered smallest first so findings arrive early, with the three
# large ones last.
#
# Usage: tool/mutation/sweep.sh [file...]
#
# Without arguments it sweeps every file under lib/src. Delete a file's
# directory under coverage/mutation to have it measured again.

set -uo pipefail

readonly RULES='tool/mutation/rules.xml'
readonly COVERAGE='coverage/lcov.info'
readonly OUT_ROOT='coverage/mutation'
readonly LOG="$OUT_ROOT/sweep.log"

if [ ! -f "$COVERAGE" ]; then
  echo "Missing $COVERAGE. Run: just coverage" >&2
  exit 1
fi

# An interrupted predecessor leaves a mutated file behind, and every result
# after that is about source nobody wrote. Refuse to start on one.
if ! dart analyze --fatal-warnings >/dev/null 2>&1; then
  echo 'lib/ does not analyze cleanly. A previous run may have left a' >&2
  echo 'mutated file behind; check `jj diff lib/` before sweeping.' >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=(
    lib/src/io.dart
    lib/src/exceptions.dart
    lib/src/constants.dart
    lib/src/include_resolver_io.dart
    lib/src/issue.dart
    lib/src/include_resolver_core.dart
    lib/src/include_assembly.dart
    lib/src/parse_with_resolver.dart
    lib/src/optional_accessors.dart
    lib/src/parser.dart
    lib/src/from_map_data.dart
    lib/src/options.dart
    lib/src/document.dart
  )
fi

mkdir -p "$OUT_ROOT"

# A run rewrites the file it is mutating and restores it when it finishes.
# Interrupted, it does not, and the mutated source is then what the next test
# run, analyzer or commit sees. This puts the file back on the way out.
#
# Safe because a sweep is the only thing touching lib/ while it runs: there is
# no legitimate edit here to lose. It cannot help against SIGKILL, so the guard
# above stays.
current=''
restore_current() {
  if [ -n "$current" ]; then
    echo "interrupted during $current; restoring it" >&2
    jj restore --from @- "$current" >/dev/null 2>&1 ||
      git checkout -- "$current" >/dev/null 2>&1
  fi
}
trap restore_current EXIT INT TERM HUP

for file in "${files[@]}"; do
  name="$(basename "$file" .dart)"
  out="$OUT_ROOT/$name"

  if [ -f "$out/.done" ]; then
    echo "skip   $file (already measured)"
    continue
  fi

  echo "sweep  $file"
  rm -rf "$out"
  current="$file"

  mutation_test \
    --builtin \
    --rules "$RULES" \
    --coverage "$COVERAGE" \
    --output "$out" \
    --format all \
    "$file" >>"$LOG" 2>&1

  # The exit code reports the quality gate, not whether the run happened, and
  # a discovery sweep is expected to miss the gate on most files. What says the
  # run finished is the report.
  if [ ! -f "$out/mutation-test-report.md" ]; then
    echo "failed $file. See $LOG" >&2
    exit 1
  fi

  current=''
  touch "$out/.done"
done

echo "Reports: $OUT_ROOT/<file>/mutation-test-report.md"
