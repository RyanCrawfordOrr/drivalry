import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:test/test.dart';

void main() {
  group('Geohash.encode', () {
    test('known vectors', () {
      expect(Geohash.encode(42.6, -5.6), 'ezs42');
      expect(Geohash.encode(57.64911, 10.40744, precision: 11), 'u4pruydqqvj');
      // The White House. (dqcjr is the cell just east of it.)
      expect(Geohash.encode(38.8977, -77.0365), 'dqcjq');
      expect(Geohash.encode(0, 0, precision: 1), 's');
      expect(Geohash.encode(-90, -180, precision: 3), '000');
    });

    test('rejects bad precision', () {
      expect(() => Geohash.encode(0, 0, precision: 0), throwsArgumentError);
      expect(() => Geohash.encode(0, 0, precision: 13), throwsArgumentError);
    });
  });

  group('Geohash.decode', () {
    test('round trips the centre of a cell', () {
      for (final h in ['ezs42', 'dqcjq', 'u4pruydqqvj', 's', '000', 'zzzzz']) {
        final box = Geohash.decode(h);
        expect(
          Geohash.encode(box.centerLat, box.centerLon, precision: h.length),
          h,
        );
        expect(box.contains(box.centerLat, box.centerLon), isTrue);
      }
    });

    test('precision 5 cells are about 4.9 km x 4.9 km at the equator', () {
      final box = Geohash.decode('s0000');
      expect(box.latSize * 111.19, closeTo(4.89, 0.05));
      expect(box.lonSize * 111.19, closeTo(4.89, 0.05));
    });

    test('rejects bad characters', () {
      expect(() => Geohash.decode('abc'), throwsArgumentError); // 'a' invalid
      expect(() => Geohash.decode(''), throwsArgumentError);
    });
  });

  group('Geohash.neighbors', () {
    test('dqcjr has the expected neighbours', () {
      final n = Geohash.neighbors('dqcjr');
      expect(n, hasLength(8));
      expect(n, contains('dqcjq'));
      expect(n, contains('dqcjx'));
      expect(n, isNot(contains('dqcjr')));
      expect(n.toSet(), hasLength(8));
    });

    test('every neighbour shares an edge or corner with the centre', () {
      final centre = Geohash.decode('dqcjr');
      for (final h in Geohash.neighbors('dqcjr')) {
        final b = Geohash.decode(h);
        expect(h.length, 5);
        expect(b.latSize, closeTo(centre.latSize, 1e-12));
        expect(b.lonSize, closeTo(centre.lonSize, 1e-12));
        final dLat = (b.centerLat - centre.centerLat).abs() / centre.latSize;
        final dLon = (b.centerLon - centre.centerLon).abs() / centre.lonSize;
        expect(dLat, anyOf(closeTo(0, 1e-9), closeTo(1, 1e-9)));
        expect(dLon, anyOf(closeTo(0, 1e-9), closeTo(1, 1e-9)));
        expect(dLat + dLon, greaterThan(0.5));
      }
    });

    test('wraps across the antimeridian', () {
      final n = Geohash.neighbors(Geohash.encode(10, 179.99));
      expect(n.any((h) => Geohash.decode(h).centerLon < -179), isTrue);
    });
  });
}
