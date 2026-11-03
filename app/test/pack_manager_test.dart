import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/packs/pack_manager.dart';
import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import 'support/sqlite_support.dart';

/// Writes a real schema-1 pack file from an in-memory pack.
File writePackFile(Directory dir, String name, MemoryPack pack) {
  final file = File(p.join(dir.path, name));
  final db = sql.sqlite3.open(file.path);
  db.execute('''
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE names (name_id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE tiles (geohash TEXT PRIMARY KEY, ways BLOB NOT NULL);
  ''');
  final meta = db.prepare('INSERT INTO meta VALUES (?, ?)');
  for (final e in pack.meta.entries) {
    meta.execute([e.key, e.value]);
  }
  meta.close();
  final tiles = db.prepare('INSERT INTO tiles VALUES (?, ?)');
  for (final cell in pack.cells) {
    tiles.execute([cell, pack.tileBlob(cell)]);
  }
  tiles.close();
  final names = db.prepare('INSERT INTO names VALUES (?, ?)');
  for (var i = 1; pack.name(i) != null; i++) {
    names.execute([i, pack.name(i)]);
  }
  names.close();
  db.close();
  return file;
}

MemoryPack tinyPack() {
  final end = destination(36.1627, -86.7816, 90, 2000);
  return MemoryPack.fromWays(
    [
      PackWay(
        id: 1,
        roadClass: RoadClass.primary,
        name: 'Broadway',
        lats: [36.1627, end.lat],
        lons: [-86.7816, end.lon],
        maxForward: 35,
        mph: true,
        source: LimitSource.tag,
      ),
    ],
    meta: {
      'region': 'us-tn',
      'region_name': 'Tennessee',
      'osm_replication_timestamp': '2026-10-31T00:00:00Z',
    },
  );
}

void main() {
  final skip = skipWithoutSqlite();
  late AppDatabase db;
  late Directory tmp;

  setUp(() async {
    db = memoryDatabase();
    tmp = await Directory.systemTemp.createTemp('drivalry-packs-');
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('importLocalFile reads region and bounds from the file', () async {
    final src = writePackFile(tmp, 'src.pack', tinyPack());
    final manager = PackManager(
      db,
      MockClient((_) async => http.Response('', 404)),
      indexUrl: 'https://example.test/index.json',
      packsDir: () async => Directory(p.join(tmp.path, 'packs')),
      policy: const AlwaysAllowPolicy(),
      now: () => 42,
    );
    final pack = await manager.importLocalFile(src.path);
    expect(pack.region, 'us-tn');
    expect(pack.name, 'Tennessee');
    expect(pack.bboxMinLat, lessThan(36.1627));
    expect(pack.bboxMaxLat, greaterThan(36.1627));
    expect(pack.bboxMinLon, lessThan(-86.7816));
    expect(pack.bboxMaxLon, greaterThan(-86.76));
    expect(File(pack.path).existsSync(), isTrue);
    expect(p.basename(pack.path), 'us-tn.pack');
    expect(await db.installedPacks(), hasLength(1));

    // The installed file opens and matches.
    final opened = SqlitePack.open(pack.path);
    final live = LiveMatcher(opened);
    final hit = live.locate(
      const GpsSample(
        t: 0,
        lat: 36.1627,
        lon: -86.7800,
        speed: 10,
        accuracy: 5,
        heading: 90,
      ),
    );
    expect(hit?.way.name, 'Broadway');
    opened.close();

    await manager.removeRegion('us-tn');
    expect(await db.installedPacks(), isEmpty);
    expect(File(pack.path).existsSync(), isFalse);
  }, skip: skip);

  test(
    'install verifies the hash and ensureRegionFor picks the right region',
    () async {
      final src = writePackFile(tmp, 'src.pack', tinyPack());
      final bytes = await src.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      final index = {
        'schemaVersion': 1,
        'builtAt': '2026-11-02T00:00:00Z',
        'packs': [
          {
            'region': 'us-tn',
            'name': 'Tennessee',
            'url': 'https://example.test/us-tn.pack',
            'bytes': bytes.length,
            'sha256': hash,
            'osmTimestamp': '2026-10-31T00:00:00Z',
            'wayCount': 1,
            'bbox': [34.98, -90.31, 36.68, -81.65],
          },
          {
            'region': 'us-bad',
            'name': 'Corrupt',
            'url': 'https://example.test/us-bad.pack',
            'bytes': bytes.length,
            'sha256': 'ff' * 32,
            'osmTimestamp': '2026-10-31T00:00:00Z',
            'wayCount': 1,
            'bbox': [0, 0, 1, 1],
          },
        ],
      };
      final client = MockClient((req) async {
        if (req.url.path.endsWith('index.json')) {
          return http.Response(jsonEncode(index), 200);
        }
        return http.Response.bytes(bytes, 200);
      });
      var wifi = false;
      final manager = PackManager(
        db,
        client,
        indexUrl: 'https://example.test/index.json',
        packsDir: () async => Directory(p.join(tmp.path, 'packs')),
        policy: _Policy(() => wifi),
        now: () => 42,
      );

      // Not on Wi-Fi: nothing downloads.
      expect(await manager.ensureRegionFor(36.16, -86.78), isNull);
      wifi = true;
      final progress = <double>[];
      final pack = await manager.ensureRegionFor(
        36.16,
        -86.78,
        onProgress: progress.add,
      );
      expect(pack?.region, 'us-tn');
      expect(pack?.sha256, hash);
      expect(progress.last, 1.0);
      // Already installed: no second download, same row back.
      expect((await manager.ensureRegionFor(36.16, -86.78))?.region, 'us-tn');
      // Outside every region.
      expect(await manager.ensureRegionFor(50, 10), isNull);
      // A bad hash is rejected and leaves nothing behind.
      final badEntry = (await manager.refreshIndex())!.byRegion('us-bad')!;
      await expectLater(
        manager.install(badEntry),
        throwsA(isA<PackInstallException>()),
      );
      expect(await db.packByRegion('us-bad'), isNull);
      expect(
        Directory(
          p.join(tmp.path, 'packs'),
        ).listSync().map((f) => p.basename(f.path)).toList(),
        ['us-tn.pack'],
      );
    },
    skip: skip,
  );

  test('a failed download leaves no temp file behind', () async {
    final dir = Directory(p.join(tmp.path, 'packs'));
    final client = MockClient.streaming((req, _) async {
      if (req.url.path.endsWith('missing.pack')) {
        return http.StreamedResponse(Stream.value(utf8.encode('nope')), 404);
      }
      // A 200 whose body dies after the first chunk.
      Stream<List<int>> broken() async* {
        yield List<int>.filled(1024, 7);
        throw const SocketException('connection reset');
      }

      return http.StreamedResponse(broken(), 200, contentLength: 4096);
    });
    final manager = PackManager(
      db,
      client,
      indexUrl: 'https://example.test/index.json',
      packsDir: () async => dir,
      policy: const AlwaysAllowPolicy(),
      now: () => 7,
    );

    await expectLater(
      manager.importFromUrl('https://example.test/missing.pack'),
      throwsA(isA<PackInstallException>()),
    );
    await expectLater(
      manager.importFromUrl('https://example.test/broken.pack'),
      throwsA(isA<SocketException>()),
    );
    await expectLater(
      manager.importLocalFile(p.join(tmp.path, 'does-not-exist.pack')),
      throwsA(isA<PackInstallException>()),
    );

    final leftovers = dir
        .listSync()
        .map((e) => p.basename(e.path))
        .where((n) => n.endsWith('.download'))
        .toList();
    expect(leftovers, isEmpty);
    expect(await db.installedPacks(), isEmpty);
  }, skip: skip);

  test(
    'sweepTempFiles removes stale temp files and keeps fresh ones',
    () async {
      final dir = Directory(p.join(tmp.path, 'packs'))..createSync();
      final stale = File(p.join(dir.path, 'us-xx.download'))
        ..writeAsStringSync('x');
      stale.setLastModifiedSync(
        DateTime.now().subtract(const Duration(hours: 3)),
      );
      final fresh = File(p.join(dir.path, PackManager.importTempName))
        ..writeAsStringSync('y');
      final real = File(p.join(dir.path, 'us-tn.pack'))..writeAsStringSync('z');
      real.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 40)),
      );
      final manager = PackManager(
        db,
        MockClient((_) async => http.Response('', 404)),
        indexUrl: 'https://example.test/index.json',
        packsDir: () async => dir,
        policy: const AlwaysAllowPolicy(),
      );
      expect(await manager.sweepTempFiles(), 1);
      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      expect(
        real.existsSync(),
        isTrue,
        reason: 'installed packs are never swept',
      );
    },
    skip: skip,
  );
}

class _Policy implements DownloadPolicy {
  _Policy(this.allow);
  final bool Function() allow;

  @override
  Future<bool> allowsLargeDownload() async => allow();
}
