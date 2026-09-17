// IO-only resolver: depends on dart:io and path.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'include_resolver_core.dart';
import 'path_utils.dart';

/// Resolves include targets against the filesystem.
///
/// A relative target is resolved against the directory of the unit holding the
/// directive; an absolute one is used as it is.
class FileIncludeResolver extends SyncIncludeResolver {
  /// Creates a resolver that decodes the files it reads with [encoding].
  ///
  /// The encoding belongs here rather than in `FlatStreamReadOptions`, because
  /// a resolver hands the traversal text: by the time a unit exists, the
  /// decoding has already happened, and only the resolver knew what to decode.
  /// Passing `readOptions` to a resolver-based entry point therefore cannot
  /// reach this.
  FileIncludeResolver({this.encoding = utf8});

  /// How the bytes of an included file are decoded.
  final Encoding encoding;

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    final baseDir = _baseDirectoryFor(request.fromId);

    final absPath = p.isAbsolute(request.target)
        ? request.target
        : p.normalize(p.join(baseDir.path, request.target));

    final file = File(absPath);

    // Read first. Asking whether the file exists and then reading it answers
    // for a moment that has passed by the time of the read, and reports every
    // failure — a permission denied, a directory in the way — as "no such
    // include", which an optional directive then skips in silence.
    final String content;
    try {
      content = file.readAsStringSync(encoding: encoding);
    } on PathNotFoundException {
      return null;
    }

    String canonical;
    try {
      canonical = resolveCanonicalPath(file);
    } catch (_) {
      canonical = file.absolute.path;
    }

    return IncludeUnit(id: normalizeCanonicalPath(canonical), content: content);
  }

  /// The directory a relative target is resolved against.
  ///
  /// Symbolic links are followed first, so that a unit reached through a link
  /// looks for its neighbours where it really lives. The `File` API resolves
  /// the including unit the same way, and the two produced different documents
  /// for a symlinked root while only this side skipped the step.
  ///
  /// [fromId] is not always a path — a caller may pass `mem:main.conf` or
  /// leave it out — so a name that does not resolve falls back to its lexical
  /// directory.
  Directory _baseDirectoryFor(String? fromId) {
    if (fromId == null || fromId.isEmpty) {
      return Directory.current;
    }

    final origin = File(fromId);

    try {
      return File(resolveCanonicalPath(origin)).parent;
    } catch (_) {
      return origin.parent;
    }
  }

  /// Resolves the canonical path for a file.
  ///
  /// This method is extracted to allow testing of error handling.
  /// Can be overridden in tests to simulate resolution failures.
  String resolveCanonicalPath(File file) => file.resolveSymbolicLinksSync();
}
