/// Port of `packages/scoring/test/attention.test.ts`.
library;

import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:test/test.dart';

void main() {
  group('phone handling', () {
    test('ignores phone use while stopped or crawling', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'stopped',
          legs: [
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
            LegSpec(durationS: 60, speedMph: 0, limitMph: 30),
            LegSpec(durationS: 200, speedMph: 30, limitMph: 30),
          ],
          phoneEventsAt: [PhoneEventAt(atS: 230), PhoneEventAt(atS: 240)],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.events.where((e) => e.kind == EventKind.phoneHandling), isEmpty);
    });

    test('merges taps within 20 s into one episode and grades by duration', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'taps',
          legs: [LegSpec(durationS: 600, speedMph: 35, limitMph: 45)],
          phoneEventsAt: [
            PhoneEventAt(atS: 100),
            PhoneEventAt(atS: 110),
            PhoneEventAt(atS: 125),
            PhoneEventAt(atS: 400),
          ],
        ),
      );
      final r = scoreTrip(trip);
      final eps = r.events
          .where((e) => e.kind == EventKind.phoneHandling)
          .toList();
      expect(eps, hasLength(2));
      expect(eps[0].severity, Severity.moderate); // 25 s
      expect(eps[1].severity, Severity.minor); // single tap
      expect(r.penalties.attention, 10);
    });

    test('treats any handling at highway speed as major', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'highway-phone',
          legs: [LegSpec(durationS: 600, speedMph: 68, limitMph: 70)],
          phoneEventsAt: [PhoneEventAt(atS: 300, kind: PhoneEventKind.unlock)],
        ),
      );
      final r = scoreTrip(trip);
      final e = r.events
          .where((x) => x.kind == EventKind.phoneHandling)
          .firstOrNull;
      expect(e?.severity, Severity.major);
      expect(r.penalties.attention, 12);
      expect(r.reckless, isFalse); // short, so not reckless
    });

    test('flags a long highway phone session as reckless', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          id: 'highway-scroll',
          legs: [LegSpec(durationS: 600, speedMph: 68, limitMph: 70)],
          phoneEventsAt: [
            PhoneEventAt(atS: 200),
            PhoneEventAt(atS: 215),
            PhoneEventAt(atS: 230),
            PhoneEventAt(atS: 245),
            PhoneEventAt(atS: 262),
            PhoneEventAt(atS: 275),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.flags, contains(Flag.recklessPhone));
      expect(r.reckless, isTrue);
      expect(r.xp, 0);
    });

    test('caps the attention penalty', () {
      final trip = buildSyntheticTrip(
        SyntheticSpec(
          id: 'phone-addict',
          legs: const [LegSpec(durationS: 900, speedMph: 35, limitMph: 45)],
          phoneEventsAt: [
            for (var i = 0; i < 12; i++) PhoneEventAt(atS: 60 + i * 60),
          ],
        ),
      );
      final r = scoreTrip(trip);
      expect(r.penalties.attention, 30);
    });
  });
}
