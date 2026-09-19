# Default recipe
default: test

# Run tests
test:
	dart test

# Analyze code
analyze:
	dart analyze .

# Format code
format:
	dart format .

# Check for outdated dependencies
checkit:
	dart pub outdated --no-dev-dependencies --up-to-date --no-dependency-overrides

# Check code
doit:
	dart pub get
	dart fix --apply
	dart format .
	dart analyze --fatal-infos --fatal-warnings
	dart test

dothecoverage:
	dart pub global activate coverage
	just coverage
	just coverage-html
	open coverage/html/index.html

# Generate line coverage (lcov)
coverage:
	#!/usr/bin/env bash
	set -euo pipefail

	# Every file under lib/ is reachable from a real test since the package was
	# split into four barrels, so there is nothing for full_coverage to pad with.
	# --branch-coverage is deliberately absent: this SDK accepts it and then
	# emits no BRF records, so it would only look like it was measuring something.
	dart run coverage:test_with_coverage -- --reporter=failures-only

	echo "Wrote coverage/lcov.info"

# Generate HTML report from lcov (requires genhtml)
coverage-html:
	#!/usr/bin/env bash
	set -euo pipefail

	ROOT_DIR="$(pwd)"
	OUT_DIR="$ROOT_DIR/coverage"
	LCOV_FILE="$OUT_DIR/lcov.info"
	HTML_DIR="$OUT_DIR/html"

	if [ ! -f "$LCOV_FILE" ]; then
	  just coverage
	fi

	mkdir -p "$HTML_DIR"
	genhtml "$LCOV_FILE" -o "$HTML_DIR"
	echo "HTML report: $HTML_DIR/index.html"

# Run mutation tests (which lines does no assertion actually observe?)
mutants:
	#!/usr/bin/env bash
	set -euo pipefail

	dart pub global activate mutation_test

	# Without the coverage report, every line no test reaches becomes a
	# guaranteed survivor and buries the real findings.
	if [ ! -f coverage/lcov.info ]; then
	  just coverage
	fi

	# -b restores the builtin operators, which naming a rules file turns off.
	# The markdown report is the one to read: it lists the surviving mutants as
	# text, so finding them does not mean scraping the HTML.
	mutation_test \
	  --builtin \
	  --rules tool/mutation/rules.xml \
	  --coverage coverage/lcov.info \
	  --output coverage/mutation/curated \
	  --format all \
	  tool/mutation_test.xml

	echo "Report: coverage/mutation/curated/mutation-test-report.md"

# Run mutation tests over all of lib (hours; resumable, one file per run)
mutants-all:
	#!/usr/bin/env bash
	set -euo pipefail

	dart pub global activate mutation_test

	if [ ! -f coverage/lcov.info ]; then
	  just coverage
	fi

	tool/mutation/sweep.sh

# Run micro-benchmark (optional arg: iterations)
bench ITERATIONS="1000" ENTRIES="2000":
	#!/usr/bin/env bash
	set -euo pipefail

	dart run tool/bench.dart {{ITERATIONS}} {{ENTRIES}}

# Run examples
examples:
	dart run example/main.dart
	dart run example/accessors.dart
	dart run example/error_handling.dart
	dart run example/includes.dart
	dart run example/io.dart
	dart run example/streams.dart

# Publish dry run
publish-dry-run:
	dart test
	dart format .
	dart analyze
	dart pub publish --dry-run
