import 'dart:io';

import 'document.dart';
import 'document_extensions.dart';
import 'includes.dart';
import 'options.dart';
import 'parser.dart';

/// Reads a configuration file and parses it into a [FlatDocument].
///
/// This is a convenience function that opens a file at the given [path] and
/// parses its contents as a flat configuration file. The parsing behavior
/// can be customized using [options] and [readOptions].
///
/// Example:
/// ```dart
/// final doc = await parseFlatFile('config.flat');
/// print(doc['background']); // 343028
/// ```
Future<FlatDocument> parseFlatFile(
  String path, {
  FlatParseOptions options = const FlatParseOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
}) async =>
    File(path).parseFlat(
      options: options,
      readOptions: readOptions,
    );

/// Reads a configuration file with includes and parses it into a [FlatDocument].
///
/// This is a convenience function that opens a file at the given [path] and
/// parses its contents as a flat configuration file with automatic include
/// processing. The include key is configurable via [options.includeKey] (defaults
/// to `config-file` for Ghostty compatibility). The parsing behavior can be
/// customized using [options] and [readOptions].
///
/// Example:
/// ```dart
/// final doc = await parseFlatFileWithIncludes('main.conf');
/// print(doc['background']); // 343028
///
/// // With custom include key
/// final doc = await parseFlatFileWithIncludes(
///   'main.conf',
///   options: const FlatParseOptions(includeKey: 'include'),
/// );
/// ```
///
/// Throws [CircularIncludeException] if a circular include is detected.
/// Throws [MissingIncludeException] if a required include file is missing.
Future<FlatDocument> parseFlatFileWithIncludes(
  String path, {
  FlatParseOptions options = const FlatParseOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
}) async =>
    FlatConfigIncludes.parseWithIncludesFromPath(
      path,
      options: options,
      readOptions: readOptions,
    );

/// File-based helpers for reading and writing flat configuration files.
///
/// This extension adds methods to [File] for working with flat configuration files.
/// It provides both asynchronous and synchronous methods for reading and writing
/// configuration data.
extension FlatConfigIO on File {
  /// Parses this file asynchronously into a [FlatDocument].
  ///
  /// This method reads the file contents and parses them as a flat configuration
  /// file. The parsing behavior can be customized using [options] and [readOptions].
  ///
  /// Example:
  /// ```dart
  /// final file = File('config.flat');
  /// final doc = await file.parseFlat();
  /// ```
  Future<FlatDocument> parseFlat({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async {
    final lines = openRead()
        .transform(readOptions.encoding.decoder)
        .transform(readOptions.lineSplitter);

    return FlatConfig.parseFromStringStream(
      lines,
      options: options,
    );
  }

  /// Parses this file synchronously into a [FlatDocument].
  ///
  /// This is a synchronous version of [parseFlat] that reads the entire file
  /// into memory before parsing. Use this when you need synchronous access
  /// to the configuration data.
  ///
  /// Example:
  /// ```dart
  /// final file = File('config.flat');
  /// final doc = file.parseFlatSync();
  /// ```
  FlatDocument parseFlatSync({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) {
    final content = readAsStringSync(encoding: readOptions.encoding);

    return FlatConfig.parse(
      content,
      options: options,
      lineSplitter: readOptions.lineSplitter,
    );
  }

  /// Parses this file with automatic include processing.
  ///
  /// This method parses the file and automatically processes any include
  /// directives found within it. The include key is configurable via
  /// [options.includeKey] (defaults to `config-file` for Ghostty compatibility).
  /// The includes are processed recursively with cycle detection and support
  /// for optional includes.
  ///
  /// Example:
  /// ```dart
  /// final file = File('main.conf');
  /// final doc = await file.parseFlatWithIncludes();
  ///
  /// // With custom include key
  /// final doc = await file.parseFlatWithIncludes(
  ///   options: const FlatParseOptions(includeKey: 'include'),
  /// );
  /// ```
  ///
  /// Throws [CircularIncludeException] if a circular include is detected.
  /// Throws [MissingIncludeException] if a required include file is missing.
  Future<FlatDocument> parseFlatWithIncludes({
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async =>
      FlatConfigIncludes.parseWithIncludes(
        this,
        options: options,
        readOptions: readOptions,
      );

  /// Writes a [FlatDocument] to this file asynchronously.
  ///
  /// This method encodes the document to text and writes it to the file.
  /// The encoding and formatting behavior can be customized using [options]
  /// and [writeOptions].
  ///
  /// Example:
  /// ```dart
  /// final file = File('config.flat');
  /// final doc = FlatConfig.fromMap({'background': '343028'});
  /// await file.writeFlat(doc);
  /// ```
  Future<void> writeFlat(
    FlatDocument doc, {
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) async {
    await writeAsBytes(
      doc.encodeToBytesWithWriteOptions(
        options: options,
        writeOptions: writeOptions,
      ),
    );
  }

  /// Writes a [FlatDocument] to this file synchronously.
  ///
  /// This is a synchronous version of [writeFlat] that writes the document
  /// to the file immediately. Use this when you need synchronous file operations.
  ///
  /// Example:
  /// ```dart
  /// final file = File('config.flat');
  /// final doc = FlatConfig.fromMap({'background': '343028'});
  /// file.writeFlatSync(doc);
  /// ```
  void writeFlatSync(
    FlatDocument doc, {
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) {
    writeAsBytesSync(
      doc.encodeToBytesWithWriteOptions(
        options: options,
        writeOptions: writeOptions,
      ),
    );
  }
}

/// Adds file I/O functionality to [FlatDocument].
///
/// This extension adds methods to [FlatDocument] for saving configuration data
/// to files. It provides both asynchronous and synchronous methods for writing
/// documents to the filesystem.
extension FlatDocumentIO on FlatDocument {
  /// Saves this document to a file asynchronously.
  ///
  /// This method creates or overwrites a file at the given [path] with the
  /// encoded contents of this document. The encoding and formatting behavior
  /// can be customized using [options] and [writeOptions].
  ///
  /// Example:
  /// ```dart
  /// final doc = FlatConfig.fromMap({'background': '343028'});
  /// await doc.saveToFile('config.flat');
  /// ```
  Future<void> saveToFile(
    String path, {
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) async {
    await File(path).writeAsBytes(
      encodeToBytesWithWriteOptions(
        options: options,
        writeOptions: writeOptions,
      ),
    );
  }

  /// Saves this document to a file synchronously.
  ///
  /// This is a synchronous version of [saveToFile] that writes the document
  /// to the file immediately. Use this when you need synchronous file operations.
  ///
  /// Example:
  /// ```dart
  /// final doc = FlatConfig.fromMap({'background': '343028'});
  /// doc.saveToFileSync('config.flat');
  /// ```
  void saveToFileSync(
    String path, {
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) {
    File(path).writeAsBytesSync(
      encodeToBytesWithWriteOptions(
        options: options,
        writeOptions: writeOptions,
      ),
    );
  }
}
