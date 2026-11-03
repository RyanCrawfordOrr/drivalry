import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/garage/fuel_math.dart';
import 'package:flutter_test/flutter_test.dart';

FuelEntry entry({
  required String id,
  required int at,
  required double litres,
  double? odoKm,
  bool full = true,
  int? cents,
}) => FuelEntry(
  id: id,
  vehicleId: 'v',
  at: at,
  odometerKm: odoKm,
  litres: litres,
  costCents: cents,
  currency: 'USD',
  fullTank: full,
);

void main() {
  group('computeFuelStats', () {
    test('two full tanks make one segment', () {
      final stats = computeFuelStats([
        entry(id: 'a', at: 1, litres: 40, odoKm: 10000, cents: 6000),
        entry(id: 'b', at: 2, litres: 35, odoKm: 10500, cents: 5250),
      ]);
      expect(stats.segments, hasLength(1));
      final seg = stats.segments.single;
      expect(seg.km, 500);
      expect(seg.litres, 35);
      expect(seg.lPer100km, closeTo(7.0, 1e-9));
      // 500 km = 310.686 mi; 35 L = 9.246 gal → 33.6 mpg
      expect(seg.mpgUs, closeTo(33.6, 0.1));
      expect(stats.lPer100km, closeTo(7.0, 1e-9));
      expect(stats.totalLitres, 75);
      expect(stats.totalCostCents, 11250);
      expect(stats.costCentsPerKm, closeTo(5250 / 500, 1e-9));
    });

    test('partial fill-ups add fuel to the next full tank', () {
      final stats = computeFuelStats([
        entry(id: 'a', at: 1, litres: 40, odoKm: 1000),
        entry(id: 'p', at: 2, litres: 10, odoKm: 1200, full: false),
        entry(id: 'b', at: 3, litres: 30, odoKm: 1500),
      ]);
      expect(stats.segments, hasLength(1));
      expect(stats.segments.single.litres, 40);
      expect(stats.segments.single.km, 500);
      expect(stats.lPer100km, closeTo(8.0, 1e-9));
    });

    test('a full tank without odometer breaks the chain', () {
      final stats = computeFuelStats([
        entry(id: 'a', at: 1, litres: 40, odoKm: 1000),
        entry(id: 'x', at: 2, litres: 38),
        entry(id: 'b', at: 3, litres: 30, odoKm: 1500),
      ]);
      expect(stats.segments, isEmpty);
      expect(stats.hasEconomy, isFalse);
      expect(formatEconomy(stats.lPer100km, useMpg: true), '–');
    });

    test('odometer going backwards restarts the chain', () {
      final stats = computeFuelStats([
        entry(id: 'a', at: 1, litres: 40, odoKm: 2000),
        entry(id: 'b', at: 2, litres: 40, odoKm: 1500),
        entry(id: 'c', at: 3, litres: 20, odoKm: 1800),
      ]);
      expect(stats.segments, hasLength(1));
      expect(stats.segments.single.from.id, 'b');
      expect(stats.segments.single.km, 300);
    });

    test('order of input does not matter', () {
      final a = entry(id: 'a', at: 1, litres: 40, odoKm: 1000);
      final b = entry(id: 'b', at: 2, litres: 30, odoKm: 1500);
      expect(computeFuelStats([b, a]).segments.single.from.id, 'a');
    });

    test('empty input', () {
      expect(computeFuelStats(const []).entries, 0);
      expect(computeFuelStats(const []).segments, isEmpty);
    });
  });

  test('unit conversions and formatting', () {
    expect(litresToUsGallons(usGallonsToLitres(5)), closeTo(5, 1e-12));
    expect(kmToMiles(milesToKm(7)), closeTo(7, 1e-12));
    expect(formatEconomy(7.0, useMpg: false), '7.0 L/100 km');
    expect(formatEconomy(7.0, useMpg: true), '33.6 mpg');
    expect(formatVolume(37.85411784, useGallons: true), '10.0 gal');
    expect(formatVolume(12.34, useGallons: false), '12.3 L');
    expect(formatCents(4210), '42.10');
  });
}
