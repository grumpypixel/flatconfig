// Shared path utilities for cross-platform path handling.

import 'dart:io';

/// Normalizes a canonical path for case-insensitive filesystems.
///
/// This function ensures that paths are normalized and converted to lowercase
/// on case-insensitive filesystems (Windows and macOS/APFS) to ensure
/// consistent canonical paths for cycle detection and caching.
///
/// On case-sensitive filesystems (Linux, etc.), the path is returned unchanged.
String normalizeCanonicalPath(String path) {
  if (Platform.isWindows || Platform.isMacOS) {
    return path.toLowerCase();
  }

  return path;
}
