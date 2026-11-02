/// Port of `packages/scoring/test/score.test.ts`.
library;

import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:test/test.dart';

void main() {
  group('trip minimums', () {
    test('does not score trips under 1 km', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'tiny',
          legs: [LegSpec(durationS: 60, speedMph: 20, limitMph: 25)],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.scored, isFalse);
      expect(r.unscoredReason, UnscoredReason.tooShort);
      expect(r.score, 0);
      expect(r.xp, 0);
      expect(
        r.feedback.headline.text,
        matches(RegExp('short|scored', caseSensitive: false)),
      );
    });

    test('does not score passenger trips', () {
      final trip = cleanCommute(
        'pax',
      ).copyWith(context: const TripContext(isPassenger: true));
      final r = scoreTrip(trip);
      expect(r.scored, isFalse);
      expect(r.unscoredReason, UnscoredReason.passenger);
    });
  });

  group('efficiency', () {
    test('penalises sustained cruising above 75 mph even under the limit', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'cruise',
          legs: [
            LegSpec(
              durationS: 600,
              speedMph: 79,
              limitMph: 80,
              roadClass: RoadClass.motorway,
            ),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.events.where((e) => e.kind == EventKind.speeding), isEmpty);
      expect(
        r.events.where((e) => e.kind == EventKind.highSpeedCruise),
        hasLength(1),
      );
      expect(r.penalties.efficiency, greaterThan(5));
      expect(r.penalties.efficiency, lessThanOrEqualTo(6));
    });

    test('penalises long mid-trip idling lightly', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'idle',
          legs: [
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 400, speedMph: 0, limitMph: 30),
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
          ],
        ),
      );
      final r = scoreTrip(trip);
      final idle = r.events
          .where((e) => e.kind == EventKind.idling)
          .firstOrNull;
      expect(idle, isNotNull);
      expect(r.penalties.efficiency, greaterThan(1.5));
      expect(r.penalties.efficiency, lessThanOrEqualTo(4));
    });
  });

  group('XP', () {
    test('gives 100 XP for a perfect 15 km trip and 0 below a score of 50', () {
      expect(computeXp(100, 15000, null, false), 100);
      expect(computeXp(49, 15000, null, false), 0);
      expect(computeXp(100, 15000, null, true), 0);
    });

    test('scales short trips down but never below the floor', () {
      expect(computeXp(100, 3000, null, false), 52);
      expect(computeXp(100, 300, null, false), 41);
    });

    test('applies the daily distance cap', () {
      expect(
        computeXp(
          100,
          30000,
          const TripContext(dailyCreditedKmBefore: 100),
          false,
        ),
        40,
      );
      expect(
        computeXp(
          100,
          30000,
          const TripContext(dailyCreditedKmBefore: 95),
          false,
        ),
        60,
      );
    });

    test('adds context bonuses only for strong scores', () {
      expect(
        computeXp(90, 20000, const TripContext(nightFraction: 1), false),
        (82 * 1.1).round(),
      );
      expect(
        computeXp(
          90,
          20000,
          const TripContext(nightFraction: 1, weather: Weather.rain),
          false,
        ),
        (82 * 1.2).round(),
      );
      expect(
        computeXp(
          70,
          20000,
          const TripContext(nightFraction: 1, weather: Weather.rain),
          false,
        ),
        46,
      );
    });

    test('adds streak bonuses for clean trips', () {
      expect(
        computeXp(100, 20000, const TripContext(cleanStreak: 5), false),
        105,
      );
      expect(
        computeXp(100, 20000, const TripContext(cleanStreak: 25), false),
        110,
      );
      expect(
        computeXp(70, 20000, const TripContext(cleanStreak: 25), false),
        46,
      );
    });
  });

  group('end-to-end fixtures', () {
    test('scores the clean commute perfectly', () {
      final r = scoreTrip(cleanCommute());
      expect(r.score, 100);
      expect(r.xp, 100);
      expect(r.feedback.headline.tone, FeedbackTone.praise);
    });

    test('scores the messy commute with one of everything', () {
      final r = scoreTrip(messyCommute());
      final kinds = r.events.map((e) => e.kind).toSet();
      expect(kinds, contains(EventKind.speeding));
      expect(kinds, contains(EventKind.harshBrake));
      expect(kinds, contains(EventKind.phoneHandling));
      expect(kinds, contains(EventKind.highSpeedCruise));
      expect(r.reckless, isFalse);
      expect(r.score, greaterThan(30));
      expect(r.score, lessThan(80));
      expect(r.feedback.headline.tone, FeedbackTone.roast);
      expect(r.feedback.lines, isNotEmpty);
    });

    test('is deterministic', () {
      final a = scoreTrip(messyCommute());
      final b = scoreTrip(messyCommute());
      expect(a.toJson(), equals(b.toJson()));
    });
  });
}
