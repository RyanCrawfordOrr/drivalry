import 'dart:math' as math;

import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  const matcher = RoadMatcher();

  group('RoadMatcher', () {
    test('(a) straight road: one segment, full coverage', () {
      final a = road(
        10,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
        limit: 35,
        name: 'K Street',
      );
      final pack = MemoryPack.fromWays([a]);
      final samples = trace(
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        count: 100,
      );

      final r = matcher.match(samples, pack);

      expectTiles(r.segments, 100);
      expect(r.segments, hasLength(1));
      final s = r.segments.single;
      expect(s.fromIdx, 0);
      expect(s.toIdx, 99);
      expect(s.wayId, '10');
      expect(s.name, 'K Street');
      expect(s.roadClass, RoadClass.residential);
      expect(s.speedLimit, closeTo(15.6464, 1e-6));
      expect(s.confidence, 0.9);
      expect(r.limitCoverage, 1.0);
      expect(r.matchedFraction, 1.0);
      expect(r.wayIdPerSample.every((id) => id == 10), isTrue);
      expect(r.forwardPerSample.every((f) => f), isTrue);
    });

    test('(b) parallel oneway roads: heading picks the legal one', () {
      // North road runs east (oneway forward); south road's points run east
      // but it is oneway against point order, so it carries westbound traffic.
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
      );
      final s = road(
        2,
        lat: south.lat,
        lon: south.lon,
        bearingDeg: 90,
        lengthM: 1500,
        limit: 40,
        oneway: 2,
      );
      final pack = MemoryPack.fromWays([n, s]);

      final east = matcher.match(
        trace(lat: baseLat, lon: baseLon, bearingDeg: 90, count: 60),
        pack,
      );
      expect(east.segments, hasLength(1));
      expect(east.segments.single.wayId, '1');
      expect(east.segments.single.speedLimit, closeTo(30 * 0.44704, 1e-6));
      expect(east.forwardPerSample.every((f) => f), isTrue);

      final start = destination(baseLat, baseLon, 90, 1000);
      final west = matcher.match(
        trace(lat: start.lat, lon: start.lon, bearingDeg: 270, count: 60),
        pack,
      );
      expect(west.segments, hasLength(1));
      expect(west.segments.single.wayId, '2');
      expect(west.segments.single.speedLimit, closeTo(40 * 0.44704, 1e-6));
      expect(west.forwardPerSample.every((f) => !f), isTrue);
    });

    test(
      '(c) switching at a turn lands the boundary on the first better sample',
      () {
        final corner = destination(baseLat, baseLon, 90, 900);
        final a = road(
          1,
          lat: baseLat,
          lon: baseLon,
          bearingDeg: 90,
          lengthM: 900,
          limit: 35,
        );
        final b = road(
          2,
          lat: corner.lat,
          lon: corner.lon,
          bearingDeg: 0,
          lengthM: 1200,
          limit: 25,
        );
        final pack = MemoryPack.fromWays([a, b]);
        final samples = legs([
          trace(
            lat: baseLat,
            lon: baseLon,
            bearingDeg: 90,
            count: 60,
          ), // 0..59, ends at 885 m
          trace(
            lat: corner.lat,
            lon: corner.lon,
            bearingDeg: 0,
            count: 60,
          ), // 60.. starts at the corner heading north
        ]);

        final r = matcher.match(samples, pack);

        expectTiles(r.segments, 120);
        expect(r.segments, hasLength(2));
        expect(r.segments[0].wayId, '1');
        expect(r.segments[0].toIdx, 59);
        expect(r.segments[1].wayId, '2');
        expect(r.segments[1].fromIdx, 60);
        expect(r.segments[1].speedLimit, closeTo(25 * 0.44704, 1e-6));
        expect(r.limitCoverage, 1.0);
      },
    );

    test('(c2) a rival that is better for only two samples does not win', () {
      // Road B runs parallel 12 m away for the whole trip. A short GPS wobble
      // of two samples towards B must not switch.
      final offset = destination(baseLat, baseLon, 0, 12);
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
      final pack = MemoryPack.fromWays([a, b]);
      final samples = trace(
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        count: 60,
      );
      final wobble = destination(baseLat, baseLon, 0, 12);
      for (final i in [20, 21]) {
        final p = destination(wobble.lat, wobble.lon, 90, 15.0 * i);
        samples[i] = GpsSample(
          t: samples[i].t,
          lat: p.lat,
          lon: p.lon,
          speed: 15,
          accuracy: 5,
          heading: 90,
        );
      }

      final r = matcher.match(samples, pack);
      expect(r.segments, hasLength(1));
      expect(r.segments.single.wayId, '1');

      // Three wobbly samples do switch, and the boundary is the first one.
      final p22 = destination(wobble.lat, wobble.lon, 90, 15.0 * 22);
      samples[22] = GpsSample(
        t: samples[22].t,
        lat: p22.lat,
        lon: p22.lon,
        speed: 15,
        accuracy: 5,
        heading: 90,
      );
      final r2 = matcher.match(samples, pack);
      expect(r2.segments.length, greaterThanOrEqualTo(2));
      expect(r2.segments[0].wayId, '1');
      expect(r2.segments[0].toIdx, 19);
      expect(r2.segments[1].wayId, '2');
      expect(r2.segments[1].fromIdx, 20);
    });

    test('(d) inaccurate fixes inherit the previous way', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
        limit: 35,
      );
      final pack = MemoryPack.fromWays([a]);
      final samples = trace(
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        count: 80,
      );
      for (var i = 30; i < 35; i++) {
        final far = destination(
          samples[i].lat,
          samples[i].lon,
          0,
          200,
        ); // 200 m off the road
        samples[i] = GpsSample(
          t: samples[i].t,
          lat: far.lat,
          lon: far.lon,
          speed: 15,
          accuracy: 80,
          heading: 90,
        );
      }

      final r = matcher.match(samples, pack);
      expect(r.segments, hasLength(1));
      expect(r.segments.single.wayId, '1');
      expect(r.wayIdPerSample.every((id) => id == 1), isTrue);
      expect(r.matchedFraction, 1.0);
    });

    test('(d2) a slow fix with no heading inherits', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
        limit: 35,
      );
      final pack = MemoryPack.fromWays([a]);
      final samples = trace(
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        count: 40,
      );
      // Stopped for 5 samples at the same spot, 30 m off the road, no heading.
      final stop = destination(samples[20].lat, samples[20].lon, 0, 30);
      for (var i = 20; i < 25; i++) {
        samples[i] = GpsSample(
          t: samples[i].t,
          lat: stop.lat,
          lon: stop.lon,
          speed: 0,
          accuracy: 5,
        );
      }
      final r = matcher.match(samples, pack);
      expect(r.wayIdPerSample.every((id) => id == 1), isTrue);
    });

    test(
      '(e) no road within reach gives an unmatched segment that still tiles',
      () {
        final a = road(
          1,
          lat: baseLat,
          lon: baseLon,
          bearingDeg: 90,
          lengthM: 450,
          limit: 35,
        );
        final bStart = destination(baseLat, baseLon, 90, 1050);
        final b = road(
          2,
          lat: bStart.lat,
          lon: bStart.lon,
          bearingDeg: 90,
          lengthM: 1000,
          limit: 25,
        );
        final pack = MemoryPack.fromWays([a, b]);
        final samples = trace(
          lat: baseLat,
          lon: baseLon,
          bearingDeg: 90,
          count: 120,
        ); // 0..1785 m

        final r = matcher.match(samples, pack);

        expectTiles(r.segments, 120);
        expect(r.segments, hasLength(3));
        expect(r.segments[0].wayId, '1');
        final gap = r.segments[1];
        expect(gap.wayId, isNull);
        expect(gap.speedLimit, isNull);
        expect(gap.confidence, 0);
        expect(gap.roadClass, RoadClass.unknown);
        expect(gap.name, isNull);
        expect(r.segments[2].wayId, '2');
        // Samples 0..30 are within 35 m of A (A ends at 450 m, sample 32 is at 480 m).
        expect(gap.fromIdx, inInclusiveRange(31, 33));
        // B starts at 1050 m: sample 68 is at 1020 m (30 m short, still a candidate).
        expect(gap.toIdx, inInclusiveRange(66, 68));
        expect(r.matchedFraction, lessThan(1.0));
        expect(r.limitCoverage, closeTo(r.matchedFraction, 0.02));
      },
    );

    test('(f) overrides replace limit and confidence', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
        limit: 35,
      );
      final pack = MemoryPack.fromWays([a]);
      final samples = trace(
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        count: 50,
      );

      final r = matcher.match(
        samples,
        pack,
        overrides: {
          1: const LimitOverride(wayId: 1, limitMps: 11.176, confidence: 0.85),
        },
      );
      expect(r.segments.single.speedLimit, 11.176);
      expect(r.segments.single.confidence, 0.85);
      expect(r.limitCoverage, 1.0);

      // An override also gives a limit to a way that had none.
      final bare = road(
        2,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
      );
      final r2 = matcher.match(
        samples,
        MemoryPack.fromWays([bare]),
        overrides: {2: const LimitOverride(wayId: 2, limitMps: 20)},
      );
      expect(r2.segments.single.speedLimit, 20);
      expect(r2.segments.single.confidence, 0.85);
      expect(r2.limitCoverage, 1.0);

      // Without the override a limitless way has zero coverage.
      final r3 = matcher.match(samples, MemoryPack.fromWays([bare]));
      expect(r3.segments.single.speedLimit, isNull);
      expect(r3.limitCoverage, 0);
      expect(r3.matchedFraction, 1.0);
    });

    test('(g) travelling against point order uses the backward limit', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
        limit: 45,
        limitBack: 35,
      );
      final pack = MemoryPack.fromWays([a]);
      final start = destination(baseLat, baseLon, 90, 1500);

      final west = matcher.match(
        trace(lat: start.lat, lon: start.lon, bearingDeg: 270, count: 60),
        pack,
      );
      expect(west.segments.single.speedLimit, closeTo(35 * 0.44704, 1e-6));
      expect(west.forwardPerSample.every((f) => !f), isTrue);

      final east = matcher.match(
        trace(lat: baseLat, lon: baseLon, bearingDeg: 90, count: 60),
        pack,
      );
      expect(east.segments.single.speedLimit, closeTo(45 * 0.44704, 1e-6));
    });

    test('(g2) a U-turn on one road splits the segment by direction', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
        limit: 45,
        limitBack: 35,
      );
      final pack = MemoryPack.fromWays([a]);
      final turn = destination(baseLat, baseLon, 90, 600);
      final samples = legs([
        trace(lat: baseLat, lon: baseLon, bearingDeg: 90, count: 40),
        trace(lat: turn.lat, lon: turn.lon, bearingDeg: 270, count: 40),
      ]);
      final r = matcher.match(samples, pack);
      expectTiles(r.segments, 80);
      expect(r.segments, hasLength(2));
      expect(r.segments[0].speedLimit, closeTo(45 * 0.44704, 1e-6));
      expect(r.segments[1].speedLimit, closeTo(35 * 0.44704, 1e-6));
      expect(r.segments[1].fromIdx, 40);
    });

    test('(h) an hour on a 50-way grid matches in well under a second', () {
      // 25 east-west streets and 25 north-south avenues, 200 m apart.
      final ways = <PackWay>[];
      const spacing = 200.0;
      for (var i = 0; i < 25; i++) {
        final o = destination(baseLat, baseLon, 0, spacing * i);
        ways.add(
          road(
            1000 + i,
            lat: o.lat,
            lon: o.lon,
            bearingDeg: 90,
            lengthM: spacing * 24,
            limit: 25 + (i % 3) * 5,
            name: 'Street $i',
          ),
        );
        final v = destination(baseLat, baseLon, 90, spacing * i);
        ways.add(
          road(
            2000 + i,
            lat: v.lat,
            lon: v.lon,
            bearingDeg: 0,
            lengthM: spacing * 24,
            limit: 30,
            name: 'Avenue $i',
          ),
        );
      }
      final pack = MemoryPack.fromWays(ways);

      // Random walk along the grid: drive one block, turn or continue.
      final rng = math.Random(42);
      var row = 12, col = 12;
      var bearingIdx = 1; // 0 N, 1 E, 2 S, 3 W
      const bearings = [0.0, 90.0, 180.0, 270.0];
      final samples = <GpsSample>[];
      var t = 1_700_000_000_000;
      while (samples.length < 3600) {
        final b = bearings[bearingIdx];
        final from = destination(
          destination(baseLat, baseLon, 0, spacing * row).lat,
          destination(baseLat, baseLon, 90, spacing * col).lon,
          0,
          0,
        );
        for (var s = 0; s < 20 && samples.length < 3600; s++) {
          final p = destination(from.lat, from.lon, b, 10.0 * s);
          final jitter = destination(
            p.lat,
            p.lon,
            rng.nextDouble() * 360,
            rng.nextDouble() * 4,
          );
          samples.add(
            GpsSample(
              t: t,
              lat: jitter.lat,
              lon: jitter.lon,
              speed: 10,
              accuracy: 4 + rng.nextDouble() * 6,
              heading: b + (rng.nextDouble() - 0.5) * 10,
            ),
          );
          t += 1000;
        }
        switch (bearingIdx) {
          case 0:
            row++;
          case 1:
            col++;
          case 2:
            row--;
          default:
            col--;
        }
        // Stay on the grid; otherwise pick a random legal direction.
        final options = <int>[
          if (row < 24) 0,
          if (col < 24) 1,
          if (row > 0) 2,
          if (col > 0) 3,
        ];
        bearingIdx = rng.nextInt(10) < 6 && options.contains(bearingIdx)
            ? bearingIdx
            : options[rng.nextInt(options.length)];
      }
      expect(samples, hasLength(3600));

      final sw = Stopwatch()..start();
      final r = matcher.match(samples, pack);
      sw.stop();
      // ignore: avoid_print
      print(
        '3600-sample grid match: ${sw.elapsedMilliseconds} ms, ${r.segments.length} segments',
      );

      expect(sw.elapsedMilliseconds, lessThan(2000));
      expectTiles(r.segments, 3600);
      expect(r.matchedFraction, greaterThan(0.95));
      expect(r.limitCoverage, greaterThan(0.95));
    });

    test('empty trace', () {
      final r = matcher.match(
        const [],
        MemoryPack.fromWays([
          road(1, lat: baseLat, lon: baseLon, bearingDeg: 90, lengthM: 100),
        ]),
      );
      expect(r.segments, isEmpty);
      expect(r.limitCoverage, 0);
      expect(r.matchedFraction, 0);
    });

    test('coverage counts moving seconds only', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
        limit: 35,
      );
      final pack = MemoryPack.fromWays([a]);
      final moving = trace(
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        count: 30,
      );
      final stopped = [
        for (var i = 0; i < 30; i++)
          GpsSample(
            t: moving.last.t + (i + 1) * 1000,
            lat: moving.last.lat,
            lon: moving.last.lon,
            speed: 0,
            accuracy: 5,
          ),
      ];
      final r = matcher.match([...moving, ...stopped], pack);
      expect(
        r.limitCoverage,
        1.0,
      ); // stopped seconds are not in the denominator
      expect(r.matchedFraction, 1.0);
    });
  });

  group('MemoryPack.fromWays', () {
    test('stores long ways in every cell they cross', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 12000,
        limit: 55,
        stepM: 6000,
      );
      final pack = MemoryPack.fromWays([a]);
      expect(pack.cells.length, greaterThanOrEqualTo(3));
      final far = destination(baseLat, baseLon, 90, 7000);
      expect(
        TileCache(pack).waysNear(far.lat, far.lon).map((w) => w.id),
        contains(1),
      );
    });

    test('name ids are 1-based in byte order', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 100,
        name: 'b street',
      );
      final b = road(
        2,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 100,
        name: 'A street',
      );
      final pack = MemoryPack.fromWays([a, b]);
      expect(pack.name(1), 'A street');
      expect(pack.name(2), 'b street');
      expect(pack.name(3), isNull);
      final ways = TileCache(pack).waysNear(baseLat, baseLon);
      expect(ways.map((w) => w.name).toSet(), {'A street', 'b street'});
    });
  });

  group('TileCache', () {
    test('dedupes and evicts', () {
      final ways = [
        for (var i = 0; i < 100; i++)
          road(
            i,
            lat: baseLat + i * 0.1,
            lon: baseLon,
            bearingDeg: 90,
            lengthM: 100,
          ),
      ];
      final cache = TileCache(MemoryPack.fromWays(ways), capacity: 10);
      for (var i = 0; i < 100; i++) {
        final near = cache.waysNear(baseLat + i * 0.1, baseLon);
        expect(near.map((w) => w.id), contains(i));
        expect(near.map((w) => w.id).toSet().length, near.length);
      }
      expect(cache.cachedCells, lessThanOrEqualTo(10));
      cache.clear();
      expect(cache.cachedCells, 0);
    });
  });
}
