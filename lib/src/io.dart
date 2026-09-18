import 'dart:io';

import 'document.dart';
import 'exceptions.dart';
import 'include_resolver_io.dart';
import 'options.dart';
import 'parse_with_resolver.dart' as resolver;
import 'parser.dart';
import 'path_utils.dart';

/// Reading and writing flat configuration files.
///
/// This is the whole file API: a path becomes a [File], and a [File] parses or
/// is written to. There is no second spelling as a top-level function or as a
/// method on the document.
extension FlatConfigIO on File {
  /// Parses this file into a [FlatDocument].
  ///
  /// Include directives are left as ordinary entries; use [parseWithIncludes]
  /// to follow them.
  ///
  /// ```dart
  /// final doc = await File('config.flat').parseFlat();
  /// ```
  Future<FlatDocument> parseFlat({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async {
    final lines = openRead()
        .transform(readOptions.encoding.decoder)
        .transform(readOptions.lineSplitter);

    return parseStringStream(lines, options: options);
  }

  /// Parses this file into a [FlatDocument], reading it in one go.
  ///
  /// The synchronous counterpart to [parseFlat], which streams instead.
  FlatDocument parseFlatSync({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) => FlatDocument.parse(
    readAsStringSync(encoding: readOptions.encoding),
    options: options,
    lineSplitter: readOptions.lineSplitter,
  );

  /// Parses this file and follows every include it names.
  ///
  /// Relative paths resolve against this file's directory, a `?` prefix marks
  /// an include optional, cycles are detected, and
  /// [FlatIncludeOptions.mergePolicy] decides the resulting order.
  ///
  /// ```dart
  /// final doc = await File('main.conf').parseWithIncludes();
  /// ```
  ///
  /// Throws [CircularIncludeException] on a cycle,
  /// [MissingIncludeException] for a required include that is not there, and
  /// [MaxIncludeDepthExceededException] past
  /// [FlatIncludeOptions.maxIncludeDepth].
  Future<FlatDocument> parseWithIncludes({
    FlatParseOptions options = const FlatParseOptions(),
    FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async {
    // Before the read, so that a file that is not there cannot report itself
    // instead of the argument that was wrong.
    includeOptions.checkUsable();

    return resolver.parseWithIncludes(
      await _readRoot(() async => readAsString(encoding: readOptions.encoding)),
      resolver: FileIncludeResolver(encoding: readOptions.encoding),
      originId: await _rootIdAsync(),
      options: options,
      includeOptions: includeOptions,
      readOptions: readOptions,
    );
  }

  /// Parses this file and follows every include it names, synchronously.
  FlatDocument parseWithIncludesSync({
    FlatParseOptions options = const FlatParseOptions(),
    FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) {
    includeOptions.checkUsable();

    return resolver.parseWithIncludesSync(
      _readRootSync(() => readAsStringSync(encoding: readOptions.encoding)),
      resolver: FileIncludeResolver(encoding: readOptions.encoding),
      originId: _rootId(),
      options: options,
      includeOptions: includeOptions,
      readOptions: readOptions,
    );
  }

  /// The identity the traversal knows this file by.
  ///
  /// The same one [FileIncludeResolver] gives a unit, so an include that leads
  /// back here is recognised as the cycle it is. Symbolic links are followed,
  /// which also makes it the directory relative includes resolve against.
  String _rootId() {
    try {
      return normalizeCanonicalPath(resolveSymbolicLinksSync());
    } on FileSystemException {
      return normalizeCanonicalPath(absolute.path);
    }
  }

  /// The asynchronous counterpart to [_rootId].
  Future<String> _rootIdAsync() async {
    try {
      return normalizeCanonicalPath(await resolveSymbolicLinks());
    } on FileSystemException {
      return normalizeCanonicalPath(absolute.path);
    }
  }

  /// Reads the root, reporting its absence the way an include's would be.
  ///
  /// Nothing can mark the file a caller named optional, so a missing root is
  /// always an error — but it is the same error an unfindable include raises,
  /// rather than a bare filesystem exception from one entry point and a
  /// [MissingIncludeException] from the other.
  Future<String> _readRoot(Future<String> Function() read) async {
    try {
      return await read();
    } on PathNotFoundException {
      throw MissingIncludeException(path, path);
    }
  }

  String _readRootSync(String Function() read) {
    try {
      return read();
    } on PathNotFoundException {
      throw MissingIncludeException(path, path);
    }
  }

  /// Writes [doc] to this file, replacing whatever was there.
  ///
  /// ```dart
  /// await File('config.flat').writeFlat(doc);
  /// ```
  Future<void> writeFlat(
    FlatDocument doc, {
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) => writeAsBytes(
    doc.encodeToBytesWithWriteOptions(
      options: options,
      writeOptions: writeOptions,
    ),
  );

  /// Writes [doc] to this file, replacing whatever was there, synchronously.
  void writeFlatSync(
    FlatDocument doc, {
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) => writeAsBytesSync(
    doc.encodeToBytesWithWriteOptions(
      options: options,
      writeOptions: writeOptions,
    ),
  );
}
