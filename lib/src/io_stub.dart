// Web/WASM stub for io.dart – no dart:io dependency!

import 'document.dart';
import 'options.dart';

Never _unsupported(String fn) =>
    throw UnsupportedError('$fn is not supported on this platform (web/wasm).');

// Placeholder so that the export identifier exists.
// (In the VM this is an extension name; here a dummy type is sufficient.)
/// Placeholder type mirroring the VM-only `FlatConfigIO` extension namespace.
class FlatConfigIO {}

/// Placeholder type mirroring the VM-only `FlatDocumentIO` extension namespace.
class FlatDocumentIO {}

/// Parses a flat config file from [path].
///
/// This stub always throws [UnsupportedError] on web/wasm because filesystem
/// access is unavailable in this platform environment.
Future<FlatDocument> parseFlatFile(
  String path, {
  FlatParseOptions options = const FlatParseOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
}) async =>
    _unsupported('parseFlatFile');

/// Synchronous variant of [parseFlatFile].
FlatDocument parseFlatFileSync(
  String path, {
  FlatParseOptions options = const FlatParseOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
}) =>
    _unsupported('parseFlatFileSync');

/// Parses a flat config file with include support from [path].
///
/// This stub always throws [UnsupportedError] on web/wasm because filesystem
/// access is unavailable in this platform environment.
Future<FlatDocument> parseFileWithIncludes(
  String path, {
  FlatParseOptions options = const FlatParseOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  Map<String, FlatDocument>? cache,
}) async =>
    _unsupported('parseFileWithIncludes');

/// Writes a FlatDocument to a file (async).
Future<void> writeFlat(
  String path,
  FlatDocument doc, {
  FlatEncodeOptions options = const FlatEncodeOptions(),
  FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
}) async =>
    _unsupported('writeFlat');

/// Writes a FlatDocument to a file (sync).
void writeFlatSync(
  String path,
  FlatDocument doc, {
  FlatEncodeOptions options = const FlatEncodeOptions(),
  FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
}) =>
    _unsupported('writeFlatSync');

/// Placeholder type mirroring the VM-only `FlatConfigIO` extension namespace.
///
/// Analyzer-friendly shims: provide extension members on Object so that
/// code like File('...').parseFlat() resolves at analysis time on web/wasm,
/// while still throwing UnsupportedError at runtime.
extension FlatConfigIOStub on Object {
  /// Parses a configuration file asynchronously.
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  Future<FlatDocument> parseFlat({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async =>
      _unsupported('File.parseFlat');

  /// Synchronous variant of [parseFlat].
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  FlatDocument parseFlatSync({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) =>
      _unsupported('File.parseFlatSync');

  /// Writes a FlatDocument to a file asynchronously.
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  Future<void> writeFlat(
    FlatDocument doc, {
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) async =>
      _unsupported('File.writeFlat');

  /// Writes a FlatDocument to a file synchronously.
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  void writeFlatSync(
    FlatDocument doc, {
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) =>
      _unsupported('File.writeFlatSync');
}
