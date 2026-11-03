import '../../tracking/tracking_models.dart';
import '../db/database.dart';

/// How well trip detection did over the last two weeks (docs/06 M1.5), from
/// what the phone actually stored. Anything that leaves no trace is reported
/// as not countable rather than guessed.
class DetectionCounters {
  const DetectionCounters({
    required this.trips,
    required this.manualStarts,
    required this.deletedTrips,
    required this.lateStarts,
    required this.lateStartsCountable,
    required this.lateEnds,
    required this.lateEndsCountable,
    required this.discardedTentativesSinceInstall,
  });

  static const Duration window = Duration(days: 14);

  /// A confirmed start more than this after the trigger is "late".
  static const Duration lateStartAfter = Duration(minutes: 2);

  /// A stationary end lands 180 s after the last moving fix (docs/08 §6);
  /// more than a minute past that is "late" (no fixes in a garage, a slow
  /// timer).
  static const Duration stationaryRule = Duration(seconds: 180);
  static const Duration lateEndSlack = Duration(seconds: 60);

  /// Trips recorded in the window (not deleted).
  final int trips;

  /// Trips the user started by hand. The best available proxy for a missed
  /// automatic start; a true miss leaves nothing to count.
  final int manualStarts;

  /// Trips the user deleted ("not a trip").
  final int deletedTrips;

  /// Trips confirmed more than [lateStartAfter] after the native trigger.
  final int lateStarts;

  /// Trips in the window whose trigger time is stored (rows older than
  /// schema 6 have none).
  final int lateStartsCountable;

  /// Stationary ends more than [stationaryRule] + [lateEndSlack] after the
  /// last moving fix.
  final int lateEnds;

  /// Stationary-ended trips whose samples are still on the phone.
  final int lateEndsCountable;

  /// The native plugin's own count of tentative trips it dropped itself:
  /// false starts the user never saw. Since install, not windowed.
  final int discardedTentativesSinceInstall;

  static Future<DetectionCounters> load(
    AppDatabase db,
    TrackingDiagnostics diagnostics,
    int nowMs,
  ) async {
    final rows = await db.tripsStartedSince(nowMs - window.inMilliseconds);
    var trips = 0;
    var manual = 0;
    var deleted = 0;
    var lateStarts = 0;
    var lateStartsCountable = 0;
    var lateEnds = 0;
    var lateEndsCountable = 0;
    for (final t in rows) {
      if (t.deletedAt != null) {
        deleted++;
        continue;
      }
      trips++;
      if (t.triggerKind == 'manual') manual++;
      final triggered = t.triggeredAt;
      if (triggered != null) {
        lateStartsCountable++;
        if (t.startedAt - triggered > lateStartAfter.inMilliseconds) {
          lateStarts++;
        }
      }
      final ended = t.endedAt;
      if (ended != null && t.endReason == 'stationary') {
        final lastMoving = await db.lastMovingSampleT(t.id);
        if (lastMoving != null) {
          lateEndsCountable++;
          final allowed =
              stationaryRule.inMilliseconds + lateEndSlack.inMilliseconds;
          if (ended - lastMoving > allowed) lateEnds++;
        }
      }
    }
    return DetectionCounters(
      trips: trips,
      manualStarts: manual,
      deletedTrips: deleted,
      lateStarts: lateStarts,
      lateStartsCountable: lateStartsCountable,
      lateEnds: lateEnds,
      lateEndsCountable: lateEndsCountable,
      discardedTentativesSinceInstall: diagnostics.discardedTentatives,
    );
  }
}
