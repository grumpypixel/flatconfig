import 'dart:convert';

import 'constants.dart';
import 'issue.dart';
import 'validation.dart';

/// Callback function invoked when a parsing error occurs.
///
/// The [lineNumber] parameter indicates the 1-based line number where the error
/// occurred, and [line] contains the raw line content that caused the error.
// Issue reporting lives in issue.dart; see FlatIssue and OnIssue.

/// Marks a `copyWith` parameter as "not passed".
///
/// `field ?? this.field` cannot tell `null` from absent, so a nullable field
/// could be set but never cleared. Nullable `copyWith` parameters take this as
/// their default and are compared with [identical].
const Object _unset = #unset;

/// The [OnIssue]-typed counterpart of [_unset].
///
/// A handler parameter has to keep its function type, or the lambda a caller
/// writes at the call site loses its inferred argument type.
void _unsetOnIssue(FlatIssue issue) {}

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
    this.onIssue,
  });

  /// Prefix used to mark comment lines.
  ///
  /// Lines that start with this prefix (after trimming) are ignored during
  /// parsing. Empty means the format has no comments, so every line is data.
  /// A prefix containing a line break is rejected when parsing starts.
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

  /// Called for each problem found while parsing, when [strict] is false.
  ///
  /// One handler covers every [FlatIssueKind], so a new kind of problem becomes
  /// additive rather than another callback on this class. If null, unparseable
  /// lines are skipped silently.
  ///
  /// ```dart
  /// FlatParseOptions(
  ///   onIssue: (i) => stderr.writeln('${i.line}: ${i.message}'),
  /// )
  /// ```
  final OnIssue? onIssue;

  /// Returns a copy of these options with selectively replaced fields.
  ///
  /// Only the provided parameters will be changed; all others will remain
  /// the same as in the original options object.
  /// Pass [onIssue] as `null` to clear it; omitting it keeps the current one.
  FlatParseOptions copyWith({
    String? commentPrefix,
    bool? decodeEscapesInQuoted,
    bool? strict,
    OnIssue? onIssue = _unsetOnIssue,
  }) => FlatParseOptions(
    commentPrefix: commentPrefix ?? this.commentPrefix,
    decodeEscapesInQuoted: decodeEscapesInQuoted ?? this.decodeEscapesInQuoted,
    strict: strict ?? this.strict,
    onIssue: identical(onIssue, _unsetOnIssue) ? this.onIssue : onIssue,
  );

  @override
  String toString() =>
      'FlatParseOptions(commentPrefix: $commentPrefix, '
      'decodeEscapesInQuoted: $decodeEscapesInQuoted, strict: $strict, '
      'onIssue: ${onIssue == null ? 'none' : 'set'})';

  @override
  bool operator ==(Object other) =>
      other is FlatParseOptions &&
      other.commentPrefix == commentPrefix &&
      other.decodeEscapesInQuoted == decodeEscapesInQuoted &&
      other.strict == strict &&
      other.onIssue == onIssue;

  @override
  int get hashCode =>
      Object.hash(commentPrefix, decodeEscapesInQuoted, strict, onIssue);
}

/// Where an include's entries land, and what may override them.
enum IncludeMergePolicy {
  /// Every include's entries come after the including file's own, and a line
  /// below an include cannot override a key the include set.
  ///
  /// The default, and what Ghostty does. Surprising if you have not met it:
  /// writing `theme = light` under `config-file = dark.conf` has no effect.
  ghostty,

  /// Each include expands where it is written, and later entries win.
  ///
  /// What most formats do, and what the line below an include usually looks
  /// like it should do.
  lastWins,
}

/// Options that control how include directives are followed.
///
/// Separate from [FlatParseOptions] because parsing one string never follows an
/// include: only the entry points that take a resolver or a filesystem path do.
/// Passing these two fields to [FlatDocument.parse] suggested otherwise.
class FlatIncludeOptions {
  /// Creates include options with the specified configuration.
  const FlatIncludeOptions({
    this.includeKey = Constants.includeKey,
    this.maxIncludeDepth = 64,
    this.maxIncludes = 256,
    this.maxIncludedEntries = 100000,
    this.mergePolicy = IncludeMergePolicy.ghostty,
  }) : assert(maxIncludeDepth >= 0, 'maxIncludeDepth must not be negative'),
       assert(maxIncludes >= 0, 'maxIncludes must not be negative'),
       assert(
         maxIncludedEntries >= 0,
         'maxIncludedEntries must not be negative',
       );

  /// Key used to identify include directives in configuration files.
  ///
  /// Lines with this key are treated as include directives; the value is the
  /// path of another configuration file. Defaults to [Constants.includeKey]
  /// (`config-file`) for Ghostty compatibility.
  ///
  /// ```dart
  /// // With the default includeKey
  /// config-file = theme.conf
  ///
  /// // With includeKey: 'include'
  /// include = theme.conf
  /// ```
  final String includeKey;

  /// Maximum recursion depth for processing includes.
  ///
  /// This defensive limit prevents pathological include graphs from causing
  /// unbounded recursion in cases where canonicalization fails or the graph
  /// is extremely deep. Zero disallows includes entirely: a document that has
  /// one raises `MaxIncludeDepthExceededException`. Defaults to 64.
  final int maxIncludeDepth;

  /// Maximum number of include directives one traversal may follow.
  ///
  /// Bounds the work of reaching documents: for a resolver backed by a
  /// network or a database, this is the number of requests a single parse can
  /// make. Counts every directive followed, including repeats of a target the
  /// traversal has already read.
  ///
  /// Exceeding it raises `IncludeBudgetExceededException`. Defaults to 256.
  final int maxIncludes;

  /// Maximum number of entries all of a traversal's includes may contribute.
  ///
  /// Bounds the size of the result, which is the half that can run away.
  /// Depth limits how far an include graph reaches and [maxIncludes] how often
  /// it is followed, but neither limits how much the graph *amounts to*: a
  /// document whose includes each pull in the previous one twice doubles per
  /// level, and because a repeated unit is parsed once and then copied into
  /// every parent that names it, sixteen such levels stay at 32 directives
  /// while reaching 65,536 entries — from under a kilobyte of source, well
  /// inside the default depth.
  ///
  /// Entries of the including document itself do not count. Exceeding it
  /// raises `IncludeBudgetExceededException`. Defaults to 100,000.
  final int maxIncludedEntries;

  /// Where an include's entries land, and what may override them.
  ///
  /// Defaults to [IncludeMergePolicy.ghostty], which is what this package has
  /// always done; it is a setting now rather than the only behaviour.
  final IncludeMergePolicy mergePolicy;

  /// Returns a copy of these options with selectively replaced fields.
  FlatIncludeOptions copyWith({
    String? includeKey,
    int? maxIncludeDepth,
    int? maxIncludes,
    int? maxIncludedEntries,
    IncludeMergePolicy? mergePolicy,
  }) => FlatIncludeOptions(
    includeKey: includeKey ?? this.includeKey,
    maxIncludeDepth: maxIncludeDepth ?? this.maxIncludeDepth,
    maxIncludes: maxIncludes ?? this.maxIncludes,
    maxIncludedEntries: maxIncludedEntries ?? this.maxIncludedEntries,
    mergePolicy: mergePolicy ?? this.mergePolicy,
  );

  @override
  String toString() =>
      'FlatIncludeOptions(includeKey: $includeKey, '
      'maxIncludeDepth: $maxIncludeDepth, maxIncludes: $maxIncludes, '
      'maxIncludedEntries: $maxIncludedEntries, '
      'mergePolicy: ${mergePolicy.name})';

  @override
  bool operator ==(Object other) =>
      other is FlatIncludeOptions &&
      other.includeKey == includeKey &&
      other.maxIncludeDepth == maxIncludeDepth &&
      other.maxIncludes == maxIncludes &&
      other.maxIncludedEntries == maxIncludedEntries &&
      other.mergePolicy == mergePolicy;

  @override
  int get hashCode => Object.hash(
    includeKey,
    maxIncludeDepth,
    maxIncludes,
    maxIncludedEntries,
    mergePolicy,
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
  }) => FlatStreamReadOptions(
    encoding: encoding ?? this.encoding,
    lineSplitter: lineSplitter ?? this.lineSplitter,
  );

  @override
  String toString() => 'FlatStreamReadOptions(encoding: ${encoding.name})';

  @override
  bool operator ==(Object other) =>
      other is FlatStreamReadOptions &&
      other.encoding == encoding &&
      other.lineSplitter == lineSplitter;

  @override
  int get hashCode => Object.hash(encoding, lineSplitter);
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
  }) : assert(lineTerminator.length > 0, 'lineTerminator must not be empty');

  /// Text encoding used when writing the file.
  ///
  /// Defaults to UTF-8, which is the most common encoding for text files.
  final Encoding encoding;

  /// Line terminator to use when writing lines.
  ///
  /// Defaults to `\n` (Unix-style line endings). You can use `\r\n` for
  /// Windows-style line endings or `\r` for classic Mac-style line endings.
  final String lineTerminator;

  /// Returns a copy of these options with selectively replaced fields.
  ///
  /// Only the provided parameters will be changed; all others will remain
  /// the same as in the original options object.
  FlatStreamWriteOptions copyWith({
    Encoding? encoding,
    String? lineTerminator,
  }) => FlatStreamWriteOptions(
    encoding: encoding ?? this.encoding,
    lineTerminator: lineTerminator ?? this.lineTerminator,
  );

  @override
  String toString() =>
      'FlatStreamWriteOptions(encoding: ${encoding.name}, '
      'lineTerminator: ${jsonEncode(lineTerminator)})';

  @override
  bool operator ==(Object other) =>
      other is FlatStreamWriteOptions &&
      other.encoding == encoding &&
      other.lineTerminator == lineTerminator;

  @override
  int get hashCode => Object.hash(encoding, lineTerminator);
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
  }) => FlatEncodeOptions(
    escapeQuoted: escapeQuoted ?? this.escapeQuoted,
    quoteIfWhitespace: quoteIfWhitespace ?? this.quoteIfWhitespace,
    alwaysQuote: alwaysQuote ?? this.alwaysQuote,
    commentPrefix: commentPrefix ?? this.commentPrefix,
  );

  @override
  String toString() =>
      'FlatEncodeOptions(escapeQuoted: $escapeQuoted, '
      'quoteIfWhitespace: $quoteIfWhitespace, alwaysQuote: $alwaysQuote, '
      'commentPrefix: $commentPrefix)';

  @override
  bool operator ==(Object other) =>
      other is FlatEncodeOptions &&
      other.escapeQuoted == escapeQuoted &&
      other.quoteIfWhitespace == quoteIfWhitespace &&
      other.alwaysQuote == alwaysQuote &&
      other.commentPrefix == commentPrefix;

  @override
  int get hashCode =>
      Object.hash(escapeQuoted, quoteIfWhitespace, alwaysQuote, commentPrefix);
}

/// What interpolation does with a `${VAR}` that names nothing.
enum MissingVariablePolicy {
  /// Leave the placeholder in the value, spelled exactly as it was written.
  ///
  /// The default. A typo stays visible instead of turning `https://${HOST}/api`
  /// into `https:///api`, which looks like a URL and fails much later.
  preserve,

  /// Replace it with the empty string, the way a POSIX shell does.
  empty,

  /// Throw an [ArgumentError] naming the variable.
  error,
}

/// What to do with an environment variable whose value contains a line break.
///
/// No document can hold one (`SPEC.md` §4), so the value cannot be kept either
/// way. The choice is whether to fail or to carry on without it.
enum MultilineValuePolicy {
  /// Throw an [ArgumentError] naming the variable. The default.
  error,

  /// Drop the variable and keep the rest.
  ///
  /// For a process whose environment happens to carry something like a PEM key
  /// it should not be reading anyway, and which should not be stopped by it.
  skip,
}

/// Options for loading environment variables into a FlatDocument.
///
/// These options control how environment-like maps are processed when using
/// [FlatDocument.fromEnvironment], including prefix filtering, interpolation,
/// and precedence handling. Pure in-memory; no dart:io required.
class FlatEnvOptions {
  /// Creates a new [FlatEnvOptions] with the specified configuration.
  ///
  /// All parameters are optional and have sensible defaults for typical
  /// environment variable loading scenarios.
  ///
  /// Unlike the other options classes this one is not `const`: it holds two
  /// maps, and a `const` constructor cannot copy them. Keeping the caller's
  /// maps would mean a later `defaults['X'] = 'y'` silently changed how an
  /// already-built options object behaves.
  FlatEnvOptions({
    String? prefix,
    this.caseSensitive = true,
    this.interpolate = false,
    this.missingVariable = MissingVariablePolicy.preserve,
    this.multilineValue = MultilineValuePolicy.error,
    this.keepEmptyValues = true,
    this.varPattern = defaultVarPattern,
    this.stripMatchedPrefix = false,
    this.keySplitOn,
    this.keyJoinWith,
    this.lowercaseKeys = false,
    Map<String, String> defaults = const {},
    Map<String, String> merge = const {},
  }) : // An empty prefix filters nothing, which is what a null prefix means.
       // Normalising here leaves one spelling of "no prefix" instead of two.
       prefix = (prefix?.isEmpty ?? true) ? null : prefix,
       defaults = Map.unmodifiable(defaults),
       merge = Map.unmodifiable(merge) {
    if (stripMatchedPrefix && this.prefix == null) {
      throw ArgumentError.value(
        stripMatchedPrefix,
        'stripMatchedPrefix',
        'needs a prefix to strip',
      );
    }

    if (keySplitOn != null && keySplitOn!.isEmpty) {
      throw ArgumentError.value(keySplitOn, 'keySplitOn', 'must not be empty');
    }

    if (keyJoinWith != null && keySplitOn == null) {
      throw ArgumentError.value(
        keyJoinWith,
        'keyJoinWith',
        'has nothing to join without keySplitOn',
      );
    }

    // A key rewritten into something the format cannot hold would only be
    // caught by FlatEntry, one layer away from the setting that caused it.
    final joiner = keyJoinWith;
    if (joiner != null) {
      final reason = invalidKeyReason(joiner);
      if (reason != null && joiner.isNotEmpty) {
        throw ArgumentError.value(joiner, 'keyJoinWith', reason);
      }
    }

    try {
      RegExp(varPattern);
    } on FormatException catch (e) {
      throw ArgumentError.value(varPattern, 'varPattern', 'is not a regex: $e');
    }

    // Interpolation reads group 1 as the variable name, so a pattern without
    // one could never name a variable. Rejected whether or not [interpolate]
    // is set: an unusable pattern is a mistake either way, and turning
    // interpolation on later should not be what surfaces it.
    if (!varPattern.contains('(')) {
      throw ArgumentError.value(
        varPattern,
        'varPattern',
        'must have a capture group naming the variable',
      );
    }
  }

  /// The default `${VAR}` placeholder pattern.
  static const String defaultVarPattern = r'\$\{([A-Za-z0-9_]+)\}';

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
  /// final doc = FlatDocument.fromEnvironment(
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
  /// final doc = FlatDocument.fromEnvironment(
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
  /// be referenced. It runs before any key transformation, so a placeholder
  /// names an environment variable and not a rewritten key.
  ///
  /// Defaults to false. A variable's value is data the program did not write,
  /// and a `$` in it is far more often a password than a reference.
  ///
  /// [missingVariable] decides what a placeholder naming nothing becomes.
  ///
  /// Example:
  /// ```dart
  /// final env = {
  ///   'HOST': 'localhost',
  ///   'PORT': '8080',
  ///   'URL': 'http://${HOST}:${PORT}',
  /// };
  /// final doc = FlatDocument.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(interpolate: true),
  /// );
  /// print(doc['URL']); // http://localhost:8080
  /// ```
  final bool interpolate;

  /// What a `${VAR}` naming nothing becomes. Only read when [interpolate].
  ///
  /// Defaults to [MissingVariablePolicy.preserve].
  final MissingVariablePolicy missingVariable;

  /// What to do with a value containing a line break.
  ///
  /// Defaults to [MultilineValuePolicy.error].
  final MultilineValuePolicy multilineValue;

  /// Keep entries whose value is '' (empty string).
  ///
  /// If false, entries with empty string values are removed from the
  /// resulting document.
  ///
  /// Example:
  /// ```dart
  /// final env = {'KEY1': 'value', 'KEY2': ''};
  /// final doc1 = FlatDocument.fromEnvironment(
  ///   env,
  ///   options: FlatEnvOptions(keepEmptyValues: true),
  /// );
  /// print(doc1.toMap()); // {KEY1: value, KEY2: }
  ///
  /// final doc2 = FlatDocument.fromEnvironment(
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

  /// Remove [prefix] from each key that matched it.
  ///
  /// The three key settings run in order — strip, split and join, lowercase —
  /// and all of them run after interpolation. Together they turn a screaming
  /// environment into ordinary configuration keys:
  ///
  /// ```dart
  /// FlatEnvOptions(
  ///   prefix: 'APP_',
  ///   stripMatchedPrefix: true,
  ///   keySplitOn: '_',
  ///   keyJoinWith: '.',
  ///   lowercaseKeys: true,
  /// );
  /// // APP_WINDOW_WIDTH -> window.width
  /// ```
  ///
  /// Requires [prefix]. Keys from [defaults] and [merge] are transformed too:
  /// they are settings for the same document, and leaving them untouched would
  /// mean a default could not override the variable it is a default for.
  final bool stripMatchedPrefix;

  /// Separator the key is split on before being rejoined with [keyJoinWith].
  ///
  /// Null leaves the key as it is.
  final String? keySplitOn;

  /// Separator the split key parts are rejoined with.
  ///
  /// Defaults to [Constants.keySeparator] when [keySplitOn] is set. Setting it
  /// without [keySplitOn] is an error rather than a no-op.
  final String? keyJoinWith;

  /// Lowercase every key, after stripping and rejoining.
  ///
  /// Two keys can collide once case stops distinguishing them; the later one
  /// wins, as it would anywhere else in a document.
  final bool lowercaseKeys;

  /// Default key-values applied first (lowest precedence).
  ///
  /// These values are applied before the environment variables, so they can
  /// be overridden by actual environment values or merge values.
  ///
  /// Example:
  /// ```dart
  /// final env = {'PORT': '3000'};
  /// final doc = FlatDocument.fromEnvironment(
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
  /// final doc = FlatDocument.fromEnvironment(
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
  /// Pass [prefix] as `null` to clear it; omitting it keeps the current one.
  /// Pass [prefix], [keySplitOn] or [keyJoinWith] as `null` to clear one;
  /// omitting it keeps the current value.
  FlatEnvOptions copyWith({
    Object? prefix = _unset,
    bool? caseSensitive,
    bool? interpolate,
    MissingVariablePolicy? missingVariable,
    MultilineValuePolicy? multilineValue,
    bool? keepEmptyValues,
    String? varPattern,
    bool? stripMatchedPrefix,
    Object? keySplitOn = _unset,
    Object? keyJoinWith = _unset,
    bool? lowercaseKeys,
    Map<String, String>? defaults,
    Map<String, String>? merge,
  }) => FlatEnvOptions(
    prefix: identical(prefix, _unset) ? this.prefix : prefix as String?,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    interpolate: interpolate ?? this.interpolate,
    missingVariable: missingVariable ?? this.missingVariable,
    multilineValue: multilineValue ?? this.multilineValue,
    keepEmptyValues: keepEmptyValues ?? this.keepEmptyValues,
    varPattern: varPattern ?? this.varPattern,
    stripMatchedPrefix: stripMatchedPrefix ?? this.stripMatchedPrefix,
    keySplitOn: identical(keySplitOn, _unset)
        ? this.keySplitOn
        : keySplitOn as String?,
    keyJoinWith: identical(keyJoinWith, _unset)
        ? this.keyJoinWith
        : keyJoinWith as String?,
    lowercaseKeys: lowercaseKeys ?? this.lowercaseKeys,
    defaults: defaults ?? this.defaults,
    merge: merge ?? this.merge,
  );

  @override
  String toString() =>
      'FlatEnvOptions(prefix: $prefix, caseSensitive: $caseSensitive, '
      'interpolate: $interpolate, missingVariable: ${missingVariable.name}, '
      'multilineValue: ${multilineValue.name}, '
      'keepEmptyValues: $keepEmptyValues, varPattern: $varPattern, '
      'stripMatchedPrefix: $stripMatchedPrefix, keySplitOn: $keySplitOn, '
      'keyJoinWith: $keyJoinWith, lowercaseKeys: $lowercaseKeys, '
      'defaults: ${defaults.length} entries, '
      'merge: ${merge.length} entries)';

  @override
  bool operator ==(Object other) =>
      other is FlatEnvOptions &&
      other.prefix == prefix &&
      other.caseSensitive == caseSensitive &&
      other.interpolate == interpolate &&
      other.missingVariable == missingVariable &&
      other.multilineValue == multilineValue &&
      other.keepEmptyValues == keepEmptyValues &&
      other.varPattern == varPattern &&
      other.stripMatchedPrefix == stripMatchedPrefix &&
      other.keySplitOn == keySplitOn &&
      other.keyJoinWith == keyJoinWith &&
      other.lowercaseKeys == lowercaseKeys &&
      _sameEntries(other.defaults, defaults) &&
      _sameEntries(other.merge, merge);

  @override
  int get hashCode => Object.hash(
    prefix,
    caseSensitive,
    interpolate,
    missingVariable,
    multilineValue,
    keepEmptyValues,
    varPattern,
    stripMatchedPrefix,
    keySplitOn,
    keyJoinWith,
    lowercaseKeys,
    _entriesHash(defaults),
    _entriesHash(merge),
  );
}

bool _sameEntries(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) {
    return false;
  }

  for (final e in a.entries) {
    if (b[e.key] != e.value) {
      return false;
    }
  }

  return true;
}

int _entriesHash(Map<String, String> m) {
  // Order-independent, so two options built from differently ordered maps
  // that compare equal also hash equal.
  var h = 0;
  for (final e in m.entries) {
    h ^= Object.hash(e.key, e.value);
  }

  return Object.hash(h, m.length);
}
