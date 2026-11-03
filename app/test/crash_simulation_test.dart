import 'package:drivalry/tracking/simulated_tracking.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

/// A straight drive at [cruise] m/s for 20 s, then stopped for 12 s, with a
/// 4 g motion event half a second after the last moving fix.
TripInput crashTrip({double cruise = 15, double peak = 45}) {
  const t0 = 1_700_000_000_000;
  const lat0 = 36.1627;
  const lon0 = -86.7816;
  final samples = <GpsSample>[];
  var lat = lat0;
  var lon = lon0;
  for (var i = 0; i < 32; i++) {
    final speed = i < 20 ? cruise : 0.0;
    samples.add(
      GpsSample(
        t: t0 + i * 1000,
        lat: lat,
        lon: lon,
        speed: speed,
        accuracy: 5,
        heading: 90,
      ),
    );
    final n = destination(lat, lon, 90, speed);
    lat = n.lat;
    lon = n.lon;
  }
  return TripInput(
    id: 'sim-crash',
    samples: samples,
    segments: const [],
    motionEvents: [
      MotionEvent(
        t: t0 + 19 * 1000 + 500,
        kind: MotionEventKind.brake,
        peak: peak,
      ),
    ],
  );
}

void main() {
  test(
    'a synthetic 4 g stop produces one crashCandidate after its batch',
    () async {
      final sim = SimulatedTracking(speedUp: double.infinity);
      final events = <TrackingEvent>[];
      final sub = sim.events.listen(events.add);
      final tripId = await sim.play(crashTrip());
      await sub.cancel();
      sim.dispose();

      final crashes = events.whereType<CrashCandidateEvent>().toList();
      expect(crashes.length, 1);
      final c = crashes.single;
      expect(c.tripId, tripId);
      expect(c.peakMps2, 45);
      expect(c.speedBeforeMps, 15);
      // Emitted right after the fixes batch that confirmed the stop, before `ended`.
      final crashIdx = events.indexOf(c);
      expect(events[crashIdx - 1], isA<FixesEvent>());
      expect(events.last, isA<PhaseEvent>());
      expect((events.last as PhaseEvent).phase, TripPhaseSignal.ended);
    },
  );

  test('the same stop at parking speed produces nothing', () async {
    final sim = SimulatedTracking(speedUp: double.infinity);
    final events = <TrackingEvent>[];
    final sub = sim.events.listen(events.add);
    await sim.play(crashTrip(cruise: 3, peak: 60));
    await sub.cancel();
    sim.dispose();
    expect(events.whereType<CrashCandidateEvent>(), isEmpty);
  });
}
