// IO-only resolver: depends on dart:io and path.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'include_resolver_core.dart';
import 'path_utils.dart';

/// File-backed resolver that mirrors current path resolution.
class FileIncludeResolver implements IncludeResolver {
  /// Creates a new file resolver.
  FileIncludeResolver();

  @override
  IncludeUnit? resolve(String target, {String? fromId}) {
    final Directory baseDir = (fromId != null && fromId.isNotEmpty)
        ? File(fromId).parent
        : Directory.current;

    final absPath = p.isAbsolute(target)
        ? target
        : p.normalize(p.join(baseDir.path, target));

    final file = File(absPath);
    if (!file.existsSync()) {
      return null;
    }

    String canonical;
    try {
      canonical = resolveCanonicalPath(file);
    } catch (_) {
      canonical = file.absolute.path;
    }

    canonical = normalizeCanonicalPath(canonical);

    final content = file.readAsStringSync();

    return IncludeUnit(id: canonical, content: content);
  }

  /// Resolves the canonical path for a file.
  ///
  /// This method is extracted to allow testing of error handling.
  /// Can be overridden in tests to simulate resolution failures.
  String resolveCanonicalPath(File file) => file.resolveSymbolicLinksSync();
}
