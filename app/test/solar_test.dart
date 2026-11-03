import 'package:drivalry/tracking/solar.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

List<GpsSample> flatTrip(
  DateTime startUtc,
  double lat,
  double lon,
  int minutes,
) => [
  for (var i = 0; i < minutes * 60; i++)
    GpsSample(
      t: startUtc.millisecondsSinceEpoch + i * 1000,
      lat: lat,
      lon: lon,
      speed: 10,
      accuracy: 5,
    ),
];

void main() {
  const nyLat = 40.7128;
  const nyLon = -74.0060;

  test(
    'New York sunset on the June solstice is about 20:30 EDT (00:30 UTC next day)',
    () {
      final sunset = Solar.sunsetUtc(DateTime.utc(2026, 6, 21), nyLat, nyLon);
      expect(sunset, isNotNull);
      // Sunset is after midnight UTC, so the scan of June 21 finds it near 00:30
      // on the 22nd only if we scan the right day; scan June 22 UTC instead.
      final s = Solar.sunsetUtc(DateTime.utc(2026, 6, 22), nyLat, nyLon)!;
      final expected = DateTime.utc(2026, 6, 22, 0, 31);
      expect(s.difference(expected).inMinutes.abs(), lessThanOrEqualTo(10));
    },
  );

  test('noon is day, midnight is night', () {
    expect(
      Solar.elevationDeg(DateTime.utc(2026, 6, 21, 17), nyLat, nyLon),
      greaterThan(60),
    );
    expect(
      Solar.elevationDeg(DateTime.utc(2026, 6, 21, 5), nyLat, nyLon),
      lessThan(-10),
    );
    expect(Solar.isNight(DateTime.utc(2026, 12, 21, 23), nyLat, nyLon), isTrue);
    expect(
      Solar.isNight(DateTime.utc(2026, 12, 21, 17), nyLat, nyLon),
      isFalse,
    );
  });

  test('night fraction: a noon trip is 0, a midnight trip is 1', () {
    expect(
      Solar.nightFraction(
        flatTrip(DateTime.utc(2026, 6, 21, 16), nyLat, nyLon, 30),
      ),
      0,
    );
    expect(
      Solar.nightFraction(
        flatTrip(DateTime.utc(2026, 6, 21, 5), nyLat, nyLon, 30),
      ),
      1,
    );
    expect(Solar.nightFraction(const []), 0);
  });

  test('a trip across dusk is partly night', () {
    // Civil dusk in NYC on 2026-06-21 is about 21:03 EDT = 01:03 UTC on the 22nd.
    final f = Solar.nightFraction(
      flatTrip(DateTime.utc(2026, 6, 22, 0, 33), nyLat, nyLon, 60),
    );
    expect(f, greaterThan(0.3));
    expect(f, lessThan(0.7));
  });
}
