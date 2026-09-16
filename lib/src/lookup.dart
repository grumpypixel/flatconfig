/// The three states a key can be in.
///
/// `doc['k'] == null` cannot tell "never mentioned" from "explicitly reset"
/// (`k =`), and the difference decides whether a default still applies or a
/// value was deliberately cleared. Switch over this where that matters:
///
/// ```dart
/// final theme = switch (doc.lookup('theme')) {
///   FlatAbsent() => Theme.system,
///   FlatReset() => Theme.none,
///   FlatPresent(:final value) => Theme.byName(value),
/// };
/// ```
sealed class FlatLookup {
  /// Creates a lookup result.
  const FlatLookup();

  /// The key does not appear in the document at all.
  const factory FlatLookup.absent() = FlatAbsent;

  /// The key appears with no value (`key =`), clearing anything before it.
  const factory FlatLookup.reset() = FlatReset;

  /// The key appears with [value].
  const factory FlatLookup.present(String value) = FlatPresent;

  /// The value if this is a [FlatPresent], and `null` for the other two.
  ///
  /// This is what `operator []` returns, and it collapses the distinction the
  /// type exists to draw.
  String? get valueOrNull;
}

/// The key does not appear in the document at all.
final class FlatAbsent extends FlatLookup {
  /// Creates the absent result.
  const FlatAbsent();

  @override
  String? get valueOrNull => null;

  @override
  bool operator ==(Object other) => other is FlatAbsent;

  @override
  int get hashCode => 0x1;

  @override
  String toString() => 'FlatLookup.absent()';
}

/// The key appears with no value, clearing anything assigned before it.
final class FlatReset extends FlatLookup {
  /// Creates the reset result.
  const FlatReset();

  @override
  String? get valueOrNull => null;

  @override
  bool operator ==(Object other) => other is FlatReset;

  @override
  int get hashCode => 0x2;

  @override
  String toString() => 'FlatLookup.reset()';
}

/// The key appears with a value.
final class FlatPresent extends FlatLookup {
  /// Creates a present result holding [value].
  const FlatPresent(this.value);

  /// The value the key resolves to.
  final String value;

  @override
  String? get valueOrNull => value;

  @override
  bool operator ==(Object other) =>
      other is FlatPresent && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'FlatLookup.present($value)';
}
