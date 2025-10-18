import 'document.dart';
import 'options.dart';
import 'parser.dart';

Never _unsupported(String fn) =>
    throw UnsupportedError('$fn is not supported on this platform (web/wasm).');

/// Mirror of the `FlatConfigIncludes` extension from includes.dart,
/// but without file access – all methods throw UnsupportedError.
/// (Signatures must match the IO counterpart exactly.)
extension FlatConfigIncludes on FlatConfig {
  /// Parses a configuration file with include support.
  ///
  /// This web/wasm stub mirrors the IO API but always throws
  /// [UnsupportedError] because filesystem access is unavailable.
  static Future<FlatDocument> parseWithIncludes(
    Object /* File */ file, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) async =>
      _unsupported('FlatConfigIncludes.parseWithIncludes');

  /// Synchronous variant of [parseWithIncludes].
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  static FlatDocument parseWithIncludesSync(
    Object /* File */ file, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) =>
      _unsupported('FlatConfigIncludes.parseWithIncludesSync');

  /// Parses a configuration file from a path with include support.
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  static Future<FlatDocument> parseWithIncludesFromPath(
    String path, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) async =>
      _unsupported('FlatConfigIncludes.parseWithIncludesFromPath');

  /// Synchronous variant of [parseWithIncludesFromPath].
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  static FlatDocument parseWithIncludesFromPathSync(
    String path, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) =>
      _unsupported('FlatConfigIncludes.parseWithIncludesFromPathSync');
}

/// In includes.dart `FileIncludes` is an extension on `File`.
/// On the web there is no `dart:io` – therefore we export a
/// placeholder type with the same name which, if referenced directly,
/// clearly signals that the feature is not available.
class FileIncludes {
  /// Creates a placeholder that mirrors the VM-only `FileIncludes` extension.
  ///
  /// The [baseDir] parameter is accepted to keep constructor parity with
  /// usages that may reference a base directory in VM code. It is unused here.
  FileIncludes(Object baseDir);
  // There are intentionally no methods here; on the web the extension method
  // `File.parseWithIncludes()` would not be usable anyway, because `File` is missing.
}

/// Analyzer-friendly stub to make File('...').parseWithIncludes() resolvable
/// on web/wasm; this mirrors the IO extension method name, but throws.
extension FileIncludesStub on Object {
  /// Parses a configuration file with include support.
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  Future<FlatDocument> parseWithIncludes({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) async =>
      _unsupported('File.parseWithIncludes');

  /// Synchronous variant of [parseWithIncludes].
  ///
  /// Always throws [UnsupportedError] on web/wasm.
  FlatDocument parseWithIncludesSync({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    Map<String, FlatDocument>? cache,
  }) =>
      _unsupported('File.parseWithIncludesSync');
}
