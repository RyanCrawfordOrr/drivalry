/// Port of `packages/scoring/test/speeding.test.ts`.
library;

import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:test/test.dart';

void main() {
  group('speeding detection', () {
    test('scores a clean trip at 100 with no events', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'clean',
          legs: [
            LegSpec(durationS: 300, speedMph: 28, limitMph: 30, name: 'Elm St'),
            LegSpec(durationS: 600, speedMph: 63, limitMph: 65, name: 'I-40'),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.scored, isTrue);
      expect(r.events, isEmpty);
      expect(r.score, 100);
      expect(r.penalties, ComponentPenalties.zero);
      expect(r.reckless, isFalse);
      expect(r.summary.secondsOverLimit, 0);
    });

    test('detects a moderate episode with the right numbers', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'moderate',
          legs: [
            LegSpec(durationS: 120, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 90, speedMph: 42, limitMph: 30, name: 'Route 9'),
            LegSpec(durationS: 300, speedMph: 30, limitMph: 30),
          ],
        ),
      );
      final r = scoreTrip(trip);
      final sp = r.events.where((e) => e.kind == EventKind.speeding).toList();
      expect(sp, hasLength(1));
      final e = sp.first;
      expect(e.severity, Severity.moderate);
      expect(e.detail, isA<SpeedingDetail>());
      final d = e.detail as SpeedingDetail;
      expect(d.roadName, 'Route 9');
      expect(d.maxOver, closeTo(mphToMps(12), 0.05));
      expect(d.timeSavedS, greaterThan(15));
      expect(d.timeSavedS, lessThan(40));
      // ~90 s includes the ramp down, so allow a little slack.
      expect(e.durationS, greaterThanOrEqualTo(85));
      expect(e.durationS, lessThanOrEqualTo(100));
      expect(r.penalties.speed, greaterThan(3));
      expect(r.score, lessThan(100));
    });

    test('ignores episodes shorter than 8 seconds', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'blip',
          legs: [
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 3, speedMph: 40, limitMph: 30, rampAccel: 10),
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30, rampAccel: 10),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.events.where((e) => e.kind == EventKind.speeding), isEmpty);
    });

    test('merges episodes separated by a short dip', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'merge',
          legs: [
            LegSpec(durationS: 100, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 40, speedMph: 42, limitMph: 30),
            LegSpec(durationS: 4, speedMph: 33, limitMph: 30, rampAccel: 4),
            LegSpec(durationS: 40, speedMph: 42, limitMph: 30, rampAccel: 4),
            LegSpec(durationS: 100, speedMph: 30, limitMph: 30),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.events.where((e) => e.kind == EventKind.speeding), hasLength(1));
    });

    test(
      'records speeding on low-confidence roads as observations, not penalties',
      () {
        final trip = buildSyntheticTrip(
          const SyntheticSpec(
            id: 'lowconf',
            legs: [
              LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
              LegSpec(
                durationS: 120,
                speedMph: 45,
                limitMph: 30,
                confidence: 0.4,
                name: 'Mystery Rd',
              ),
              LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
            ],
          ),
        );
        final r = scoreTrip(trip);
        expect(r.events.where((e) => e.kind == EventKind.speeding), isEmpty);
        expect(r.observations, hasLength(1));
        expect(r.penalties.speed, 0);
        expect(r.score, 100);
      },
    );

    test('does not judge roads with no limit at all', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'nolimit',
          legs: [LegSpec(durationS: 600, speedMph: 55)],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.events, isEmpty);
      expect(r.flags, contains(Flag.limitsUnknown));
    });

    test('flags reckless at 25+ over and zeroes XP', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'reckless',
          legs: [
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 30, speedMph: 58, limitMph: 30, name: 'Elm St'),
            LegSpec(durationS: 400, speedMph: 30, limitMph: 30),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.reckless, isTrue);
      expect(r.flags, contains(Flag.recklessSpeed));
      expect(r.score, lessThanOrEqualTo(25));
      expect(r.xp, 0);
      expect(r.feedback.headline.tone, FeedbackTone.roast);
    });

    test('flags 100+ mph as reckless even with an unknown limit', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'ton',
          legs: [
            LegSpec(durationS: 200, speedMph: 60),
            LegSpec(durationS: 15, speedMph: 104, rampAccel: 3),
            LegSpec(durationS: 200, speedMph: 60, rampAccel: 3),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.reckless, isTrue);
      final e = r.events.where((x) => x.kind == EventKind.speeding).firstOrNull;
      expect(e?.severity, Severity.reckless);
    });

    test('skips samples with bad GPS accuracy', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'badgps',
          legs: [
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 60, speedMph: 45, limitMph: 30, accuracy: 120),
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.events.where((e) => e.kind == EventKind.speeding), isEmpty);
    });
  });

  group('limit-drop grace', () {
    test('does not punish slowing down after the limit drops', () {
      // 65 mph highway straight into a 25 mph street, decelerating at a gentle 1.5 m/s².
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'exit-ramp',
          legs: [
            LegSpec(durationS: 300, speedMph: 63, limitMph: 65, name: 'I-40'),
            LegSpec(
              durationS: 180,
              speedMph: 22,
              limitMph: 25,
              name: 'Maple Ave',
            ),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.events.where((e) => e.kind == EventKind.speeding), isEmpty);
      expect(r.reckless, isFalse);
      expect(r.score, 100);
    });

    test(
      'still catches a driver who keeps the speed after the limit drops',
      () {
        final trip = buildSyntheticTrip(
          const SyntheticSpec(
            id: 'ignores-sign',
            legs: [
              LegSpec(durationS: 300, speedMph: 63, limitMph: 65, name: 'I-40'),
              LegSpec(
                durationS: 40,
                speedMph: 63,
                limitMph: 25,
                name: 'Maple Ave',
              ),
              LegSpec(
                durationS: 180,
                speedMph: 22,
                limitMph: 25,
                name: 'Maple Ave',
              ),
            ],
          ),
        );
        final r = scoreTrip(trip);
        final sp = r.events.where((e) => e.kind == EventKind.speeding).toList();
        expect(sp, hasLength(1));
        expect(sp.first.severity, Severity.reckless);
        // Only the first few seconds are forgiven.
        expect(sp.first.durationS, greaterThanOrEqualTo(30));
      },
    );
  });
}
