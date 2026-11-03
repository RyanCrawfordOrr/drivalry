import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  test('resetAccountState forgets per-account sync state only', () async {
    final db = memoryDatabase();
    addTearDown(db.close);

    await db.markUploaded('t1', 'hash', 5);
    await db.awardBadge('first_trip', 5);
    await db.markBadgeSynced('first_trip');
    await db.enqueueOutbox(
      OutboxCompanion(
        id: const Value('row'),
        kind: const Value('anything'),
        payload: const Value('{}'),
        createdAt: const Value(5),
      ),
    );
    await db.cachePut('feed:all:0', '[]', 5);
    await db.setSetting('location_hidden', 'true');
    await db.setSetting('units', 'kmh');

    await db.resetAccountState();

    expect(await db.uploadedTrip('t1'), isNull);
    expect(
      (await db.badgeAward('first_trip'))!.synced,
      isFalse,
      reason: 'the award itself survives, its sync mark does not',
    );
    expect(await db.dueOutbox(1 << 40), isEmpty);
    expect(await db.cacheGet('feed:all:0'), isNull);
    expect(await db.getSetting('location_hidden'), isNull);
    expect(
      await db.getSetting('units'),
      'kmh',
      reason: 'device settings are not account state',
    );
  }, skip: skip);
}
