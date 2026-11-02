/// Helpers that reproduce JavaScript number semantics where Dart's differ.
///
/// The TypeScript engine is the specification, so every place it relies on a JS-specific
/// behaviour is routed through one of these so the divergence is explicit and testable.
library;

/// JavaScript `Math.round`: the nearest integer, with ties rounding toward +∞.
///
/// Dart's [double.round] rounds ties away from zero (`(-2.5).round() == -3`, JS gives `-2`).
/// Non-finite values pass through unchanged, as in JS. `x - floor(x)` is exact for doubles,
/// so `0.49999999999999994` correctly rounds to `0` (a naive `floor(x + 0.5)` would not).
double jsRound(double x) {
  if (!x.isFinite) return x;
  final f = x.floorToDouble();
  return (x - f) < 0.5 ? f : f + 1;
}

/// [jsRound] as an [int]. Only for values known to be finite (scores, XP).
int jsRoundInt(double x) => jsRound(x).toInt();

/// How a JS template literal renders an integral number: `45` not `45.0`, `-0` as `0`,
/// and `NaN` / `Infinity` spelled out.
String jsIntegerString(double v) {
  if (v.isNaN) return 'NaN';
  if (v.isInfinite) return v > 0 ? 'Infinity' : '-Infinity';
  return v.toInt().toString();
}

/// Stable sort. `Array.prototype.sort` is stable (ES2019); Dart's [List.sort] is not
/// guaranteed to be, and event ordering (hence feedback `eventIndex`) depends on ties
/// keeping their insertion order.
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = items.indexed.toList();
  indexed.sort((a, b) {
    final c = compare(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final (_, value) in indexed) value];
}
