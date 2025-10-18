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
	just coverage-full
	just coverage-html
	open coverage/html/index.html

# Generate coverage (lcov)
coverage:
	#!/usr/bin/env bash
	set -euo pipefail

	ROOT_DIR="$(pwd)"
	OUT_DIR="$ROOT_DIR/coverage"
	LCOV_FILE="$OUT_DIR/lcov.info"

	mkdir -p "$OUT_DIR"

	echo "Running tests with coverage..."
	dart run test --coverage="$OUT_DIR"

	echo "Converting coverage to lcov..."
	dart run coverage:format_coverage \
	  --packages="$ROOT_DIR/.dart_tool/package_config.json" \
	  --report-on="$ROOT_DIR/lib" \
	  --lcov \
	  --in="$OUT_DIR" \
	  --out="$LCOV_FILE"

	echo "Wrote $LCOV_FILE"

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

# Generate full coverage incl. untested files (requires: dart pub global activate full_coverage)
coverage-full:
	#!/usr/bin/env bash
	set -euo pipefail

	ROOT_DIR="$(pwd)"
	OUT_DIR="$ROOT_DIR/coverage"
	LCOV_FILE="$OUT_DIR/lcov.info"

	mkdir -p "$OUT_DIR"

	# Include files with zero coverage via full_coverage
	dart pub global run full_coverage --ignore '*}.dart'

	# Run tests with VM coverage
	dart run test --coverage="$OUT_DIR"

	# Convert to lcov; -c for absolute paths and proper function names
	dart pub global run coverage:format_coverage --lcov --in="$OUT_DIR" --out="$LCOV_FILE" -c --report-on="$ROOT_DIR/lib"

	# Clean transient coverage artifacts
	rm -rf "$OUT_DIR/test" || true
	rm -f "$OUT_DIR/coverage.json" || true

	echo "Wrote $LCOV_FILE"

# Run micro-benchmark (optional arg: iterations)
bench ITERATIONS="1000" ENTRIES="2000":
	#!/usr/bin/env bash
	set -euo pipefail

	dart run tool/bench.dart {{ITERATIONS}} {{ENTRIES}}

# Run examples
examples:
	dart run example/basic.dart
	dart run example/accessors.dart
	dart run example/streams.dart
	dart run example/io.dart
	dart run example/includes.dart

# Publish dry run
publish-dry-run:
	dart test
	dart format .
	dart analyze
	dart pub publish --dry-run
