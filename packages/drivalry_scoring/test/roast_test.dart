/// Port of `packages/scoring/test/roast.test.ts`.
library;

import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:test/test.dart';

/// Words that must never appear in a roast. The floor from docs/02-game-design.md §9.1.
final List<RegExp> banned = [
  RegExp('crash', caseSensitive: false),
  RegExp('wreck', caseSensitive: false),
  RegExp(r'\bdie\b', caseSensitive: false),
  RegExp(r'\bdead\b', caseSensitive: false),
  RegExp('death', caseSensitive: false),
  RegExp(r'\bkill', caseSensitive: false),
  RegExp('injur', caseSensitive: false),
  RegExp('hospital', caseSensitive: false),
  RegExp('drunk', caseSensitive: false),
  RegExp(r'\bbeer\b', caseSensitive: false),
  RegExp(r'\bidiot\b', caseSensitive: false),
  RegExp(r'\bstupid\b', caseSensitive: false),
  RegExp(r'\bmoron\b', caseSensitive: false),
  RegExp(r'\bfat\b', caseSensitive: false),
  RegExp(r'\bugly\b', caseSensitive: false),
  RegExp(r'\bbet you can', caseSensitive: false),
  RegExp(r'\bfaster\b', caseSensitive: false),
];

void main() {
  group('roast templates', () {
    test('never cross the hard floor', () {
      for (final MapEntry(key: key, value: byIntensity) in templates.entries) {
        for (final MapEntry(key: intensity, value: list)
            in byIntensity.entries) {
          expect(
            list,
            isNotEmpty,
            reason: '${key.key}.${intensity.name} has templates',
          );
          for (final t in list) {
            for (final re in banned) {
              expect(
                re.hasMatch(t),
                isFalse,
                reason:
                    '${key.key}.${intensity.name}: "$t" matches ${re.pattern}',
              );
            }
          }
        }
      }
    });

    test('fills every slot it uses', () {
      for (final intensity in Intensity.values) {
        final r = scoreTrip(
          messyCommute('slots-${intensity.name}'),
          ScoreOptions(intensity: intensity),
        );
        for (final line in [r.feedback.headline, ...r.feedback.lines]) {
          expect(line.text, isNot(matches(RegExp(r'\{\w+\}'))));
        }
      }
    });

    test('is deterministic per trip id and varies across ids', () {
      const savage = ScoreOptions(intensity: Intensity.savage);
      final a = scoreTrip(messyCommute('same'), savage);
      final b = scoreTrip(messyCommute('same'), savage);
      expect(a.feedback.toJson(), equals(b.feedback.toJson()));

      final seen = <String>{};
      for (var i = 0; i < 12; i++) {
        seen.add(
          scoreTrip(messyCommute('id-$i'), savage).feedback.headline.text,
        );
      }
      expect(seen.length, greaterThan(1));
    });

    test('puts the speed and the road in a speeding roast', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'roadname',
          legs: [
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 120, speedMph: 42, limitMph: 30, name: 'Elm St'),
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
          ],
        ),
      );
      final r = scoreTrip(
        trip,
        const ScoreOptions(intensity: Intensity.savage),
      );
      expect(r.feedback.headline.tone, FeedbackTone.roast);
      expect(r.feedback.headline.text, contains('Elm St'));
      expect(r.feedback.headline.text, matches(RegExp(r'\b(42|12|30)\b')));
    });

    test('supports km/h output', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'metric',
          legs: [
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 120, speedMph: 42, limitMph: 30, name: 'Elm St'),
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
          ],
        ),
      );
      final r = scoreTrip(
        trip,
        const ScoreOptions(intensity: Intensity.gentle, units: SpeedUnits.kmh),
      );
      expect(r.feedback.headline.text, matches(RegExp(r'km/h|\b(68|19|48)\b')));
    });

    test('praises a perfect trip', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'perfect',
          legs: [LegSpec(durationS: 900, speedMph: 40, limitMph: 45)],
        ),
      );
      final r = scoreTrip(trip, const ScoreOptions(intensity: Intensity.sassy));
      expect(r.feedback.headline.tone, FeedbackTone.praise);
      expect(r.feedback.headline.text, matches('miles'));
    });

    test('formats durations and savings in plain words', () {
      expect(formatDuration(45), '45 seconds');
      expect(formatDuration(65), 'a minute');
      expect(formatDuration(95), '1 min 35 s');
      expect(formatDuration(190), '3 minutes');
      expect(formatSaved(0), 'nothing');
      expect(formatSaved(38), '38 seconds');
      expect(formatSaved(130), '2 minutes');
    });
  });
}
