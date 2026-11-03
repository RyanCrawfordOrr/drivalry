import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:test/test.dart';

import 'support.dart';

GpsSample fix(
  double lat,
  double lon, {
  double heading = 90,
  double speed = 15,
  double accuracy = 5,
}) => GpsSample(
  t: 1_700_000_000_000,
  lat: lat,
  lon: lon,
  speed: speed,
  accuracy: accuracy,
  heading: heading,
);

void main() {
  group('LiveMatcher', () {
    test('locates a fix and reports the directional limit', () {
      final north = destination(baseLat, baseLon, 0, 15);
      final south = destination(baseLat, baseLon, 180, 15);
      final n = road(
        1,
        lat: north.lat,
        lon: north.lon,
        bearingDeg: 90,
        lengthM: 1500,
        limit: 30,
        oneway: 1,
        name: 'North',
      );
      final s = road(
        2,
        lat: south.lat,
        lon: south.lon,
        bearingDeg: 90,
        lengthM: 1500,
        limit: 40,
        oneway: 2,
        name: 'South',
      );
      final live = LiveMatcher(MemoryPack.fromWays([n, s]));

      final east = live.locate(fix(baseLat, baseLon, heading: 90))!;
      expect(east.way.id, 1);
      expect(east.name, 'North');
      expect(east.forward, isTrue);
      expect(east.postedLimit, 30);
      expect(east.limitMps, closeTo(30 * 0.44704, 1e-6));
      expect(east.distanceM, closeTo(15, 0.5));

      live.reset();
      final west = live.locate(fix(baseLat, baseLon, heading: 270))!;
      expect(west.way.id, 2);
      expect(west.forward, isFalse);
      expect(west.postedLimit, 40);
    });

    test('is sticky across consecutive fixes', () {
      final offset = destination(baseLat, baseLon, 0, 30);
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 1500,
        limit: 35,
      );
      final b = road(
        2,
        lat: offset.lat,
        lon: offset.lon,
        bearingDeg: 90,
        lengthM: 1500,
        limit: 25,
      );
      final live = LiveMatcher(MemoryPack.fromWays([a, b]));

      final p1 = destination(
        baseLat,
        baseLon,
        0,
        10,
      ); // 10 m from A, 20 m from B
      expect(live.locate(fix(p1.lat, p1.lon))!.way.id, 1);

      final p2 = destination(
        baseLat,
        baseLon,
        0,
        16,
      ); // 16 m from A, 14 m from B: B better by 0.2 only
      expect(live.locate(fix(p2.lat, p2.lon))!.way.id, 1);

      final p3 = destination(
        baseLat,
        baseLon,
        0,
        25,
      ); // 25 m from A, 5 m from B: B wins by 2.0
      expect(live.locate(fix(p3.lat, p3.lon))!.way.id, 2);
      expect(live.last!.postedLimit, 25);
    });

    test('inaccurate fixes keep the last match; nothing nearby clears it', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 1500,
        limit: 35,
      );
      final live = LiveMatcher(MemoryPack.fromWays([a]));
      expect(live.locate(fix(baseLat, baseLon)), isNotNull);
      expect(live.locate(fix(baseLat + 1, baseLon, accuracy: 120))!.way.id, 1);
      expect(live.locate(fix(baseLat + 1, baseLon)), isNull);
      expect(live.last, isNull);
    });

    test('applies overrides', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 1500,
        limit: 35,
      );
      final live = LiveMatcher(MemoryPack.fromWays([a]));
      final m = live.locate(
        fix(baseLat, baseLon),
        overrides: {1: const LimitOverride(wayId: 1, limitMps: 9)},
      )!;
      expect(m.limitMps, 9);
      expect(m.confidence, 0.85);
    });
  });
}
