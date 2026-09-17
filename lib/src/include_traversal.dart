import 'package:meta/meta.dart';

import 'document.dart';
import 'exceptions.dart';
import 'options.dart';
import 'validation.dart';

/// The state of a single include traversal: the options every unit is read
/// with, the units currently on the stack, and the units already finished.
///
/// One of these exists per call and is never shared between calls. Finished
/// units are keyed by id alone, and an id only identifies a result while the
/// content behind it, the options and the resolver all stay fixed. That holds
/// within one traversal and nowhere else, which is why there is no way to hand
/// a traversal to a second call.
@internal
final class IncludeTraversal {
  /// Creates a traversal that reads every unit with the given options.
  ///
  /// Throws [ArgumentError] if any of the traversal limits is negative.
  IncludeTraversal({
    required this.options,
    required this.includeOptions,
    required this.readOptions,
  }) {
    checkIncludeDepth(includeOptions.maxIncludeDepth);
    checkIncludeBudget(includeOptions.maxIncludes, 'maxIncludes');
    checkIncludeBudget(includeOptions.maxIncludedEntries, 'maxIncludedEntries');
  }

  /// How each unit is parsed.
  final FlatParseOptions options;

  /// Which key introduces an include, how deep they may nest, and how the
  /// result is assembled.
  final FlatIncludeOptions includeOptions;

  /// How bytes and lines are decoded while reading a unit.
  final FlatStreamReadOptions readOptions;

  final Set<String> _onStack = <String>{};
  final Map<String, FlatDocument> _finished = <String, FlatDocument>{};

  var _includesFollowed = 0;
  var _entriesIncluded = 0;

  /// Claims [id] for resolution, and returns the document if this traversal
  /// already built it.
  ///
  /// A non-null result means the caller is done: nothing was claimed, and
  /// [finish] must not be called. A null result means the caller owns [id]
  /// until it calls [finish].
  ///
  /// [reportedAs] names the unit in exceptions, which for a file is the path
  /// as written rather than the canonical one. [includedFrom] names the unit
  /// holding the directive, and is null at the root.
  ///
  /// Throws [MaxIncludeDepthExceededException] past the configured depth,
  /// [CircularIncludeException] if [id] is already on the stack, and
  /// [IncludeBudgetExceededException] once the traversal has followed more
  /// directives than [FlatIncludeOptions.maxIncludes] allows.
  FlatDocument? begin(
    String id, {
    required String reportedAs,
    required String? includedFrom,
    required int depth,
  }) {
    final maxDepth = includeOptions.maxIncludeDepth;
    if (depth > maxDepth) {
      throw MaxIncludeDepthExceededException(reportedAs, depth, maxDepth);
    }

    // Counted before the cache is consulted: a repeated unit is parsed once,
    // but its entries are copied into every parent that names it, which is
    // the cost this bounds.
    if (depth > 0 && ++_includesFollowed > includeOptions.maxIncludes) {
      throw IncludeBudgetExceededException(
        reportedAs,
        'maxIncludes',
        includeOptions.maxIncludes,
      );
    }

    if (!_onStack.add(id)) {
      throw CircularIncludeException(includedFrom ?? reportedAs, id);
    }

    final done = _finished[id];
    if (done != null) {
      _onStack.remove(id);
    }

    return done;
  }

  /// Records [document] as the result for [id] and releases the claim, so the
  /// same unit may be included again from somewhere else.
  FlatDocument finish(String id, FlatDocument document) {
    _onStack.remove(id);
    _finished[id] = document;

    return document;
  }

  /// Charges [count] entries contributed by an include against the budget.
  ///
  /// Call this before the entries are copied into a parent, so that a graph
  /// which doubles per level is stopped while it is still small. [reportedAs]
  /// names the unit that pushed the traversal over.
  ///
  /// Throws [IncludeBudgetExceededException] past
  /// [FlatIncludeOptions.maxIncludedEntries].
  void chargeEntries(int count, String reportedAs) {
    _entriesIncluded += count;

    if (_entriesIncluded > includeOptions.maxIncludedEntries) {
      throw IncludeBudgetExceededException(
        reportedAs,
        'maxIncludedEntries',
        includeOptions.maxIncludedEntries,
      );
    }
  }
}
