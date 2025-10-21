// Shared utilities for processing documents according to Ghostty semantics.

import 'document.dart';
import 'options.dart';

/// Result of processing a document according to Ghostty semantics.
class GhosttyProcessedDocument {
  /// Creates a processed document result.
  GhosttyProcessedDocument({
    required this.includeValues,
    required this.preIncludeEntries,
    required this.filteredTailEntries,
    required this.seenAnyInclude,
  });

  /// The list of include values found in the document (in order).
  final List<String> includeValues;

  /// Entries that appeared before the first include directive.
  final List<FlatEntry> preIncludeEntries;

  /// Entries that appeared after include directives,
  /// filtered to exclude any keys that will be set by includes.
  final List<FlatEntry> filteredTailEntries;

  /// Whether any include directives were found.
  final bool seenAnyInclude;
}

/// Result of the initial Ghostty semantics collection pass.
class GhosttyCollectedDocument {
  /// Creates a collected document result.
  GhosttyCollectedDocument({
    required this.includeValues,
    required this.preIncludeEntries,
    required this.seenAnyInclude,
  });

  /// The list of include values found in the document (in order).
  final List<String> includeValues;

  /// Entries that appeared before the first include directive.
  final List<FlatEntry> preIncludeEntries;

  /// Whether any include directives were found.
  final bool seenAnyInclude;
}

/// Collects include values and entries before the first include.
GhosttyCollectedDocument collectIncludesAndPreEntries(
  FlatDocument doc,
  FlatParseOptions options,
) {
  final includeValues = <String>[];
  final preIncludeEntries = <FlatEntry>[];
  var seenAnyInclude = false;

  for (final e in doc.entries) {
    if (e.key == options.includeKey) {
      if (e.value != null) {
        final trimmedValue = e.value!.trim();
        if (trimmedValue.isNotEmpty) {
          includeValues.add(trimmedValue);
          seenAnyInclude = true;
        }
      }
      continue;
    }
    if (!seenAnyInclude) {
      preIncludeEntries.add(e);
    }
  }

  return GhosttyCollectedDocument(
    includeValues: includeValues,
    preIncludeEntries: preIncludeEntries,
    seenAnyInclude: seenAnyInclude,
  );
}

/// Filters the tail (post-include) entries so they don't override include keys.
List<FlatEntry> filterTailEntries(
  FlatDocument doc,
  FlatParseOptions options,
  Set<String> keysFromIncludes,
) {
  final filteredTail = <FlatEntry>[];

  var afterFirstInclude = false;
  for (final e in doc.entries) {
    if (e.key == options.includeKey) {
      afterFirstInclude = true;
      continue; // skip include directives entirely
    }
    if (!afterFirstInclude) {
      continue; // we only consider the tail
    }
    if (keysFromIncludes.contains(e.key)) {
      continue; // must not override
    }
    filteredTail.add(e);
  }

  return filteredTail;
}

/// Processes a parsed document according to Ghostty semantics.
///
/// Ghostty semantics dictate:
/// 1. Collect all include directives and entries before the first include
/// 2. Entries after the first include must not override keys set by includes
///
/// This function extracts:
/// - Include values (paths/ids to be resolved)
/// - Pre-include entries (entries before first include directive)
/// - Later entries after includes (requires [keysFromIncludes] to filter)
///
/// Returns a [GhosttyProcessedDocument] with the processed information.
GhosttyProcessedDocument processDocumentWithGhosttySemantics(
  FlatDocument doc,
  FlatParseOptions options,
  Set<String> keysFromIncludes,
) {
  final collected = collectIncludesAndPreEntries(doc, options);
  final filteredTail = collected.seenAnyInclude
      ? filterTailEntries(doc, options, keysFromIncludes)
      : const <FlatEntry>[];

  return GhosttyProcessedDocument(
    includeValues: collected.includeValues,
    preIncludeEntries: collected.preIncludeEntries,
    filteredTailEntries: filteredTail,
    seenAnyInclude: collected.seenAnyInclude,
  );
}

/// Builds the final document according to Ghostty semantics.
///
/// The final order is:
/// 1. All entries **before** first include directive
/// 2. Then **all include entries**
/// 3. Then the filtered tail entries (that do not override any key from includes)
FlatDocument buildGhosttyDocument(
  List<FlatEntry> preIncludeEntries,
  List<FlatEntry> includeEntries,
  List<FlatEntry> filteredTailEntries,
) =>
    FlatDocument([
      ...preIncludeEntries,
      ...includeEntries,
      ...filteredTailEntries,
    ]);
