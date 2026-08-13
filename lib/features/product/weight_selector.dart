/// Pure weight-selector math (PRD E1 / acceptance J4) — kept free of
/// `BuildContext`/widgets so the stepping, clamping and price logic is
/// directly unit-testable.
///
/// A weight-sold item's selector starts at [stepG] grams, each "+"/"-" moves
/// by one more [stepG], and the result is always clamped to `[minG, maxG]`
/// (falling back to `[stepG, +inf)` when a bound isn't provided by the
/// backend, since a selector can never usefully go below its own step or
/// have an unbounded max cut off).
class WeightSelector {
  WeightSelector({required this.stepG, double? minG, this.maxG})
    : minG = (minG != null && minG > 0) ? minG : stepG {
    grams = _clamp(stepG);
  }

  /// The configured step (`weight_step_g`), and the selector's starting
  /// value.
  final double stepG;

  /// Lower clamp bound (`min_g`). Defaults to [stepG] when the backend
  /// didn't send one (or sent a non-positive value).
  final double minG;

  /// Upper clamp bound (`max_g`). `null` means unbounded.
  final double? maxG;

  /// Current selection in grams.
  late double grams;

  /// Current selection in Kg (PRD E1: cart qty is sent in Kg —
  /// `grams / 1000.0`).
  double get kg => grams / 1000.0;

  bool get canIncrement => maxG == null || grams < maxG!;

  bool get canDecrement => grams > minG;

  void increment() => grams = _clamp(grams + stepG);

  void decrement() => grams = _clamp(grams - stepG);

  /// Live total price for the current selection: `price_per_uom × kg`
  /// (PRD J4).
  double totalPrice(double pricePerUom) => pricePerUom * kg;

  double _clamp(double value) {
    var v = value;
    if (v < minG) v = minG;
    final max = maxG;
    if (max != null && v > max) v = max;
    return v;
  }
}

/// Formats a gram amount for display: grams below 1000 as a whole-number
/// gram value (`"500 g"`), at/above 1000 as Kg with at most one decimal,
/// trimming a trailing `.0` (`"1 kg"`, `"1.5 kg"`).
String formatWeightGrams(
  double grams, {
  required String gramUnit,
  required String kgUnit,
}) {
  if (grams < 1000) {
    return '${grams.round()} $gramUnit';
  }
  final tenths = (grams / 100).round(); // grams -> kg*10, rounded
  final kgStr = tenths % 10 == 0
      ? (tenths ~/ 10).toString()
      : (tenths / 10).toStringAsFixed(1);
  return '$kgStr $kgUnit';
}
