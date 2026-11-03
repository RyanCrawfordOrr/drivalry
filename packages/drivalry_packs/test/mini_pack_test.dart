import 'dart:io';

import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show RoadClass;
import 'package:test/test.dart';

import 'sqlite_support.dart';

/// Cross-language golden test: the Python builder in `tools/packs` turns
/// `tests/vectors/mini.osm` into the committed `mini.pack`; this reader must
/// decode every way in it exactly as `docs/07-pack-format.md` says.
void main() {
  final sep = Platform.pathSeparator;
  final path =
      '${repoRoot().path}${sep}tools${sep}packs${sep}tests${sep}vectors${sep}mini.pack';
  final skip =
      sqliteSkipReason() ??
      (File(path).existsSync() ? null : 'no vector at $path');

  group('mini.pack', () {
    late SqlitePack pack;
    late Map<int, PackWay> ways;

    setUpAll(() {
      pack = SqlitePack.open(path);
      final near = TileCache(pack).waysNear(38.9050, -77.0300);
      ways = {for (final w in near) w.id: w};
    });
    tearDownAll(() => pack.close());

    test('meta', () {
      expect(pack.meta['schema_version'], '1');
      expect(pack.meta['region'], 'test-mini');
      expect(pack.meta['geohash_precision'], '5');
      expect(pack.meta['way_count'], '17');
      expect(pack.meta['osm_replication_timestamp'], '');
      expect(pack.meta['bbox'], isNotNull);
    });

    test('kept and dropped ways', () {
      expect(ways.keys.toList()..sort(), [
        101,
        102,
        103,
        104,
        105,
        106,
        107,
        108,
        109,
        110,
        113,
        114,
        116,
        117,
        118,
        119,
        120,
      ]);
    });

    test('mph tag, collinear node simplified away', () {
      final w = ways[101]!;
      expect(w.name, 'Oak Street');
      expect(w.roadClass, RoadClass.residential);
      expect(w.mph, isTrue);
      expect(w.maxForward, 25);
      expect(w.maxBackward, isNull);
      expect(w.source, LimitSource.tag);
      expect(w.confidence, 0.9);
      expect(w.limitMps(forward: true), closeTo(25 * 0.44704, 1e-9));
      expect(w.lats.length, 2);
    });

    test('km/h tag', () {
      final w = ways[102]!;
      expect(w.mph, isFalse);
      expect(w.maxForward, 50);
      expect(w.roadClass, RoadClass.secondary);
      expect(w.limitMps(forward: true), closeTo(50 / 3.6, 1e-9));
    });

    test('forward and backward differ', () {
      final w = ways[103]!;
      expect(w.maxForward, 45);
      expect(w.maxBackward, 35);
      expect(w.limitMps(forward: false), closeTo(35 * 0.44704, 1e-9));
      expect(w.roadClass, RoadClass.primary);
    });

    test('backward-only limit, unnamed', () {
      final w = ways[104]!;
      expect(w.name, isNull);
      expect(w.maxForward, isNull);
      expect(w.maxBackward, 30);
      expect(w.limitMps(forward: true), isNull);
      expect(w.limitMps(forward: false), closeTo(30 * 0.44704, 1e-9));
      expect(w.roadClass, RoadClass.tertiary);
    });

    test('no limit', () {
      final w = ways[105]!;
      expect(w.maxForward, isNull);
      expect(w.source, LimitSource.none);
      expect(w.confidence, 0);
      expect(w.limitMps(forward: true), isNull);
    });

    test('implied zone limit', () {
      final w = ways[106]!;
      expect(w.source, LimitSource.implied);
      expect(w.confidence, 0.5);
      expect(w.maxForward, 20);
      expect(w.mph, isTrue);
    });

    test('oneway variants', () {
      expect(ways[107]!.oneway, 1);
      expect(ways[108]!.oneway, 2);
      expect(ways[109]!.oneway, 1, reason: 'motorway implies oneway');
      expect(ways[109]!.roadClass, RoadClass.motorway);
      expect(ways[109]!.name, 'I-395');
      expect(ways[118]!.oneway, 0, reason: 'explicit oneway=no wins');
      expect(ways[118]!.roadClass, RoadClass.motorway);
    });

    test('roundabout keeps its closed ring', () {
      final w = ways[110]!;
      expect(w.roundabout, isTrue);
      expect(w.oneway, 1);
      expect(w.lats.length, 5);
      expect(w.lats.first, w.lats.last);
      expect(w.lons.first, w.lons.last);
    });

    test('kept service road', () {
      expect(ways[113]!.roadClass, RoadClass.service);
      expect(ways[113]!.name, 'Alley Service');
    });

    test('long way is simplified and appears in several cells', () {
      final w = ways[114]!;
      expect(w.name, 'Long Pike');
      expect(w.roadClass, RoadClass.trunk);
      expect(w.lats.length, 4);
      expect(w.lons.first, closeTo(-77.12, 1e-6));
      expect(w.lons.last, closeTo(-76.94, 1e-6));
      final farWest = TileCache(pack).waysNear(38.9050, -77.1150);
      expect(farWest.map((x) => x.id), contains(114));
    });

    test('utf-8 name and maxspeed=none', () {
      final w = ways[116]!;
      expect(w.name, 'Émile Way');
      expect(w.maxForward, isNull);
      expect(w.source, LimitSource.none);
    });

    test('list value takes the first entry', () {
      expect(ways[117]!.maxForward, 30);
      expect(ways[117]!.mph, isTrue);
      expect(ways[117]!.roadClass, RoadClass.unclassified);
    });

    test('equal forward and backward collapse to one limit', () {
      expect(ways[119]!.maxForward, 15);
      expect(ways[119]!.maxBackward, isNull);
      expect(ways[119]!.roadClass, RoadClass.residential);
    });

    test('forward-only limit applies to both directions', () {
      final w = ways[120]!;
      expect(w.maxForward, 40);
      expect(w.maxBackward, isNull);
      expect(w.limitMps(forward: false), closeTo(40 * 0.44704, 1e-9));
      expect(w.roadClass, RoadClass.primary);
    });
  }, skip: skip);
}
