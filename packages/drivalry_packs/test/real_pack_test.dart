import 'dart:io';

import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show GpsSample;
import 'package:test/test.dart';

import 'sqlite_support.dart';

/// Smoke test against a real pack built by `tools/packs` for the District of
/// Columbia. Skipped when the file is absent.
void main() {
  final sep = Platform.pathSeparator;
  final path =
      '${repoRoot().path}${sep}tools${sep}packs${sep}out${sep}us-dc.pack';
  final skip =
      sqliteSkipReason() ??
      (File(path).existsSync() ? null : 'no pack at $path');

  test('us-dc.pack: meta and the roads around the White House', () {
    final pack = SqlitePack.open(path);
    addTearDown(pack.close);
    expect(pack.meta['schema_version'], '1');
    expect(pack.meta['region'], 'us-dc');
    expect(int.parse(pack.meta['way_count']!), greaterThan(1000));

    final ways = TileCache(pack).waysNear(38.8977, -77.0365);
    expect(ways.length, greaterThan(100));
    final names = ways.map((w) => w.name).whereType<String>().toSet();
    expect(
      names.any((n) => n.contains('Pennsylvania')),
      isTrue,
      reason: 'names near the White House: ${names.take(20)}',
    );

    // 17th St NW just west of the White House, heading north.
    final m = LiveMatcher(pack).locate(
      const GpsSample(
        t: 1_700_000_000_000,
        lat: 38.8985,
        lon: -77.0398,
        speed: 10,
        accuracy: 5,
        heading: 0,
      ),
    );
    expect(m, isNotNull);
    // ignore: avoid_print
    print(
      '17th St NW match: ${m!.way.name} ${m.postedLimit ?? '-'} ${m.way.unitLabel} '
      '(${m.distanceM.toStringAsFixed(1)} m, conf ${m.confidence})',
    );
  }, skip: skip);
}
