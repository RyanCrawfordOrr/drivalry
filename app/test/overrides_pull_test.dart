import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/sync/limit_flags_sync.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

/// Serves override rows and records the watermark it was asked for.
class FakeOverrides implements OverridesSource {
  List<Map<String, dynamic>> rows = [];
  final List<String?> sinceArgs = [];

  @override
  Future<List<Map<String, dynamic>>> fetch(
    String region, {
    String? since,
  }) async {
    sinceArgs.add(since);
    if (since == null) return rows;
    final cut = DateTime.parse(since);
    return [
      for (final r in rows)
        if (DateTime.parse(r['updated_at'] as String).isAfter(cut)) r,
    ];
  }
}

Map<String, dynamic> row(int wayId, double mps, String updatedAt) => {
  'way_id': wayId,
  'limit_mps': mps,
  'confidence': 0.85,
  'updated_at': updatedAt,
};

void main() {
  final skip = skipWithoutSqlite();
  const day = 24 * 3600 * 1000;

  Future<AppDatabase> dbWithPack() async {
    final db = memoryDatabase();
    await db.upsertPack(
      PacksCompanion.insert(
        region: 'us-dc',
        name: 'DC',
        osmTimestamp: 'x',
        path: '/x',
        sha256: 'y',
        bytes: 1,
        wayCount: 1,
        bboxMinLat: 38,
        bboxMinLon: -78,
        bboxMaxLat: 39,
        bboxMaxLon: -76,
        installedAt: 1,
      ),
    );
    return db;
  }

  test('watermark comes from the server rows, not the phone clock', () async {
    final db = await dbWithPack();
    addTearDown(db.close);
    // Phone clock three minutes ahead of the server.
    var now = DateTime.utc(2026, 11, 3, 12, 3).millisecondsSinceEpoch;
    final src = FakeOverrides()
      ..rows = [row(1, 15.6, '2026-11-03T11:59:00.000Z')];
    final sync = LimitFlagsSync(
      db,
      OutboxWorker(db, now: () => now),
      null,
      now: () => now,
      overrides: src,
    );

    expect(await sync.pullIfDue(), ['us-dc']);
    expect(src.sinceArgs, [null], reason: 'first pull is a full fetch');
    expect((await cachedOverrides(db, 'us-dc')).keys, [1]);

    // A row the server committed at 11:58:30 (before the pull, after the
    // phone-clock watermark 12:03 would have been) still arrives next time.
    src.rows.add(row(2, 11.2, '2026-11-03T11:58:30.000Z'));
    now += day;
    expect(await sync.pullIfDue(), ['us-dc']);
    expect(
      src.sinceArgs.last,
      '2026-11-03T11:58:00.000Z',
      reason: 'newest updated_at minus 60 s of slack',
    );
    expect((await cachedOverrides(db, 'us-dc')).keys, containsAll([1, 2]));

    // Not due again until tomorrow.
    expect(await sync.pullIfDue(), isEmpty);
  }, skip: skip);

  test(
    'a weekly full refresh drops overrides retracted on the server',
    () async {
      final db = await dbWithPack();
      addTearDown(db.close);
      var now = DateTime.utc(2026, 11, 3).millisecondsSinceEpoch;
      final src = FakeOverrides()
        ..rows = [
          row(1, 15.6, '2026-11-01T00:00:00.000Z'),
          row(2, 11.2, '2026-11-02T00:00:00.000Z'),
        ];
      final sync = LimitFlagsSync(
        db,
        OutboxWorker(db, now: () => now),
        null,
        now: () => now,
        overrides: src,
      );
      await sync.pullIfDue();
      expect((await cachedOverrides(db, 'us-dc')).keys, containsAll([1, 2]));

      // Way 2 is retracted. Incremental pulls cannot see a deletion...
      src.rows.removeWhere((r) => r['way_id'] == 2);
      now += day;
      await sync.pullIfDue();
      expect((await cachedOverrides(db, 'us-dc')).keys, containsAll([1, 2]));

      // ...the weekly full refresh does.
      now += 7 * day;
      await sync.pullIfDue();
      expect(src.sinceArgs.last, isNull);
      expect((await cachedOverrides(db, 'us-dc')).keys, [1]);
    },
    skip: skip,
  );
}
