// Assembling a document from a parsed unit and the entries its includes
// produced. The order this ends up in is the whole semantics of an include,
// so it lives in one place rather than in each parse path.

import 'document.dart';
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
    required this.seenAnyInclude,
  });

  /// The include values found in the document, in order.
  final List<String> includeTargets;

  /// Entries that appeared before the first include directive.
  final List<FlatEntry> preIncludeEntries;

  /// Whether any include directive named something.
  final bool seenAnyInclude;
}

/// Collects include targets and the entries preceding the first directive.
CollectedIncludes collectIncludes(
  FlatDocument doc,
  FlatIncludeOptions options,
) {
  final includeTargets = <String>[];
  final preIncludeEntries = <FlatEntry>[];
  var seenAnyInclude = false;

  for (final entry in doc.entries) {
    if (entry.key != options.includeKey) {
      if (!seenAnyInclude) {
        preIncludeEntries.add(entry);
      }
      continue;
    }

    final target = entry.value?.trim();
    if (target == null || target.isEmpty) {
      continue;
    }

    includeTargets.add(target);
    seenAnyInclude = true;
  }

  return CollectedIncludes(
    includeTargets: includeTargets,
    preIncludeEntries: preIncludeEntries,
    seenAnyInclude: seenAnyInclude,
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
  final includeEntries = [for (final group in groups) ...group];
  final keysFromIncludes = {for (final entry in includeEntries) entry.key};

  return FlatDocument([
    ...collectIncludes(doc, options).preIncludeEntries,
    ...includeEntries,
    ..._tailEntries(doc, options, keysFromIncludes),
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

    final target = entry.value?.trim();
    if (target == null || target.isEmpty) {
      continue;
    }

    if (nextGroup < groups.length) {
      entries.addAll(groups[nextGroup++]);
    }
  }

  return FlatDocument(entries);
}

/// Entries after the first include directive that no include already set.
List<FlatEntry> _tailEntries(
  FlatDocument doc,
  FlatIncludeOptions options,
  Set<String> keysFromIncludes,
) {
  final tail = <FlatEntry>[];
  var afterFirstInclude = false;

  for (final entry in doc.entries) {
    if (entry.key == options.includeKey) {
      afterFirstInclude = true;
      continue;
    }

    if (!afterFirstInclude || keysFromIncludes.contains(entry.key)) {
      continue;
    }

    tail.add(entry);
  }

  return tail;
}
