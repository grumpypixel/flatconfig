import 'dart:convert';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'document.dart';
import 'exceptions.dart';
import 'options.dart';
import 'parser_utils.dart';

/// Main parser class for flat `key = value` configuration files.
///
/// [FlatConfig] provides static methods for parsing configuration data from
/// various sources including strings, streams, and files. It supports flexible
/// parsing options and can handle quoted values, comments, and duplicate keys.
///
/// Example:
/// ```dart
/// final doc = FlatConfig.parse('background = 282c34');
/// print(doc['background']); // 282c34
/// ```
class FlatConfig {
  /// Parses a configuration string into a [FlatDocument].
  ///
  /// This method processes a multi-line configuration string and returns a
  /// [FlatDocument] containing all valid key-value pairs. The parsing behavior
  /// can be customized using [options].
  ///
  /// Parsing rules:
  /// - Lines starting with the comment prefix (default `#`) are ignored
  /// - Empty lines are ignored
  /// - Keys are trimmed of whitespace
  /// - Values are processed as follows:
  ///   - Quoted values preserve inner whitespace and `=` characters
  ///   - Unquoted values are trimmed of whitespace
  /// - Duplicate keys are preserved in insertion order
  /// - Empty unquoted values are treated as `null` (configuration reset)
  ///
  /// Example:
  /// ```dart
  /// const config = '''
  /// # This is a comment
  /// background = 282c34
  /// title = "My Application"
  /// debug = true
  /// ''';
  ///
  /// final doc = FlatConfig.parse(config);
  /// print(doc['background']); // 282c34
  /// print(doc['title']); // My Application
  /// ```
  static FlatDocument parse(
    String source, {
    FlatParseOptions options = const FlatParseOptions(),
    LineSplitter lineSplitter = const LineSplitter(),
  }) {
    assert(!options.commentPrefix.contains('\n'));

    if (source.trim().isEmpty) {
      return FlatDocument.empty();
    }

    return parseLines(
      lineSplitter.convert(source),
      options: options,
    );
  }

  /// Parses a configuration from a list of lines.
  ///
  /// This method is useful when you already have the configuration data split
  /// into individual lines. Each line is processed according to the same rules
  /// as [parse], but without the need to split the input string first.
  ///
  /// Example:
  /// ```dart
  /// final lines = [
  ///   'background = 282c34',
  ///   'title = "My App"',
  ///   '# This is a comment',
  /// ];
  ///
  /// final doc = FlatConfig.parseLines(lines);
  /// ```
  static FlatDocument parseLines(
    List<String> lines, {
    FlatParseOptions options = const FlatParseOptions(),
  }) {
    assert(!options.commentPrefix.contains('\n'));

    final out = <FlatEntry>[];
    var lineNumber = 0;

    for (final raw in lines) {
      lineNumber++;

      final entry = parseLine(
        raw,
        lineNumber: lineNumber,
        options: options,
      );
      if (entry != null) {
        out.add(entry);
      }
    }

    return FlatDocument(out);
  }

  /// Parses a configuration from a byte stream.
  ///
  /// This method is useful for reading configuration data from files or network
  /// streams. The byte stream is first decoded using the specified encoding,
  /// then split into lines, and finally parsed as configuration data.
  ///
  /// Example:
  /// ```dart
  /// final file = File('config.flat');
  /// final doc = await FlatConfig.parseFromByteStream(file.openRead());
  /// ```
  static Future<FlatDocument> parseFromByteStream(
    Stream<List<int>> stream, {
    FlatParseOptions options = const FlatParseOptions(),
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  }) async =>
      parseFromStringStream(
        stream.transform(readOptions.encoding.decoder).transform(
              readOptions.lineSplitter,
            ),
        options: options,
      );

  /// Parses a configuration from a string stream.
  ///
  /// This method processes a stream of strings, where each string represents
  /// one line of configuration data. It's useful when you have a stream of
  /// lines that you want to parse as configuration.
  static Future<FlatDocument> parseFromStringStream(
    Stream<String> stream, {
    FlatParseOptions options = const FlatParseOptions(),
  }) async {
    assert(!options.commentPrefix.contains('\n'));

    final out = <FlatEntry>[];

    var lineNumber = 0;

    await for (var raw in stream) {
      lineNumber++;

      final entry = parseLine(
        raw,
        lineNumber: lineNumber,
        options: options,
      );

      if (entry != null) {
        out.add(entry);
      }
    }

    return FlatDocument(out);
  }

  /// Lazily parses a byte stream, yielding [FlatEntry]s as they are read.
  ///
  /// This method is useful for processing large configuration files without
  /// loading the entire document into memory at once. Each valid configuration
  /// entry is yielded as soon as it's parsed.
  ///
  /// Example:
  /// ```dart
  /// await for (final entry in FlatConfig.parseEntries(file.openRead())) {
  ///   print('${entry.key} = ${entry.value}');
  /// }
  /// ```
  static Stream<FlatEntry> parseEntries(
    Stream<List<int>> stream, {
    FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
    FlatParseOptions options = const FlatParseOptions(),
  }) async* {
    final lines = stream
        .transform(readOptions.encoding.decoder)
        .transform(readOptions.lineSplitter);

    yield* parseEntriesFromStringStream(
      lines,
      options: options,
    );
  }

  /// Lazily parses a string stream, yielding [FlatEntry]s as they are read.
  ///
  /// This method processes a stream of strings (lines) and yields each valid
  /// configuration entry as it's encountered. Useful for streaming processing
  /// of configuration data.
  static Stream<FlatEntry> parseEntriesFromStringStream(
    Stream<String> stream, {
    FlatParseOptions options = const FlatParseOptions(),
  }) async* {
    assert(!options.commentPrefix.contains('\n'));

    var lineNumber = 0;
    await for (var raw in stream) {
      lineNumber++;

      final entry = parseLine(
        raw,
        lineNumber: lineNumber,
        options: options,
      );
      if (entry != null) {
        yield entry;
      }
    }
  }

  /// Builds a [FlatDocument] from a map of string keys and values.
  ///
  /// This method creates a configuration document from a map, which is useful
  /// for programmatically creating configuration data.
  ///
  /// Properties:
  /// - Insertion order is preserved based on the map's iteration order
  /// - A `null` value becomes a reset entry (`key =`)
  /// - Only one entry per key is created (no duplicates)
  ///
  /// Example:
  /// ```dart
  /// final map = {
  ///   'background': '282c34',
  ///   'title': 'My App',
  ///   'debug': null, // becomes 'debug ='
  /// };
  ///
  /// final doc = FlatConfig.fromMap(map);
  /// ```
  static FlatDocument fromMap(Map<String, String?> map) {
    final out = [for (final e in map.entries) FlatEntry(e.key, e.value)];

    return FlatDocument(out);
  }

  /// Builds a [FlatDocument] from a map of dynamic values.
  ///
  /// This method converts a map with dynamic values into a configuration document
  /// by stringifying the values. The [valueEncoder] function can be used to
  /// customize how values are converted to strings.
  ///
  /// Properties:
  /// - Values are stringified using [valueEncoder] (defaults to [toString])
  /// - Returning `null` from [valueEncoder] produces a reset entry
  /// - Insertion order is preserved based on the map's iteration order
  ///
  /// Example:
  /// ```dart
  /// final map = {
  ///   'port': 8080,
  ///   'debug': true,
  ///   'name': 'My App',
  /// };
  ///
  /// final doc = FlatConfig.fromDynamicMap(map);
  /// ```
  static FlatDocument fromDynamicMap(
    Map<String, dynamic> map, {
    String? Function(String key, dynamic value)? valueEncoder,
  }) {
    final encodeValue =
        valueEncoder ?? ((String key, dynamic value) => value?.toString());

    final out = <FlatEntry>[
      for (final e in map.entries) FlatEntry(e.key, encodeValue(e.key, e.value))
    ];

    return FlatDocument(out);
  }

  /// Parses a single configuration line into a [FlatEntry].
  ///
  /// This method processes one line of configuration text and returns a [FlatEntry]
  /// if the line contains a valid key-value pair, or null if the line should be
  /// ignored (empty, comment, or invalid).
  ///
  /// Lax mode:
  /// - Missing equals are ignored
  /// - Empty keys are ignored
  ///
  /// The [lineNumber] parameter is used for error reporting when exceptions are thrown.
  @visibleForTesting
  static FlatEntry? parseLine(
    String raw, {
    int? lineNumber,
    FlatParseOptions options = const FlatParseOptions(),
  }) {
    final line = preprocessLine(raw, options.commentPrefix);
    if (line == null) {
      return null;
    }

    final ln = lineNumber ?? 0;
    final strict = options.strict;
    final decodeEscapesInQuoted = options.decodeEscapesInQuoted;
    final onMissingEquals = options.onMissingEquals;
    final onEmptyKey = options.onEmptyKey;

    final sep = Constants.pairSeparator;
    final idx = line.indexOf(sep);
    if (idx < 0) {
      if (strict) {
        throw MissingEqualsException(ln, raw);
      }
      onMissingEquals?.call(ln, raw);

      return null;
    }

    // Key left of separator, right trimRight
    final trimmedKey = line.substring(0, idx).trimRight();
    if (trimmedKey.isEmpty) {
      if (strict) {
        throw EmptyKeyException(ln, raw);
      }
      onEmptyKey?.call(ln, raw);

      return null;
    }

    // Value right of separator directly to parseValue
    final value = parseValue(
      line.substring(idx + sep.length),
      decodeEscapesInQuoted: decodeEscapesInQuoted,
      strict: strict,
      lineNumber: ln,
      rawLine: raw,
    );

    return FlatEntry(trimmedKey, value);
  }

  /// Trims and applies comment rules to a raw line.
  ///
  /// This method preprocesses a raw configuration line by:
  /// - Removing BOM (Byte Order Mark) if present
  /// - Trimming whitespace
  /// - Checking if the line is a comment (starts with [commentPrefix])
  /// - Checking if the line is empty
  ///
  /// Returns the cleaned line to be parsed, or `null` if the line should be ignored.
  @visibleForTesting
  static String? preprocessLine(String raw, String commentPrefix) {
    if (raw.isEmpty) {
      return null;
    }

    var start = 0;
    var end = raw.length;

    // Strip BOM
    if (raw.codeUnitAt(0) == Constants.bomCharCode) {
      start = 1;
    }

    // Trim left
    while (start < end) {
      final c = raw.codeUnitAt(start);
      if (!isWhitespace(c)) {
        break;
      }
      start++;
    }

    // Check comment prefix (after Trim-Left)
    if (commentPrefix.isNotEmpty &&
        start + commentPrefix.length <= end &&
        raw.startsWith(commentPrefix, start)) {
      return null;
    }

    // Trim right
    while (end > start) {
      final c = raw.codeUnitAt(end - 1);
      if (!isWhitespace(c)) {
        break;
      }
      end--;
    }

    if (end <= start) {
      return null;
    }

    // If nothing left, null; otherwise Substring without Trim-Allocation
    return raw.substring(start, end);
  }
}
