/// Sanity checks on the synthetic trip builder that the fixtures do not already pin.
library;

import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:test/test.dart';

void main() {
  group('buildSyntheticTrip', () {
    test('default start time is Date.UTC(2026, 10, 1, 17, 30, 0)', () {
      expect(
        defaultSyntheticStartT,
        DateTime.utc(2026, 11, 1, 17, 30).millisecondsSinceEpoch,
      );
    });

    test('default id embeds the start time', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(legs: [LegSpec(durationS: 3, speedMph: 10)]),
      );
      expect(trip.id, 'synthetic-$defaultSyntheticStartT');
      expect(trip.samples, hasLength(4));
      expect(trip.segments.single.fromIdx, 1);
      expect(trip.segments.single.toIdx, 3);
      expect(trip.segments.single.speedLimit, isNull);
      expect(trip.segments.single.confidence, 0);
      expect(trip.segments.single.roadClass, RoadClass.residential);
      expect(trip.phoneEvents, isNull);
      expect(trip.context, isNull);
    });

    test('limits at or above 55 mph default to motorway', () {
      final trip = buildSyntheticTrip(
        const SyntheticSpec(
          legs: [
            LegSpec(durationS: 2, speedMph: 10, limitMph: 55),
            LegSpec(durationS: 2, speedMph: 10, limitMph: 54),
          ],
        ),
      );
      expect(trip.segments[0].roadClass, RoadClass.motorway);
      expect(trip.segments[0].confidence, 0.9);
      expect(trip.segments[1].roadClass, RoadClass.residential);
    });

    test('SyntheticSpec survives a JSON round trip', () {
      const spec = SyntheticSpec(
        id: 'rt',
        startT: 1000,
        start: (lat: 1.5, lon: -2.5),
        headingDeg: 45,
        legs: [
          LegSpec(
            durationS: 2,
            speedMph: 30,
            limitMph: 25,
            name: 'X',
            turnRateDegS: 3,
            accuracy: 7,
          ),
        ],
        phoneEventsAt: [PhoneEventAt(atS: 1, kind: PhoneEventKind.unlock)],
        accuracy: 9,
        context: TripContext(
          nightFraction: 0.5,
          weather: Weather.snow,
          cleanStreak: 3,
        ),
      );
      final json = spec.toJson();
      expect(SyntheticSpec.fromJson(json).toJson(), equals(json));
      expect(
        buildSyntheticTrip(SyntheticSpec.fromJson(json)).toJson(),
        equals(buildSyntheticTrip(spec).toJson()),
      );
    });
  });
}
