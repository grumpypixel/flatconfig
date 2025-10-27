# Changelog

## 0.5.0

Added:

- **`FlatDocument.hasAllKeys()`**  
  Checks whether all specified keys exist in the document.  
  - `ignoreNulls` (default: `true`) skips null-valued keys.  
  - `caseSensitive` (default: `true`) controls case matching.  

- **`FlatDocument.slice(prefix)`**  
  Extracts a subdocument containing only keys that start with the given prefix.  
  Operates on the resolved/latest view (unique keys; last value wins) and preserves key order.  

- **`FlatDocument.stripPrefix(prefix)`**  
  Returns a new document with all keys that start with the given prefix —  
  but removes the prefix from each key.  
  Ideal for working with grouped or sectioned configurations.  

## 0.4.0

Added:

- **In-memory include support** via the new resolver system:
  - `MemoryIncludeResolver` – define virtual configuration sources in memory (maps, generated strings, or tests).
  - `CompositeIncludeResolver` – combine multiple resolvers (e.g., files + memory) with *first-hit-wins* lookup order.
  - `FlatConfigResolverIncludes.parseStringWithIncludes()` – parse configuration text using any custom resolver.
- **Web/WASM compatibility:**
  - `FileIncludeResolver` is now an I/O-only implementation.
  - A lightweight `FileIncludeResolver` stub is automatically used on Web/WASM (always returns `null`).

Behavior:

- Matches the **Ghostty include semantics**:
  - Includes are processed at the end of the current unit (depth-first).
  - Later includes override earlier includes.
  - Entries after the first include cannot override keys defined in includes.
  - Optional includes prefixed with `?` are silently ignored if missing.
  - Cycle detection is performed via canonical `IncludeUnit.id`.

Improved:

- Expanded README:
  - Detailed “Include Semantics” and new “In-Memory and Hybrid Includes” sections.
  - Clarified **non-blocking reset** behavior (`key =` clears but doesn’t block later assignments).
  - Added examples for resolver composition and hybrid (file + memory) setups.

Notes:

- The resolver system shares the same merge, caching, and validation rules as file-based includes.
- Fully compatible with `FlatDocument`, `FlatEntry`, and all accessors.
- Backwards-compatible with existing file-based parsing APIs.

## 0.3.1

Improved:

- Polished README section for accessors (`get*`, `require*`, ranges, and quote awareness)
- Added concise "Accessors – At a Glance" overview
- Unified comment style and clarified boolean handling and range validation
- Minor formatting and consistency improvements across examples

Fixed:

- Corrected README description of include semantics:
  - Includes are merged **depth-first at the insertion point**; **later entries override earlier ones** (“later wins”).
  - An **unquoted empty value** (`key =`) is an **explicit reset** and **does not block** later assignments (**non-blocking by default**).
  - Optional includes via `config-file = ?file.conf` now explicitly documented as “missing files are ignored”.
- Added an example to demonstrate non-blocking resets and later overrides.

## 0.3.0

Added:

- Deep flattening via `FlatConfig.fromMapData()`.
- `FlatMapDataOptions` for list mode, CSV encoding, null handling, key escaping.
- RFC-4180 CSV utilities (`rfc4180Quote`, `rfc4180CsvItemEncoder`).
- `keyEscaper` for safe nested key handling.
- New tests: full coverage for map flattening, list modes, and CSV quoting.

Improved:

- Documentation and README examples for `fromMapData` and document factories.
- Barrel exports (`flatconfig.dart`) now include all public constructors.
- Internal structure cleanup and error context clarity.

Fixed:

- Proper key escaping on root keys in `fromMapData`.
- Accurate multi-value list flattening order.

## 0.2.0

Added:

- Generic & context-aware accessors:
  - `getAs<T>(key, converter)` – lenient “try” variant; returns `null` on missing/empty/invalid.
  - `getAsOr<T>(key, converter, default)` – lenient with fallback.
  - `requireAs<T>(key, converter)` – strict; throws `FormatException` with context.
  - `getAsWith<T>(key, (raw, key, doc) => T?)` – advanced, document-aware converter.
  - `requireAsWith<T>(...)` – strict variant for advanced converters.
  - `getAllAs<T>(key, converter)` – lazy, lenient conversion for duplicate keys.
  - `requireAllAs<T>(key, converter)` – strict conversion for all values.
- README: New **Custom Converters** section with examples.
- README: **Comparison to INI/TOML** and **Design Philosophy** sections.

Improved:

- Consistent, idiomatic error semantics:
  - Lenient `get*` accessors never throw; strict `require*` accessors throw with `.explain(key, got, cause)` context.

Notes:

- No breaking changes. Web/WASM-safe core remains unchanged; I/O helpers are still VM-only.

## 0.1.4

Added:

- **Web/WASM Stubs:** Added `includes_stub.dart` and `io_stub.dart` to safely
  throw `UnsupportedError` on non-IO platforms. The package now loads cleanly
  in Flutter Web / WASM projects (core parsing remains available).

Changed:

- **Barrel Exports:** Simplified conditional exports — the full units for
  `io.dart` and `includes.dart` are exported so that all extensions are
  visible on IO platforms.
- **README & Example:** Updated to use the recommended path-based helpers:
  `parseFlatFile`, `parseFlatFileSync`, `parseFileWithIncludes`,
  `writeFlat`, `writeFlatSync` (no more `src/` imports).
  File-based extensions remain available as ergonomic sugar.

Fixed:

- Pub.dev analysis warning: Missing `lints` dependency in `example/` package.
- Web/WASM analysis: no longer fails due to missing `dart:io` references.

Notes:

- This release is **non-breaking** (`0.1.x` → `0.1.4`).

## 0.1.3

Added:

- Added full support for *recursive* `config-file` *includes* (Ghostty-compatible).
  - Supports optional includes (`?path`), nested includes, relative paths, and cycle detection.
  - Defensive maximum include depth (`maxIncludeDepth`, default 64).
  - Async/sync I/O via `File.parseWithIncludes()` and `parseFileWithIncludes()`.
- Introduced example and documentation for *null-reset semantics* (`key = → null`, blocks later assignments).
- Clarified behavior for *one include per line* — comma-separated paths are treated as a single literal.
- Improved README with clear *include semantics*, usage examples, and quote-awareness notes (`getMap()` vs `getDocument()`).

Improved:

- Internal include handling now normalizes paths and detects circular dependencies more robustly.
- Minor parser cleanups and docstring refinements for consistency.

## 0.1.2

Documentation & metadata improvements:

- Updated dependency constraints and topics for pub.dev
- Updated README with slightly clearer description

## 0.1.1

Added:

- `FlatEntry.validated` factory for safe key creation
- Strict factories (`fromMap`, `fromEntries`, `merge`, `single`) with `strict` toggle
- Updated README with validation and factory examples

Improved:

- Internal key validation logic
- Documentation clarity and formatting

## 0.1.0

🎉 Initial public release.
