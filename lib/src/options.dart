import 'dart:convert';

import 'constants.dart';

/// Callback function invoked when a parsing error occurs.
///
/// The [lineNumber] parameter indicates the 1-based line number where the error
/// occurred, and [line] contains the raw line content that caused the error.
typedef OnErrorHandler = void Function(int lineNumber, String line);

/// Options that control how configuration files are parsed.
///
/// These options allow you to customize the parsing behavior, including comment
/// handling, escape sequence processing, include processing, and error handling strategies.
class FlatParseOptions {
  /// Creates parser options with the specified configuration.
  ///
  /// All parameters are optional and have sensible defaults for typical
  /// configuration file parsing.
  const FlatParseOptions({
    this.commentPrefix = Constants.commentPrefix,
    this.decodeEscapesInQuoted = true,
    this.strict = false,
    this.includeKey = Constants.includeKey,
    this.maxIncludeDepth = 64,
    this.onMissingEquals,
    this.onEmptyKey,
  });

  /// Prefix used to mark comment lines.
  ///
  /// Lines that start with this prefix (after trimming) are ignored during parsing.
  /// Defaults to `#`.
  final String commentPrefix;

  /// Whether to decode escape sequences inside quoted values.
  ///
  /// When true, `\"` is decoded to `"` and `\\` is decoded to `\` inside
  /// quoted values. Every other backslash stays literal.
  ///
  /// Defaults to true, matching [FlatEncodeOptions.escapeQuoted]. The two must
  /// agree: a document written by the encoder has to be readable by the parser
  /// without the caller configuring anything (SPEC.md 5.2).
  final bool decodeEscapesInQuoted;

  /// Whether invalid lines should throw exceptions instead of being ignored.
  ///
  /// When true, parsing errors (like missing `=` or empty keys) will throw
  /// exceptions. When false, invalid lines are silently ignored. Defaults to false.
  final bool strict;

  /// Key used to identify include directives in configuration files.
  ///
  /// When parsing with includes, lines with this key are treated as include
  /// directives. The value should be a path to another configuration file.
  /// Defaults to [Constants.includeKey] (`config-file`) for Ghostty compatibility.
  ///
  /// Example:
  /// ```dart
  /// // With default includeKey = Constants.includeKey
  /// config-file = theme.conf
  ///
  /// // With includeKey = 'include'
  /// include = theme.conf
  /// ```
  final String includeKey;

  /// Maximum recursion depth for processing includes.
  ///
  /// This defensive limit prevents pathological include graphs from causing
  /// unbounded recursion in cases where canonicalization fails or the graph
  /// is extremely deep. Defaults to 64.
  final int maxIncludeDepth;

  /// Handler called when a line is missing the `=` separator.
  ///
  /// This is only called when [strict] is false. If null, invalid lines are
  /// silently ignored.
  final OnErrorHandler? onMissingEquals;

  /// Handler called when a key is empty (e.g., `= value`).
  ///
  /// This is only called when [strict] is false. If null, invalid lines are
  /// silently ignored.
  final OnErrorHandler? onEmptyKey;

  /// Returns a copy of these options with selectively replaced fields.
  ///
  /// Only the provided parameters will be changed; all others will remain
  /// the same as in the original options object.
  FlatParseOptions copyWith({
    String? commentPrefix,
    bool? decodeEscapesInQuoted,
    bool? strict,
    String? includeKey,
    int? maxIncludeDepth,
    OnErrorHandler? onMissingEquals,
    OnErrorHandler? onEmptyKey,
  }) =>
      FlatParseOptions(
        commentPrefix: commentPrefix ?? this.commentPrefix,
        decodeEscapesInQuoted:
            decodeEscapesInQuoted ?? this.decodeEscapesInQuoted,
        strict: strict ?? this.strict,
        includeKey: includeKey ?? this.includeKey,
        maxIncludeDepth: maxIncludeDepth ?? this.maxIncludeDepth,
        onMissingEquals: onMissingEquals ?? this.onMissingEquals,
        onEmptyKey: onEmptyKey ?? this.onEmptyKey,
      );
}

/// Options for reading configuration data from a byte stream.
///
/// These options control how byte streams are decoded and split into lines
/// before being parsed as configuration data.
class FlatStreamReadOptions {
  /// Creates stream read options with the specified configuration.
  const FlatStreamReadOptions({
    this.encoding = utf8,
    this.lineSplitter = const LineSplitter(),
  });

  /// Text encoding used to decode byte streams.
  ///
  /// Defaults to UTF-8, which is the most common encoding for text files.
  final Encoding encoding;

  /// Line splitter used to break decoded text into lines.
  ///
  /// Defaults to [LineSplitter], which handles common line ending conventions
  /// (CRLF, LF, CR).
  final LineSplitter lineSplitter;

  /// Returns a copy of these options with selectively replaced fields.
  ///
  /// Only the provided parameters will be changed; all others will remain
  /// the same as in the original options object.
  FlatStreamReadOptions copyWith({
    Encoding? encoding,
    LineSplitter? lineSplitter,
  }) =>
      FlatStreamReadOptions(
        encoding: encoding ?? this.encoding,
        lineSplitter: lineSplitter ?? this.lineSplitter,
      );
}

/// Options for writing configuration data to a byte stream.
///
/// These options control how configuration documents are encoded and written
/// to byte streams, including text encoding and line ending handling.
class FlatStreamWriteOptions {
  /// Creates stream write options with the specified configuration.
  const FlatStreamWriteOptions({
    this.encoding = utf8,
    this.lineTerminator = Constants.newline,
    this.ensureTrailingNewline = false,
  });

  /// Text encoding used when writing the file.
  ///
  /// Defaults to UTF-8, which is the most common encoding for text files.
  final Encoding encoding;

  /// Line terminator to use when writing lines.
  ///
  /// Defaults to `\n` (Unix-style line endings). You can use `\r\n` for
  /// Windows-style line endings or `\r` for classic Mac-style line endings.
  final String lineTerminator;

  /// Whether to ensure the final output ends with a newline.
  ///
  /// When true, a newline will be added to the end of the file if it doesn't
  /// already end with one. Defaults to false.
  final bool ensureTrailingNewline;

  /// Returns a copy of these options with selectively replaced fields.
  ///
  /// Only the provided parameters will be changed; all others will remain
  /// the same as in the original options object.
  FlatStreamWriteOptions copyWith({
    Encoding? encoding,
    String? lineTerminator,
    bool? ensureTrailingNewline,
  }) =>
      FlatStreamWriteOptions(
        encoding: encoding ?? this.encoding,
        lineTerminator: lineTerminator ?? this.lineTerminator,
        ensureTrailingNewline:
            ensureTrailingNewline ?? this.ensureTrailingNewline,
      );
}

/// Options for encoding configuration data to text.
///
/// These options control how [FlatDocument] objects are converted to text
/// format, including quoting behavior and escape sequence handling.
class FlatEncodeOptions {
  /// Creates encode options with the specified configuration.
  const FlatEncodeOptions({
    this.escapeQuoted = true,
    this.quoteIfWhitespace = true,
    this.alwaysQuote = false,
    this.commentPrefix = Constants.commentPrefix,
  });

  /// Whether to escape quotes and backslashes in quoted values.
  ///
  /// When true, `"` becomes `\"` and `\` becomes `\\` inside quoted values.
  ///
  /// Defaults to true. Unescaped output is only readable back because the
  /// parser used to close quoted values at the last quote rather than the
  /// first; producing output a conforming parser would misread must not be the
  /// default (SPEC.md 7).
  final bool escapeQuoted;

  /// Whether to quote values that have leading or trailing whitespace.
  ///
  /// When true, values like `" value "` will be quoted to preserve whitespace.
  /// Defaults to true.
  final bool quoteIfWhitespace;

  /// Whether to quote all non-null values.
  ///
  /// When true, all values will be wrapped in quotes regardless of their content.
  /// Defaults to false.
  final bool alwaysQuote;

  /// Prefix used to mark comment lines.
  ///
  /// This is used to determine if a value starts with a comment and should be quoted.
  /// Defaults to `#`.
  final String commentPrefix;

  /// Returns a copy of these options with selectively replaced fields.
  ///
  /// Only the provided parameters will be changed; all others will remain
  /// the same as in the original options object.
  FlatEncodeOptions copyWith({
    bool? escapeQuoted,
    bool? quoteIfWhitespace,
    bool? alwaysQuote,
    String? commentPrefix,
  }) =>
      FlatEncodeOptions(
        escapeQuoted: escapeQuoted ?? this.escapeQuoted,
        quoteIfWhitespace: quoteIfWhitespace ?? this.quoteIfWhitespace,
        alwaysQuote: alwaysQuote ?? this.alwaysQuote,
        commentPrefix: commentPrefix ?? this.commentPrefix,
      );
}

/// Options for loading environment variables into a FlatDocument.
///
/// These options control how environment-like maps are processed when using
/// [FlatConfig.fromEnvironment], including prefix filtering, interpolation,
/// and precedence handling. Pure in-memory; no dart:io required.
class FlatEnvOptions {
  /// Creates a new [FlatEnvOptions] with the specified configuration.
  ///
  /// All parameters are optional and have sensible defaults for typical
  /// environment variable loading scenarios.
  const FlatEnvOptions({
    this.prefix,
    this.caseSensitive = true,
    this.interpolate = true,
    this.keepEmptyValues = true,
    this.varPattern = r'\$\{([A-Za-z0-9_]+)\}',
    this.defaults = const {},
    this.merge = const {},
  });

  /// Optional key prefix to include only env vars starting with this prefix.
  ///
  /// If set, only keys that start with this prefix will be included in the
  /// resulting document. The keys will retain the prefix in the document.
  /// Use [FlatDocumentExtensions.stripPrefix] on the result if you want to
  /// remove the prefix from the keys.
  ///
  /// Example:
  /// ```dart
  /// final env = {'APP_HOST': 'localhost', 'APP_PORT': '8080', 'OTHER': 'value'};
  /// final doc = FlatConfig.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(prefix: 'APP_'),
  /// );
  /// print(doc.toMap()); // {APP_HOST: localhost, APP_PORT: 8080}
  /// ```
  final String? prefix;

  /// When false, keys are matched case-insensitively (storage remains original).
  ///
  /// This affects prefix matching when [prefix] is set. The original case of
  /// the keys is always preserved in the resulting document.
  ///
  /// Example with case-insensitive matching:
  /// ```dart
  /// final env = {'app_host': 'localhost', 'APP_PORT': '8080'};
  /// final doc = FlatConfig.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(prefix: 'APP_', caseSensitive: false),
  /// );
  /// print(doc.toMap()); // {app_host: localhost, APP_PORT: 8080}
  /// ```
  final bool caseSensitive;

  /// Replace `${VAR}` placeholders in values using the final env view.
  ///
  /// When enabled, values can reference other variables using the `${VAR}`
  /// syntax. The interpolation happens after all defaults, env, and merge
  /// operations are applied, so any variable in the final environment can
  /// be referenced.
  ///
  /// Variables that don't exist are replaced with an empty string.
  ///
  /// Example:
  /// ```dart
  /// final env = {
  ///   'HOST': 'localhost',
  ///   'PORT': '8080',
  ///   'URL': 'http://${HOST}:${PORT}',
  /// };
  /// final doc = FlatConfig.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(interpolate: true),
  /// );
  /// print(doc['URL']); // http://localhost:8080
  /// ```
  final bool interpolate;

  /// Keep entries whose value is '' (empty string).
  ///
  /// If false, entries with empty string values are removed from the
  /// resulting document.
  ///
  /// Example:
  /// ```dart
  /// final env = {'KEY1': 'value', 'KEY2': ''};
  /// final doc1 = FlatConfig.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(keepEmptyValues: true),
  /// );
  /// print(doc1.toMap()); // {KEY1: value, KEY2: }
  ///
  /// final doc2 = FlatConfig.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(keepEmptyValues: false),
  /// );
  /// print(doc2.toMap()); // {KEY1: value}
  /// ```
  final bool keepEmptyValues;

  /// Regex used for `${VAR}` placeholder matching (first capture = var name).
  ///
  /// The regex must have at least one capture group, which will be used as
  /// the variable name to look up in the environment.
  ///
  /// Default pattern matches: `${VAR_NAME}` where VAR_NAME contains only
  /// alphanumeric characters and underscores.
  final String varPattern;

  /// Default key-values applied first (lowest precedence).
  ///
  /// These values are applied before the environment variables, so they can
  /// be overridden by actual environment values or merge values.
  ///
  /// Example:
  /// ```dart
  /// final env = {'PORT': '3000'};
  /// final doc = FlatConfig.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(
  ///     defaults: {'HOST': 'localhost', 'PORT': '8080'},
  ///   ),
  /// );
  /// print(doc.toMap()); // {HOST: localhost, PORT: 3000}
  /// ```
  final Map<String, String> defaults;

  /// Additional key-values applied last (highest precedence).
  ///
  /// These values are applied after environment variables and will override
  /// any conflicting keys from defaults or the environment.
  ///
  /// Example:
  /// ```dart
  /// final env = {'PORT': '3000'};
  /// final doc = FlatConfig.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(
  ///     merge: {'PORT': '9000'},
  ///   ),
  /// );
  /// print(doc.toMap()); // {PORT: 9000}
  /// ```
  final Map<String, String> merge;

  /// Returns a copy of these options with selectively replaced fields.
  ///
  /// Only the provided parameters will be changed; all others will remain
  /// the same as in the original options object.
  FlatEnvOptions copyWith({
    String? prefix,
    bool? caseSensitive,
    bool? interpolate,
    bool? keepEmptyValues,
    String? varPattern,
    Map<String, String>? defaults,
    Map<String, String>? merge,
  }) =>
      FlatEnvOptions(
        prefix: prefix ?? this.prefix,
        caseSensitive: caseSensitive ?? this.caseSensitive,
        interpolate: interpolate ?? this.interpolate,
        keepEmptyValues: keepEmptyValues ?? this.keepEmptyValues,
        varPattern: varPattern ?? this.varPattern,
        defaults: defaults ?? this.defaults,
        merge: merge ?? this.merge,
      );
}
