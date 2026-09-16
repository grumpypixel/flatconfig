import 'dart:io';

import 'document.dart';
import 'includes.dart';
import 'options.dart';
import 'parser.dart';

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
  }) => FlatConfigIncludes.parseWithIncludes(
    this,
    options: options,
    includeOptions: includeOptions,
    readOptions: readOptions,
  );

  /// Parses this file and follows every include it names, synchronously.
  FlatDocument parseWithIncludesSync({
    FlatParseOptions options = const FlatParseOptions(),
    FlatIncludeOptions includeOptions = const FlatIncludeOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) => FlatConfigIncludes.parseWithIncludesSync(
    this,
    options: options,
    includeOptions: includeOptions,
    readOptions: readOptions,
  );

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
