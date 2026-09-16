// Shared path utilities for cross-platform path handling.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Whether the filesystem holding a path treats `A` and `a` as one name.
///
/// Include identity hangs on the answer. Folding two distinct files into one
/// canonical id serves the wrong content and invents cycles; failing to fold a
/// file reached under two spellings merely loads it twice. The first mistake is
/// the one worth avoiding, so every implementation here answers
/// "case-sensitive" when it cannot tell.
abstract interface class PathCaseFolding {
  /// Whether [path] lives on a case-insensitive filesystem.
  bool isCaseInsensitive(String path);
}

/// A fixed answer, for tests and for callers who know their filesystem.
class FixedCaseFolding implements PathCaseFolding {
  /// Creates a strategy that answers [answer] for every path.
  const FixedCaseFolding(this.answer);

  /// The answer given to every query.
  final bool answer;

  @override
  bool isCaseInsensitive(String path) => answer;
}

/// Answers by asking the filesystem, caching one answer per directory.
///
/// Windows is answered without a probe. Elsewhere the platform does not settle
/// it: an APFS volume can be mounted either way, and so can a removable exFAT
/// one on Linux. Assuming macOS is case-insensitive, as this used to, collapses
/// `Foo.conf` and `foo.conf` on the volumes that are not.
class FilesystemCaseFolding implements PathCaseFolding {
  final _byDirectory = <String, bool>{};

  @override
  bool isCaseInsensitive(String path) {
    if (Platform.isWindows) {
      return true;
    }

    final directory = p.dirname(path);
    final cached = _byDirectory[directory];
    if (cached != null) {
      return cached;
    }

    final probed = _probe(path, directory);
    if (probed == null) {
      // Inconclusive for this file, but another file in the same directory may
      // still answer it, so nothing is cached.
      return false;
    }

    _byDirectory[directory] = probed;

    return probed;
  }

  /// Whether [directory] is case-insensitive, or `null` if [path] cannot tell.
  static bool? _probe(String path, String directory) {
    final name = p.basename(path);
    final flipped = name.toUpperCase() == name
        ? name.toLowerCase()
        : name.toUpperCase();

    if (flipped == name) {
      return null;
    }

    try {
      final original = File(path).statSync();
      if (original.type == FileSystemEntityType.notFound) {
        return null;
      }

      final other = File(p.join(directory, flipped)).statSync();
      if (other.type == FileSystemEntityType.notFound) {
        return false;
      }

      // A case-sensitive volume can genuinely hold both spellings as separate
      // files. Matching size and timestamp says this is one file seen twice.
      return other.size == original.size && other.modified == original.modified;
    } on FileSystemException {
      return null;
    }
  }
}

/// The strategy used when a caller does not supply one.
final PathCaseFolding defaultPathCaseFolding = FilesystemCaseFolding();

/// Normalizes a canonical path so that one file yields one identity.
///
/// The path is lowercased only where [folding] reports that case does not
/// distinguish files, and returned unchanged otherwise.
String normalizeCanonicalPath(String path, {PathCaseFolding? folding}) {
  final strategy = folding ?? defaultPathCaseFolding;

  return strategy.isCaseInsensitive(path) ? path.toLowerCase() : path;
}
