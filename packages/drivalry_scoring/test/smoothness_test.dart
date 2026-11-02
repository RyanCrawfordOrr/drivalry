/// Port of `packages/scoring/test/smoothness.test.ts`.
library;

import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:test/test.dart';

void main() {
  group('smoothness detection from GPS', () {
    test('derives a harsh brake from a sudden speed drop', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'brake',
          legs: [
            LegSpec(durationS: 200, speedMph: 45, limitMph: 45),
            LegSpec(durationS: 6, speedMph: 5, limitMph: 45, rampAccel: 4.2),
            LegSpec(durationS: 200, speedMph: 45, limitMph: 45),
          ],
        ),
      );
      final r = scoreTrip(trip);
      final brakes = r.events
          .where((e) => e.kind == EventKind.harshBrake)
          .toList();
      expect(brakes, hasLength(1));
      expect(brakes.first.severity, Severity.moderate);
      expect(r.penalties.smoothness, greaterThan(0));
    });

    test('classifies a very hard stop as severe', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'slam',
          legs: [
            LegSpec(durationS: 200, speedMph: 45, limitMph: 45),
            LegSpec(durationS: 5, speedMph: 0, limitMph: 45, rampAccel: 6),
            LegSpec(durationS: 200, speedMph: 45, limitMph: 45),
          ],
        ),
      );
      final r = scoreTrip(trip);
      final brakes = r.events
          .where((e) => e.kind == EventKind.harshBrake)
          .toList();
      expect(brakes, hasLength(1));
      expect(brakes.first.severity, Severity.severe);
    });

    test('derives harsh acceleration and taxes it in efficiency too', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'launch',
          legs: [
            LegSpec(durationS: 120, speedMph: 25, limitMph: 45),
            LegSpec(durationS: 60, speedMph: 45, limitMph: 45, rampAccel: 3.6),
            LegSpec(durationS: 300, speedMph: 45, limitMph: 45),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(
        r.events.where((e) => e.kind == EventKind.harshAccel),
        hasLength(1),
      );
      expect(r.penalties.efficiency, greaterThanOrEqualTo(0.5));
    });

    test('detects hard cornering from heading rate at speed', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'corner',
          legs: [
            LegSpec(durationS: 200, speedMph: 35, limitMph: 45),
            LegSpec(durationS: 4, speedMph: 35, limitMph: 45, turnRateDegS: 22),
            LegSpec(durationS: 200, speedMph: 35, limitMph: 45),
          ],
        ),
      );
      final r = scoreTrip(trip);
      final corners = r.events
          .where((e) => e.kind == EventKind.hardCorner)
          .toList();
      expect(corners, hasLength(1));
      expect(corners.first.severity, Severity.severe);
    });

    test('normalises short trips so one brake is not catastrophic', () {
      final short = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'short-brake',
          legs: [
            LegSpec(durationS: 90, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 5, speedMph: 2, limitMph: 30, rampAccel: 4),
            LegSpec(durationS: 90, speedMph: 30, limitMph: 30),
          ],
        ),
      );
      final r = scoreTrip(short);
      expect(r.scored, isTrue);
      // One moderate brake = 2.0 raw, normalised by 10 km / 3 km floor ≈ 6.7
      expect(r.penalties.smoothness, lessThan(8));
      expect(r.penalties.smoothness, greaterThan(5));
    });

    test('prefers supplied accelerometer events over GPS derivation', () {
      final built = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'accelerometer',
          legs: [LegSpec(durationS: 600, speedMph: 40, limitMph: 45)],
        ),
      );
      final t0 = built.samples.first.t;
      final trip = built.copyWith(
        motionEvents: [
          MotionEvent(t: t0 + 100000, kind: MotionEventKind.brake, peak: 5.4),
          MotionEvent(
            t: t0 + 101000,
            kind: MotionEventKind.brake,
            peak: 4.1,
          ), // merged into the first
          MotionEvent(t: t0 + 300000, kind: MotionEventKind.corner, peak: 4.4),
          MotionEvent(
            t: t0 + 400000,
            kind: MotionEventKind.accel,
            peak: 2.0,
          ), // below threshold, ignored
        ],
      );
      final r = scoreTrip(trip);
      expect(
        r.events.where((e) => e.kind == EventKind.harshBrake),
        hasLength(1),
      );
      expect(
        r.events.firstWhere((e) => e.kind == EventKind.harshBrake).severity,
        Severity.severe,
      );
      expect(
        r.events.where((e) => e.kind == EventKind.hardCorner),
        hasLength(1),
      );
      expect(r.events.where((e) => e.kind == EventKind.harshAccel), isEmpty);
    });
  });
}
