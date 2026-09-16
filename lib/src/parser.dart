import 'dart:convert';

import 'package:meta/meta.dart';

import 'constants.dart';
import 'document.dart';
import 'exceptions.dart';
import 'issue.dart';
import 'options.dart';
import 'parser_utils.dart';
import 'validation.dart';

/// Parsing entry points for flat `key = value` configuration files.
///
/// These are the implementations behind the `FlatDocument.parse*` statics.
/// They live here rather than on the class so that `document.dart` stays the
/// one file describing the type, and this one the one describing the grammar.
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
/// background = 343028
/// title = "My Application"
/// debug = true
/// ''';
///
/// final doc = FlatConfig.parse(config);
/// print(doc['background']); // 343028
/// print(doc['title']); // My Application
/// ```
FlatDocument parseSource(
  String source, {
  FlatParseOptions options = const FlatParseOptions(),
  LineSplitter lineSplitter = const LineSplitter(),
}) {
  checkCommentPrefix(options.commentPrefix);

  if (source.trim().isEmpty) {
    return FlatDocument.empty();
  }

  return parseSourceLines(lineSplitter.convert(source), options: options);
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
///   'background = 343028',
///   'title = "My App"',
///   '# This is a comment',
/// ];
///
/// final doc = FlatConfig.parseLines(lines);
/// ```
FlatDocument parseSourceLines(
  List<String> lines, {
  FlatParseOptions options = const FlatParseOptions(),
}) {
  checkCommentPrefix(options.commentPrefix);

  final out = <FlatEntry>[];
  var lineNumber = 0;

  for (final raw in lines) {
    lineNumber++;

    final entry = parseLine(raw, lineNumber: lineNumber, options: options);
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
Future<FlatDocument> parseByteStream(
  Stream<List<int>> stream, {
  FlatParseOptions options = const FlatParseOptions(),
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
}) async => parseStringStream(
  stream
      .transform(readOptions.encoding.decoder)
      .transform(readOptions.lineSplitter),
  options: options,
);

/// Parses a configuration from a string stream.
///
/// This method processes a stream of strings, where each string represents
/// one line of configuration data. It's useful when you have a stream of
/// lines that you want to parse as configuration.
Future<FlatDocument> parseStringStream(
  Stream<String> stream, {
  FlatParseOptions options = const FlatParseOptions(),
}) async {
  checkCommentPrefix(options.commentPrefix);

  final out = <FlatEntry>[];

  var lineNumber = 0;

  await for (var raw in stream) {
    lineNumber++;

    final entry = parseLine(raw, lineNumber: lineNumber, options: options);

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
Stream<FlatEntry> streamEntriesFromBytes(
  Stream<List<int>> stream, {
  FlatStreamReadOptions readOptions = const FlatStreamReadOptions(),
  FlatParseOptions options = const FlatParseOptions(),
}) async* {
  final lines = stream
      .transform(readOptions.encoding.decoder)
      .transform(readOptions.lineSplitter);

  yield* streamEntriesFromStrings(lines, options: options);
}

/// Lazily parses a string stream, yielding [FlatEntry]s as they are read.
///
/// This method processes a stream of strings (lines) and yields each valid
/// configuration entry as it's encountered. Useful for streaming processing
/// of configuration data.
Stream<FlatEntry> streamEntriesFromStrings(
  Stream<String> stream, {
  FlatParseOptions options = const FlatParseOptions(),
}) async* {
  checkCommentPrefix(options.commentPrefix);

  var lineNumber = 0;
  await for (var raw in stream) {
    lineNumber++;

    final entry = parseLine(raw, lineNumber: lineNumber, options: options);
    if (entry != null) {
      yield entry;
    }
  }
}

/// Builds a [FlatDocument] from environment-like maps.
///
/// This method is pure and does not access [Platform.environment] or any
/// global state. You must explicitly pass the environment map, making it
/// suitable for Flutter Web, WASM, and testing scenarios.
///
/// Precedence order: [FlatEnvOptions.defaults] → [env] → [FlatEnvOptions.merge]
///
/// Processing steps:
/// 1. Apply default values from [options.defaults]
/// 2. Apply environment variables from [env] (with optional prefix filtering)
/// 3. Apply override values from [options.merge]
/// 4. Drop empty values if [options.keepEmptyValues] is false
/// 5. Interpolate `${VAR}` placeholders if [options.interpolate] is true
/// 6. Return a [FlatDocument]
///
/// Example - Basic usage:
/// ```dart
/// final env = {'HOST': 'localhost', 'PORT': '8080'};
/// final doc = FlatConfig.fromEnvironment(env);
/// print(doc['HOST']); // localhost
/// ```
///
/// Example - With prefix filtering:
/// ```dart
/// final env = {
///   'APP_HOST': 'api.example.com',
///   'APP_PORT': '8080',
///   'OTHER_VAR': 'ignored',
/// };
/// final doc = FlatConfig.fromEnvironment(
///   env,
///   options: FlatEnvOptions(prefix: 'APP_'),
/// );
/// final clean = doc.stripPrefix('APP_');
/// print(clean.toMap()); // {HOST: api.example.com, PORT: 8080}
/// ```
///
/// Example - With interpolation:
/// ```dart
/// final env = {
///   'HOST': 'api.example.com',
///   'PORT': '8080',
///   'URL': 'https://${HOST}:${PORT}',
/// };
/// final doc = FlatConfig.fromEnvironment(
///   env,
///   options: FlatEnvOptions(interpolate: true),
/// );
/// print(doc['URL']); // https://api.example.com:8080
/// ```
///
/// Example - With precedence:
/// ```dart
/// final env = {'PORT': '3000'};
/// final doc = FlatConfig.fromEnvironment(
///   env,
///   options: FlatEnvOptions(
///     defaults: {'HOST': 'localhost', 'PORT': '8080'},
///     merge: {'DEBUG': 'true'},
///   ),
/// );
/// print(doc.toMap()); // {HOST: localhost, PORT: 3000, DEBUG: true}
/// ```
FlatDocument documentFromEnvironment(
  Map<String, String> env, {
  FlatEnvOptions? options,
}) {
  final opts = options ?? FlatEnvOptions();
  final out = <String, String?>{};

  // 1) Start with defaults (lowest precedence).
  if (opts.defaults.isNotEmpty) {
    for (final e in opts.defaults.entries) {
      out[e.key] = e.value;
    }
  }

  // 2) Apply provided env.
  if (env.isNotEmpty) {
    final usePrefix = opts.prefix;
    if (usePrefix == null || usePrefix.isEmpty) {
      for (final e in env.entries) {
        out[e.key] = e.value;
      }
    } else {
      if (opts.caseSensitive) {
        for (final e in env.entries) {
          if (e.key.startsWith(usePrefix)) {
            out[e.key] = e.value;
          }
        }
      } else {
        final lp = usePrefix.toLowerCase();
        for (final e in env.entries) {
          if (e.key.toLowerCase().startsWith(lp)) {
            out[e.key] = e.value;
          }
        }
      }
    }
  }

  // 3) Final merge overrides (highest precedence).
  if (opts.merge.isNotEmpty) {
    for (final e in opts.merge.entries) {
      out[e.key] = e.value;
    }
  }

  // 4) Drop empty values if requested.
  if (!opts.keepEmptyValues) {
    final keysToDrop = <String>[];
    for (final kv in out.entries) {
      if ((kv.value ?? '').isEmpty) {
        keysToDrop.add(kv.key);
      }
    }
    for (final k in keysToDrop) {
      out.remove(k);
    }
  }

  // 5) Interpolate ${VAR} if enabled. Single pass is usually enough for env.
  if (opts.interpolate) {
    final re = RegExp(opts.varPattern);
    final snapshot = Map<String, String?>.from(out);
    for (final k in out.keys.toList()) {
      final raw = out[k];
      if (raw == null || raw.isEmpty) {
        continue;
      }

      // Replace all matches by rebuilding the string
      final matches = re.allMatches(raw).toList();
      if (matches.isEmpty) {
        continue;
      }

      final buffer = StringBuffer();
      var lastEnd = 0;

      for (final m in matches) {
        // Add the text before this match
        buffer.write(raw.substring(lastEnd, m.start));

        // Add the replacement value
        if (m.groupCount >= 1) {
          final name = m.group(1)!;
          final rep = snapshot[name] ?? '';
          buffer.write(rep);
        }

        lastEnd = m.end;
      }

      // Add any remaining text after the last match
      buffer.write(raw.substring(lastEnd));

      out[k] = buffer.toString();
    }
  }

  // Values are already strings here, so no encoding step is needed.
  return FlatDocument([for (final e in out.entries) FlatEntry(e.key, e.value)]);
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
FlatEntry? parseLine(
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
  final onIssue = options.onIssue;

  final sep = Constants.pairSeparator;
  final idx = line.indexOf(sep);
  if (idx < 0) {
    if (strict) {
      throw MissingEqualsException(ln, raw, column: line.length);
    }
    onIssue?.call(
      FlatIssue(
        kind: FlatIssueKind.missingEquals,
        line: ln,
        column: line.length,
        rawLine: raw,
      ),
    );

    return null;
  }

  // Key left of separator, right trimRight
  final trimmedKey = line.substring(0, idx).trimRight();
  if (trimmedKey.isEmpty) {
    if (strict) {
      throw EmptyKeyException(ln, raw, column: idx + 1);
    }
    onIssue?.call(
      FlatIssue(
        kind: FlatIssueKind.emptyKey,
        line: ln,
        column: idx + 1,
        rawLine: raw,
      ),
    );

    return null;
  }

  // A key the encoder could not write back out is not a key (SPEC.md 3).
  final keyProblem = invalidKeyReason(trimmedKey);
  if (keyProblem != null) {
    if (strict) {
      throw InvalidKeyException(trimmedKey, keyProblem, ln, raw);
    }
    onIssue?.call(
      FlatIssue(
        kind: FlatIssueKind.invalidKey,
        line: ln,
        column: 1,
        rawLine: raw,
        detail: keyProblem,
      ),
    );

    return null;
  }

  // Value right of separator directly to parseValue
  final value = parseValue(
    line.substring(idx + sep.length),
    decodeEscapesInQuoted: decodeEscapesInQuoted,
    strict: strict,
    lineNumber: ln,
    rawLine: raw,
    onIssue: onIssue,
    columnOffset: idx + sep.length,
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
String? preprocessLine(String raw, String commentPrefix) {
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
