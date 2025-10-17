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

/// Parses a flat config file with include support from [path].
///
/// This stub always throws [UnsupportedError] on web/wasm because filesystem
/// access is unavailable in this platform environment.
Future<FlatDocument> parseFileWithIncludes(
  String path, {
  FlatParseOptions options = const FlatParseOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
}) async =>
    _unsupported('parseFileWithIncludes');
