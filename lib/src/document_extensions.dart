import 'constants.dart';
import 'document.dart';
import 'options.dart';
import 'parser_utils.dart';

/// Ordering strategy for collapsing duplicate keys in a [FlatDocument].
///
/// When collapsing duplicate keys, this enum determines which position the
/// collapsed entry should occupy in the final document.
enum CollapseOrder {
  /// Keep the position of the first occurrence of a key.
  ///
  /// The collapsed entry will appear at the same position as the first
  /// occurrence of the key in the original document.
  firstOccurrence,

  /// Keep the position of the last write (last occurrence) of a key.
  ///
  /// The collapsed entry will appear at the same position as the last
  /// occurrence of the key in the original document.
  lastWrite,
}

/// Extensions for [FlatDocument] providing additional functionality.
///
/// This extension adds methods for document manipulation, encoding, and formatting
/// that are not part of the core document functionality.
extension FlatDocumentExtensions on FlatDocument {
  /// Returns a new document where duplicate keys are collapsed into at most
  /// one entry per key (latest value wins). Multi-value keys can be preserved.
  ///
  /// This method is useful for converting a document with duplicate keys into
  /// a more traditional key-value structure where each key appears only once.
  ///
  /// Parameters:
  /// - [order]: choose whether the collapsed entry stays at the first or last
  ///   occurrence position
  /// - [dropNulls]: if true, omit keys whose final collapsed value is `null`
  ///   (i.e., explicit resets are removed)
  /// - [multiValueKeys]: keys that must not be collapsed; all their entries are
  ///   preserved in-place
  /// - [isMultiValueKey]: optional predicate to dynamically mark keys as
  ///   multi-value in addition to [multiValueKeys]
  /// - [ignoreResets]: if true, ignore reset entries (key =) when collapsing
  ///
  /// Example:
  /// ```dart
  /// const config = '''
  /// background = 282c34
  /// background = ffaa00
  /// title = My App
  /// ''';
  ///
  /// final doc = FlatConfig.parse(config);
  /// final collapsed = doc.collapse();
  /// print(collapsed['background']); // ffaa00
  /// ```
  FlatDocument collapse({
    CollapseOrder order = CollapseOrder.firstOccurrence,
    bool dropNulls = false,
    Iterable<String> multiValueKeys = const [],
    bool Function(String key)? isMultiValueKey,
    bool ignoreResets = false,
  }) {
    final multiSet =
        multiValueKeys is Set<String> ? multiValueKeys : multiValueKeys.toSet();

    bool isMulti(String k) =>
        multiSet.contains(k) || (isMultiValueKey?.call(k) ?? false);

    // Pre-pass: track last value and anchor/last indices for single-value keys.
    final lastVal = <String, String?>{};
    final anchorIndex = <String, int>{};
    final lastIndex = <String, int>{};

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];

      if (isMulti(e.key)) {
        // Multi-value keys will be preserved in the second pass.
        continue;
      }

      if (ignoreResets && e.value == null) {
        // If ignoreResets is active and the entry is a "Reset" (key =),
        // then the previous value is retained and no update to null is performed.
        // Nevertheless, the position (lastIndex) is updated, so that subsequent values can correctly
        // overwrite the anchor.
        anchorIndex.putIfAbsent(e.key, () => i);
        lastIndex[e.key] = i;
        continue;
      }

      // Normal case: value (also null) is accepted.
      lastVal[e.key] = e.value;

      // Set the anchor position for the first occurrence (or keep it).
      anchorIndex.putIfAbsent(e.key, () => i);

      // Update the last occurrence.
      lastIndex[e.key] = i;
    }

    if (order == CollapseOrder.lastWrite) {
      // overwrite anchors with last occurrence indices
      for (final k in lastIndex.keys) {
        anchorIndex[k] = lastIndex[k]!;
      }
    }

    // Emit-Pass
    final out = <FlatEntry>[];
    final emitted = <String>{};

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (isMulti(e.key)) {
        // Preserve multi-value entries exactly in original order/location.
        out.add(e);
        continue;
      }

      final anchor = anchorIndex[e.key];
      if (anchor == null || emitted.contains(e.key)) {
        continue;
      }

      if (i == anchor) {
        final v = lastVal[e.key];
        if (dropNulls && v == null) {
          // skip explicit reset if requested
        } else {
          out.add(FlatEntry(e.key, v));
        }
        emitted.add(e.key);
      }
    }

    return FlatDocument(out);
  }

  /// Encodes this document into a textual configuration string.
  ///
  /// This method converts the document back to the flat configuration format,
  /// with each entry becoming a line in the format `key = value`. The encoding
  /// behavior can be customized using [options].
  ///
  /// Note: Line endings are normalized in the I/O layer, not in this method.
  ///
  /// Example:
  /// ```dart
  /// final doc = FlatConfig.fromMap({'background': '282c34', 'title': 'My App'});
  /// final text = doc.encode();
  /// print(text);
  /// // background = 282c34
  /// // title = My App
  /// ```
  String encode({
    FlatEncodeOptions options = const FlatEncodeOptions(),
  }) {
    String quoteIfNeeded(String v) {
      final hasLeadingOrTrailingWhitespace = v != v.trim();
      final containsSeparator = v.contains(Constants.pairSeparator);
      final startsWithComment = options.commentPrefix.isNotEmpty &&
          v.trimLeft().startsWith(options.commentPrefix);
      final containsDoubleQuote = v.contains(Constants.quote);
      final containsNewline =
          v.contains(Constants.newline) || v.contains(Constants.carriageReturn);

      final needsQuoting = options.alwaysQuote ||
          (options.quoteIfWhitespace && hasLeadingOrTrailingWhitespace) ||
          containsSeparator ||
          startsWithComment ||
          containsDoubleQuote ||
          containsNewline;

      if (!needsQuoting) {
        return v;
      }

      if (options.escapeQuoted) {
        final escaped = v
            .replaceAll(Constants.backslash, r'\\')
            .replaceAll(Constants.quote, r'\"');

        return '"$escaped"';
      }

      return '"$v"';
    }

    final buf = StringBuffer();
    for (final e in entries) {
      final v = e.value;
      buf.writeln(v == null ? '${e.key} = ' : '${e.key} = ${quoteIfNeeded(v)}');
    }

    return buf.toString();
  }

  /// Encodes this document and returns the result as bytes.
  ///
  /// This method first encodes the document to text using [options], then
  /// converts the text to bytes using the encoding specified in [writeOptions].
  /// Line endings are normalized according to [writeOptions.lineTerminator].
  ///
  /// Example:
  /// ```dart
  /// final doc = FlatConfig.fromMap({'background': '282c34'});
  /// final bytes = doc.encodeToBytesWithWriteOptions();
  /// await File('config.flat').writeAsBytes(bytes);
  /// ```
  List<int> encodeToBytesWithWriteOptions({
    FlatEncodeOptions options = const FlatEncodeOptions(),
    FlatStreamWriteOptions writeOptions = const FlatStreamWriteOptions(),
  }) {
    final text = encode(options: options);
    final normalized = normalizeLineEndings(
      text,
      lineTerminator: writeOptions.lineTerminator,
      ensureTrailingNewline: writeOptions.ensureTrailingNewline,
    );

    return writeOptions.encoding.encode(normalized);
  }

  /// Merges another document into this one.
  ///
  /// This method combines the entries from [other] with the entries from this
  /// document. The [override] parameter controls how duplicate keys are handled.
  ///
  /// Parameters:
  /// - [other]: the document to merge into this one
  /// - [override]: if true, existing entries are overridden by the new ones;
  ///   if false, existing entries take precedence
  ///
  /// Example:
  /// ```dart
  /// final doc1 = FlatConfig.fromMap({'background': '282c34', 'title': 'App'});
  /// final doc2 = FlatConfig.fromMap({'background': 'ffaa00', 'debug': 'true'});
  /// final merged = doc1.merge(doc2);
  /// print(merged['background']); // ffaa00 (overridden)
  /// print(merged['title']); // App (preserved)
  /// print(merged['debug']); // true (added)
  /// ```
  FlatDocument merge(FlatDocument other, {bool override = true}) {
    final combined = <FlatEntry>[...entries];
    final seen = {...keys};
    for (final e in other) {
      if (override || !seen.contains(e.key)) {
        combined.add(e);
        seen.add(e.key);
      }
    }

    return FlatDocument(combined);
  }

  /// Creates a human-friendly dump of entries in insertion order.
  ///
  /// This method is useful for debugging and understanding the structure of
  /// a configuration document. It shows each entry with its index and value.
  ///
  /// Parameters:
  /// - [includeIndexes]: if true, each line is prefixed with its index in brackets
  ///
  /// Example output (includeIndexes=true):
  /// ```
  /// [0] background = 282c34
  /// [1] title = My App
  /// [2] debug = null
  /// ```
  ///
  /// When [includeIndexes] is false, the index prefix is omitted.
  String debugDump({bool includeIndexes = true}) {
    final buf = StringBuffer();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (includeIndexes) {
        buf.write('[');
        buf.write(i);
        buf.write('] ');
      }
      buf
        ..write(e.key)
        ..write(' = ')
        ..write(e.value ?? 'null');
      if (i + 1 < entries.length) {
        buf.writeln();
      }
    }

    return buf.toString();
  }

  /// Pretty printer with optional sorting and column alignment.
  ///
  /// This method formats the document for human-readable output with various
  /// formatting options to improve readability.
  ///
  /// Parameters:
  /// - [includeIndexes]: if true, lines are prefixed with "[i] " showing their index
  /// - [sortByKey]: if true, lines are ordered by key (stable sort on index)
  /// - [alignColumns]: if true, keys are padded so the '=' signs align in columns
  ///
  /// Example output (sortByKey=true, alignColumns=true):
  /// ```
  /// [0] background = 282c34
  /// [1] debug      = true
  /// [2] title      = My App
  /// ```
  String toPrettyString({
    bool includeIndexes = true,
    bool sortByKey = false,
    bool alignColumns = false,
  }) {
    final items = <(int, String, String?)>[];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      items.add((i, e.key, e.value));
    }

    if (sortByKey) {
      items.sort((a, b) {
        final c = a.$2.compareTo(b.$2);
        if (c != 0) {
          return c;
        }

        return a.$1.compareTo(b.$1);
      });
    }

    var maxKeyLen = 0;
    if (alignColumns) {
      for (final it in items) {
        if (it.$2.length > maxKeyLen) {
          maxKeyLen = it.$2.length;
        }
      }
    }

    final buf = StringBuffer();
    for (var idx = 0; idx < items.length; idx++) {
      final (i, key, value) = items[idx];
      if (includeIndexes) {
        buf
          ..write('[')
          ..write(i)
          ..write('] ');
      }
      if (alignColumns) {
        buf
          ..write(key)
          ..write(' ' * (maxKeyLen - key.length))
          ..write(' = ');
      } else {
        buf
          ..write(key)
          ..write(' = ');
      }
      buf.write(value ?? 'null');
      if (idx + 1 < items.length) {
        buf.writeln();
      }
    }

    return buf.toString();
  }
}
