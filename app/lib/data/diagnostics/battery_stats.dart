import '../db/database.dart';
import 'battery_sampler.dart';

/// Battery drain measured on this phone over the last two weeks (docs/06
/// M1.5). Every rate is null until there is enough data to be honest about.
class BatteryStats {
  const BatteryStats({
    this.drivingPctPerHour,
    this.drivingHours = 0,
    this.drivingPairs = 0,
    this.parkedPctPerDay,
    this.parkedDays = 0,
    this.parkedPairs = 0,
  });

  /// Percentage points per hour of recording, from trip start/end pairs.
  final double? drivingPctPerHour;
  final double drivingHours;
  final int drivingPairs;

  /// Percentage points per day with no trip in between, from parked readings.
  final double? parkedPctPerDay;
  final double parkedDays;
  final int parkedPairs;

  /// Window the stats cover.
  static const Duration window = Duration(days: 14);

  /// Minimum evidence before a rate is shown.
  static const int minDrivingPairs = 2;
  static const double minDrivingHours = 0.5;
  static const double minParkedHours = 12;

  /// Parked pairs closer than this are the same sitting; further apart than
  /// the maximum, something was missed (phone off, app killed for days).
  static const Duration minParkedGap = Duration(hours: 2);
  static const Duration maxParkedGap = Duration(hours: 48);

  /// Pure: [samples] oldest first, all phases mixed.
  static BatteryStats compute(List<BatterySample> samples) {
    // Driving: pair each tripStart with the tripEnd of the same trip.
    final starts = <String, BatterySample>{};
    var drainDriving = 0.0;
    var hoursDriving = 0.0;
    var pairsDriving = 0;
    for (final s in samples) {
      if (s.phase == BatteryPhase.tripStart.wire && s.tripId != null) {
        starts[s.tripId!] = s;
      } else if (s.phase == BatteryPhase.tripEnd.wire && s.tripId != null) {
        final start = starts.remove(s.tripId!);
        if (start == null || s.t <= start.t) continue;
        final drop = (start.level - s.level) * 100;
        if (drop < 0) continue; // charged in the car: says nothing about drain
        drainDriving += drop;
        hoursDriving += (s.t - start.t) / 3.6e6;
        pairsDriving++;
      }
    }

    // Parked: consecutive parked readings with no trip start in between.
    final parked = samples
        .where((s) => s.phase == BatteryPhase.parked.wire)
        .toList();
    final tripStartTimes = samples
        .where((s) => s.phase == BatteryPhase.tripStart.wire)
        .map((s) => s.t)
        .toList();
    var drainParked = 0.0;
    var hoursParked = 0.0;
    var pairsParked = 0;
    for (var i = 1; i < parked.length; i++) {
      final a = parked[i - 1];
      final b = parked[i];
      final gap = b.t - a.t;
      if (gap < minParkedGap.inMilliseconds ||
          gap > maxParkedGap.inMilliseconds) {
        continue;
      }
      if (tripStartTimes.any((t) => t > a.t && t < b.t)) continue;
      final drop = (a.level - b.level) * 100;
      if (drop < 0) continue; // on a charger between readings
      drainParked += drop;
      hoursParked += gap / 3.6e6;
      pairsParked++;
    }

    return BatteryStats(
      drivingPctPerHour:
          pairsDriving >= minDrivingPairs && hoursDriving >= minDrivingHours
          ? drainDriving / hoursDriving
          : null,
      drivingHours: hoursDriving,
      drivingPairs: pairsDriving,
      parkedPctPerDay: hoursParked >= minParkedHours
          ? drainParked / (hoursParked / 24)
          : null,
      parkedDays: hoursParked / 24,
      parkedPairs: pairsParked,
    );
  }

  /// Loads the last two weeks of samples and computes.
  static Future<BatteryStats> load(AppDatabase db, int nowMs) async =>
      compute(await db.batterySamplesSince(nowMs - window.inMilliseconds));
}
