import '../db/database.dart';

/// Litres in a US gallon.
const double litresPerUsGallon = 3.785411784;

/// Metres in a mile, as kilometres.
const double kmPerMile = 1.609344;

double litresToUsGallons(double litres) => litres / litresPerUsGallon;
double usGallonsToLitres(double gallons) => gallons * litresPerUsGallon;
double kmToMiles(double km) => km / kmPerMile;
double milesToKm(double miles) => miles * kmPerMile;

/// Fuel burned between two consecutive full tanks with odometer readings.
/// Partial fill-ups in between count toward the fuel, not toward a segment of
/// their own, because only a full tank tells you how much was really used.
class FuelSegment {
  const FuelSegment({
    required this.from,
    required this.to,
    required this.litres,
  });

  final FuelEntry from;
  final FuelEntry to;

  /// Fuel added after [from], up to and including [to].
  final double litres;

  double get km => (to.odometerKm ?? 0) - (from.odometerKm ?? 0);
  double get lPer100km => km <= 0 ? double.nan : litres / km * 100;
  double get mpgUs => litres <= 0 || km <= 0
      ? double.nan
      : kmToMiles(km) / litresToUsGallons(litres);
}

/// What the Fuel tab shows for one vehicle.
class FuelStats {
  const FuelStats({
    required this.entries,
    required this.segments,
    required this.totalLitres,
    required this.totalCostCents,
  });

  static const empty = FuelStats(
    entries: 0,
    segments: [],
    totalLitres: 0,
    totalCostCents: 0,
  );

  final int entries;
  final List<FuelSegment> segments;
  final double totalLitres;
  final int totalCostCents;

  /// Distance covered by measured segments only.
  double get measuredKm => segments.fold(0, (s, g) => s + g.km);

  double get measuredLitres => segments.fold(0, (s, g) => s + g.litres);

  /// Fleet-style average over every measured segment, or NaN.
  double get lPer100km =>
      measuredKm <= 0 ? double.nan : measuredLitres / measuredKm * 100;

  double get mpgUs => measuredKm <= 0 || measuredLitres <= 0
      ? double.nan
      : kmToMiles(measuredKm) / litresToUsGallons(measuredLitres);

  /// Cents per kilometre over the entries that carry a cost and fall inside
  /// measured segments, or NaN.
  double get costCentsPerKm {
    if (measuredKm <= 0) return double.nan;
    var cents = 0;
    for (final g in segments) {
      cents += g.to.costCents ?? 0;
    }
    return cents / measuredKm;
  }

  bool get hasEconomy => segments.isNotEmpty && !lPer100km.isNaN;
}

/// Computes true fuel economy from a vehicle's fill-ups, oldest first.
///
/// Rules: a segment runs from one full tank with an odometer reading to the
/// next; partial fill-ups add fuel to the running segment; a full tank without
/// an odometer reading closes nothing and restarts the chain; odometer
/// readings that go backwards restart the chain too.
FuelStats computeFuelStats(List<FuelEntry> entriesUnsorted) {
  if (entriesUnsorted.isEmpty) return FuelStats.empty;
  final entries = List<FuelEntry>.of(entriesUnsorted)
    ..sort((a, b) => a.at.compareTo(b.at));
  final segments = <FuelSegment>[];
  FuelEntry? anchor;
  var litresSinceAnchor = 0.0;
  var totalLitres = 0.0;
  var totalCost = 0;

  for (final e in entries) {
    totalLitres += e.litres;
    totalCost += e.costCents ?? 0;
    if (!e.fullTank) {
      if (anchor != null) litresSinceAnchor += e.litres;
      continue;
    }
    if (e.odometerKm == null) {
      anchor = null;
      litresSinceAnchor = 0;
      continue;
    }
    if (anchor != null &&
        anchor.odometerKm != null &&
        e.odometerKm! > anchor.odometerKm!) {
      segments.add(
        FuelSegment(from: anchor, to: e, litres: litresSinceAnchor + e.litres),
      );
    }
    anchor = e;
    litresSinceAnchor = 0;
  }
  return FuelStats(
    entries: entries.length,
    segments: segments,
    totalLitres: totalLitres,
    totalCostCents: totalCost,
  );
}

/// "7.8 L/100 km" or "30.1 mpg" depending on the user's units.
String formatEconomy(double lPer100km, {required bool useMpg}) {
  if (lPer100km.isNaN || lPer100km <= 0) return '–';
  if (useMpg) {
    final mpg = 235.214583 / lPer100km;
    return '${mpg.toStringAsFixed(1)} mpg';
  }
  return '${lPer100km.toStringAsFixed(1)} L/100 km';
}

/// "12.4 L" or "3.3 gal".
String formatVolume(double litres, {required bool useGallons}) => useGallons
    ? '${litresToUsGallons(litres).toStringAsFixed(1)} gal'
    : '${litres.toStringAsFixed(1)} L';

/// "\$42.10" from cents (no locale currency symbols yet; the entry carries the
/// currency code, shown separately).
String formatCents(int cents) => (cents / 100).toStringAsFixed(2);
