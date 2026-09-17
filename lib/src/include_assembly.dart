// Assembling a document from a parsed unit and the entries its includes
// produced. The order this ends up in is the whole semantics of an include,
// so it lives in one place rather than in each parse path.

import 'document.dart';
import 'include_path_utils.dart';
import 'options.dart';

/// What a document's own entries and its includes' entries were found to be.
///
/// [includeTargets] is in document order and one per directive that names
/// something, which is what lets a resolved group be matched back to the
/// directive it came from.
final class CollectedIncludes {
  /// Creates a collection result.
  const CollectedIncludes({
    required this.includeTargets,
    required this.preIncludeEntries,
    required this.postIncludeEntries,
  });

  /// The include values found in the document, in order.
  final List<String> includeTargets;

  /// Entries that appeared before the first directive.
  final List<FlatEntry> preIncludeEntries;

  /// Entries that appeared after the first directive.
  final List<FlatEntry> postIncludeEntries;
}

/// The target [entry] names, or `null` when it is not an include directive.
///
/// A line that uses the include key but names nothing — `config-file =`,
/// `config-file = ?`, `config-file = ""`, `config-file = ?""` — is not a
/// directive. It asks no resolver anything, and it must not act as the
/// boundary the tail is measured from either, or a line that does nothing
/// would change what the document means.
String? _directiveTarget(FlatEntry entry, FlatIncludeOptions options) {
  if (entry.key != options.includeKey) {
    return null;
  }

  final raw = entry.value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  // Only emptiness is asked here, and no decoding can turn a non-empty path
  // into an empty one, so the parse options need not reach this far.
  return processIncludePath(raw).isEmpty ? null : raw;
}

/// Splits [doc] into its include targets and the entries around them.
///
/// One pass, because the two halves have to agree on where the first directive
/// is. Deciding that twice is what let an empty directive start the tail
/// without ending the head, which duplicated every entry after it.
CollectedIncludes collectIncludes(
  FlatDocument doc,
  FlatIncludeOptions options,
) {
  final includeTargets = <String>[];
  final preIncludeEntries = <FlatEntry>[];
  final postIncludeEntries = <FlatEntry>[];

  for (final entry in doc.entries) {
    if (entry.key == options.includeKey) {
      // A directive line never survives as an entry, whether it names
      // something or not.
      final target = _directiveTarget(entry, options);
      if (target != null) {
        includeTargets.add(target);
      }
      continue;
    }

    if (includeTargets.isEmpty) {
      preIncludeEntries.add(entry);
    } else {
      postIncludeEntries.add(entry);
    }
  }

  return CollectedIncludes(
    includeTargets: includeTargets,
    preIncludeEntries: preIncludeEntries,
    postIncludeEntries: postIncludeEntries,
  );
}

/// Builds the final document from [doc] and the entries its includes produced.
///
/// [groups] holds one list per entry of [CollectedIncludes.includeTargets], in
/// the same order, empty where an optional include was missing. Keeping them
/// grouped rather than flattened is what allows
/// [IncludeMergePolicy.lastWins] to put each group back where its directive
/// was.
FlatDocument assembleIncludedDocument(
  FlatDocument doc,
  FlatIncludeOptions options,
  List<List<FlatEntry>> groups,
) => switch (options.mergePolicy) {
  IncludeMergePolicy.ghostty => _assembleGhostty(doc, options, groups),
  IncludeMergePolicy.lastWins => _assembleLastWins(doc, options, groups),
};

/// Pre-include entries, then every included entry, then the tail.
///
/// The tail drops any key an include set, which is the part that surprises
/// people: in this policy a line below an include does not override it.
FlatDocument _assembleGhostty(
  FlatDocument doc,
  FlatIncludeOptions options,
  List<List<FlatEntry>> groups,
) {
  final collected = collectIncludes(doc, options);
  final includeEntries = [for (final group in groups) ...group];
  final keysFromIncludes = {for (final entry in includeEntries) entry.key};

  return FlatDocument([
    ...collected.preIncludeEntries,
    ...includeEntries,
    ...collected.postIncludeEntries.where(
      (entry) => !keysFromIncludes.contains(entry.key),
    ),
  ]);
}

/// Each include expands where it was written, and later entries win.
///
/// What most formats do, and what someone writing a line below an include
/// expects it to do.
FlatDocument _assembleLastWins(
  FlatDocument doc,
  FlatIncludeOptions options,
  List<List<FlatEntry>> groups,
) {
  final entries = <FlatEntry>[];
  var nextGroup = 0;

  for (final entry in doc.entries) {
    if (entry.key != options.includeKey) {
      entries.add(entry);
      continue;
    }

    if (_directiveTarget(entry, options) != null && nextGroup < groups.length) {
      entries.addAll(groups[nextGroup++]);
    }
  }

  return FlatDocument(entries);
}
