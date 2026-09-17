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
/// No platform settles this on its own: an APFS volume can be mounted either
/// way, a removable exFAT one on Linux is insensitive, and Windows supports
/// per-directory case sensitivity. Assuming macOS is insensitive, as this used
/// to, collapses `Foo.conf` and `foo.conf` on the volumes that are not.
///
/// A probe that cannot decide falls back to what the platform usually does,
/// which is the answer that was wrong least often before any probing existed.
class FilesystemCaseFolding implements PathCaseFolding {
  final _byDirectory = <String, bool>{};

  @override
  bool isCaseInsensitive(String path) {
    final directory = p.dirname(path);
    final cached = _byDirectory[directory];
    if (cached != null) {
      return cached;
    }

    final probed = _probe(path, directory);
    if (probed == null) {
      // Inconclusive for this file, but another file in the same directory may
      // still answer it, so nothing is cached.
      return _platformDefault;
    }

    _byDirectory[directory] = probed;

    return probed;
  }

  /// What to answer where the filesystem will not say.
  static bool get _platformDefault => Platform.isWindows;

  /// Whether [directory] is case-insensitive, or `null` if [path] cannot tell.
  static bool? _probe(String path, String directory) {
    final name = p.basename(path);
    final flipped = name.toUpperCase() == name
        ? name.toLowerCase()
        : name.toUpperCase();

    // A name without letters — `123.conf` — has no other spelling to try.
    if (flipped == name) {
      return null;
    }

    final other = p.join(directory, flipped);

    try {
      if (!File(path).existsSync()) {
        return null;
      }

      // The other spelling does not resolve, so the filesystem keeps the two
      // apart.
      if (!File(other).existsSync()) {
        return false;
      }

      // Both spellings resolve. Whether that is one file or two is a question
      // for the filesystem: identicalSync compares device and inode rather
      // than inferring it from metadata, which two distinct files routinely
      // share — copies written in the same second, or files of equal length.
      return FileSystemEntity.identicalSync(path, other);
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
