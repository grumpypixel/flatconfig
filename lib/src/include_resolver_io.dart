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
///
/// Both halves are genuine: [resolve] reads and canonicalizes without blocking,
/// [resolveSync] does neither. Inheriting the asynchronous method from
/// [SyncIncludeResolver] would have made every include of an awaited parse a
/// blocking read, which is what an event loop notices.
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
  Future<IncludeUnit?> resolve(IncludeRequest request) async {
    final file = _target(request, await _asyncBase(request.fromId));

    // Read first. Asking whether the file exists and then reading it answers
    // for a moment that has passed by the time of the read, and reports every
    // failure — a permission denied, a directory in the way — as "no such
    // include", which an optional directive then skips in silence.
    final String content;
    try {
      content = await file.readAsString(encoding: encoding);
    } on PathNotFoundException {
      return null;
    }

    return IncludeUnit(id: await _asyncId(file), content: content);
  }

  @override
  IncludeUnit? resolveSync(IncludeRequest request) {
    final file = _target(request, _syncBase(request.fromId));

    final String content;
    try {
      content = file.readAsStringSync(encoding: encoding);
    } on PathNotFoundException {
      return null;
    }

    return IncludeUnit(id: _syncId(file), content: content);
  }

  /// The file [request] names, relative to [baseDir] unless it is absolute.
  File _target(IncludeRequest request, Directory baseDir) => File(
    p.isAbsolute(request.target)
        ? request.target
        : p.normalize(p.join(baseDir.path, request.target)),
  );

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
  Directory _syncBase(String? fromId) {
    if (fromId == null || fromId.isEmpty) {
      return Directory.current;
    }

    final origin = File(fromId);

    try {
      return File(resolveCanonicalPath(origin)).parent;
    } on FileSystemException {
      return origin.parent;
    }
  }

  /// The asynchronous counterpart to [_syncBase].
  Future<Directory> _asyncBase(String? fromId) async {
    if (fromId == null || fromId.isEmpty) {
      return Directory.current;
    }

    final origin = File(fromId);

    try {
      return File(await origin.resolveSymbolicLinks()).parent;
    } on FileSystemException {
      return origin.parent;
    }
  }

  /// The identity a unit is known by: its real path, case-folded where the
  /// filesystem folds case.
  String _syncId(File file) {
    try {
      return normalizeCanonicalPath(resolveCanonicalPath(file));
    } on FileSystemException {
      return normalizeCanonicalPath(file.absolute.path);
    }
  }

  /// The asynchronous counterpart to [_syncId].
  Future<String> _asyncId(File file) async {
    try {
      return normalizeCanonicalPath(await file.resolveSymbolicLinks());
    } on FileSystemException {
      return normalizeCanonicalPath(file.absolute.path);
    }
  }

  /// Resolves the canonical path for a file.
  ///
  /// This method is extracted to allow testing of error handling.
  /// Can be overridden in tests to simulate resolution failures.
  String resolveCanonicalPath(File file) => file.resolveSymbolicLinksSync();
}
