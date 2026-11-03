import 'dart:io';

import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'sqlite_support.dart';
import 'support.dart';

void main() {
  final skip = sqliteSkipReason();

  group('SqlitePack', () {
    late Directory tmp;
    late String path;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('drivalry_packs_');
      path = '${tmp.path}${Platform.pathSeparator}test.pack';
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    /// Writes a pack file following docs/07 §1 from an in-memory pack.
    void writePack(
      MemoryPack mem,
      String path, {
      Map<String, String>? metaOverride,
    }) {
      final db = sqlite3.open(path);
      db.execute('PRAGMA page_size = 4096');
      db.execute(
        'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      db.execute(
        'CREATE TABLE names (name_id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      db.execute(
        'CREATE TABLE tiles (geohash TEXT PRIMARY KEY, ways BLOB NOT NULL)',
      );
      final meta = {...mem.meta, 'region': 'us-test', ...?metaOverride};
      final metaStmt = db.prepare('INSERT INTO meta VALUES (?, ?)');
      for (final e in meta.entries) {
        metaStmt.execute([e.key, e.value]);
      }
      metaStmt.close();
      final nameStmt = db.prepare('INSERT INTO names VALUES (?, ?)');
      for (var id = 1; mem.name(id) != null; id++) {
        nameStmt.execute([id, mem.name(id)]);
      }
      nameStmt.close();
      final tileStmt = db.prepare('INSERT INTO tiles VALUES (?, ?)');
      for (final cell in mem.cells) {
        tileStmt.execute([cell, mem.tileBlob(cell)]);
      }
      tileStmt.close();
      db.close();
    }

    test('opens, reads meta, names and tiles, and matches', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 2000,
        limit: 35,
        name: 'K Street',
      );
      final b = road(
        2,
        lat: baseLat + 0.01,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 500,
        limit: 25,
        name: 'M Street',
      );
      writePack(MemoryPack.fromWays([a, b]), path);

      final pack = SqlitePack.open(path);
      addTearDown(pack.close);
      expect(pack.meta['schema_version'], '1');
      expect(pack.region, 'us-test');
      expect(pack.name(1), 'K Street');
      expect(pack.name(2), 'M Street');
      expect(pack.name(99), isNull);
      expect(pack.tileCount, greaterThanOrEqualTo(1));
      expect(pack.tileBlob('00000'), isNull);

      final ways = TileCache(pack).waysNear(baseLat, baseLon);
      expect(ways.map((w) => w.id).toSet(), containsAll([1, 2]));
      expect(ways.firstWhere((w) => w.id == 1).name, 'K Street');

      final r = const RoadMatcher().match(
        trace(lat: baseLat, lon: baseLon, bearingDeg: 90, count: 50),
        pack,
      );
      expect(r.segments.single.wayId, '1');
      expect(r.segments.single.name, 'K Street');
      expect(r.segments.single.speedLimit, closeTo(35 * 0.44704, 1e-6));
      expect(r.limitCoverage, 1.0);
    });

    test('refuses an unknown schema version and leaves the file closed', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 200,
      );
      writePack(
        MemoryPack.fromWays([a]),
        path,
        metaOverride: {'schema_version': '99'},
      );
      expect(
        () => SqlitePack.open(path),
        throwsA(isA<UnsupportedPackException>()),
      );
      // Still deletable: the handle was released.
      File(path).deleteSync();
    });

    test('throws after close', () {
      final a = road(
        1,
        lat: baseLat,
        lon: baseLon,
        bearingDeg: 90,
        lengthM: 200,
      );
      writePack(MemoryPack.fromWays([a]), path);
      final pack = SqlitePack.open(path);
      pack.close();
      pack.close(); // idempotent
      expect(() => pack.tileBlob('dqcjq'), throwsStateError);
    });
  }, skip: skip);
}
