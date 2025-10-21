// Web/WASM stub for the IO-only FileIncludeResolver.
import 'include_resolver_core.dart';

/// Stub implementation used on web/wasm.
/// Always returns `null` since file system access is not available.
class FileIncludeResolver implements IncludeResolver {
  /// Creates a new file resolver.
  FileIncludeResolver();

  @override
  IncludeUnit? resolve(String target, {String? fromId}) => null;
}
