import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/sync/limit_flags_sync.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

/// Serves whatever rows it is given, ignoring the watermark.
class _Overrides implements OverridesSource {
  List<Map<String, dynamic>> rows = [];

  @override
  Future<List<Map<String, dynamic>>> fetch(
    String region, {
    String? since,
  }) async => rows;
}

Map<String, dynamic> _row(int wayId, String updatedAt) => {
  'way_id': wayId,
  'limit_mps': 15.6,
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

  Future<void> flag(AppDatabase db, int way, int createdAt) => db.addLimitFlag(
    LimitFlagsCompanion.insert(
      wayId: '$way',
      region: const Value('us-dc'),
      suggestedMps: 15.6,
      createdAt: createdAt,
    ),
  );

  test(
    'Snitch: a pulled override for a way you flagged counts once; ten earn it',
    () async {
      final db = await dbWithPack();
      addTearDown(db.close);
      var now = DateTime.utc(2026, 11, 3, 12).millisecondsSinceEpoch;
      final totals = <int>[];
      final src = _Overrides();
      final sync = LimitFlagsSync(
        db,
        OutboxWorker(db, now: () => now),
        null,
        now: () => now,
        overrides: src,
        onConfirmedFlags: (n) async => totals.add(n),
      );

      // Nine flags from yesterday on ways 1–9, and one on way 10 raised
      // *after* its override was committed: it agrees but did not cause it.
      for (var way = 1; way <= 9; way++) {
        await flag(db, way, now - day);
      }
      await flag(db, 10, now);
      src.rows = [
        for (var way = 1; way <= 9; way++)
          _row(way, '2026-11-03T11:00:00.000Z'),
        _row(10, '2026-11-03T10:00:00.000Z'),
        _row(99, '2026-11-03T11:00:00.000Z'), // nobody here flagged it
      ];
      expect(await sync.pullIfDue(), ['us-dc']);
      expect(totals, [9], reason: 'way 10 was flagged after its override');
      expect((await sync.confirmedFlagIds()).length, 9);

      // The same overrides again (a forced full refresh) add nothing.
      now += 8 * day;
      expect(await sync.pullIfDue(force: true), ['us-dc']);
      expect(totals, [9]);

      // A tenth confirmation arrives: the callback crosses the threshold.
      await flag(db, 11, now);
      src.rows.add(_row(11, '2026-11-11T13:00:00.000Z'));
      now += day;
      expect(await sync.pullIfDue(), ['us-dc']);
      expect(totals, [9, 10]);
      expect(LimitFlagsSync.snitchConfirmations, 10);
    },
    skip: skip,
  );

  test('no flags, no callback; a region-less flag still matches', () async {
    final db = await dbWithPack();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 11, 3, 12).millisecondsSinceEpoch;
    final totals = <int>[];
    final src = _Overrides()..rows = [_row(5, '2026-11-03T11:00:00.000Z')];
    final sync = LimitFlagsSync(
      db,
      OutboxWorker(db, now: () => now),
      null,
      now: () => now,
      overrides: src,
      onConfirmedFlags: (n) async => totals.add(n),
    );
    expect(await sync.pullIfDue(), ['us-dc']);
    expect(totals, isEmpty);

    await db.addLimitFlag(
      LimitFlagsCompanion.insert(wayId: '5', suggestedMps: 15.6, createdAt: 1),
    );
    expect(await sync.pullIfDue(force: true), ['us-dc']);
    expect(totals, [1]);
  }, skip: skip);
}
