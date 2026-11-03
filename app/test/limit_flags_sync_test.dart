import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/sync/limit_flags_sync.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  test('decodeOverrides builds LimitOverride entries', () {
    final m = decodeOverrides(
      jsonEncode({
        '123': {'limit_mps': 15.6464, 'confidence': 0.85},
        '456': {'limit_mps': 11.176},
        'junk': 1,
      }),
    );
    expect(m.keys, containsAll([123, 456]));
    expect(m[123]!.limitMps, closeTo(15.6464, 1e-9));
    expect(m[123]!.confidence, 0.85);
    expect(m[456]!.confidence, cloudOverrideConfidence);
    expect(m.containsKey(0), isFalse);
  });

  test('cachedOverrides reads the region cache', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    expect(await cachedOverrides(db, 'us-dc'), isEmpty);
    await db.cachePut(
      overridesCacheKey('us-dc'),
      jsonEncode({
        '7': {'limit_mps': 20.0, 'confidence': 0.85},
      }),
      1,
    );
    final m = await cachedOverrides(db, 'us-dc');
    expect(m[7]!.limitMps, 20.0);
  }, skip: skip);

  test(
    'an unsynced flag is queued with posted units and marked synced',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final outbox = OutboxWorker(db, now: () => 1);
      addTearDown(outbox.dispose);
      final sent = <Map<String, dynamic>>[];
      outbox.register(LimitFlagsSync.kindFlag, (p) async {
        sent.add(p);
        await db.markLimitFlagSynced((p['flag_id'] as num).toInt());
      });
      final sync = LimitFlagsSync(db, outbox, null, now: () => 1);
      sync.start();
      addTearDown(sync.stop);

      await db.addLimitFlag(
        LimitFlagsCompanion.insert(
          wayId: '98765',
          region: const Value('us-dc'),
          suggestedMps: 35 * 0.44704,
          createdAt: 1,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await outbox.drain();

      expect(sent.length, 1);
      final p = sent.single;
      expect(p['way_id'], 98765);
      expect(p['region'], 'us-dc');
      expect(p['suggested_mph'], isTrue);
      expect(p['suggested_value'], 35);
      expect(await db.watchUnsyncedLimitFlags().first, isEmpty);
    },
    skip: skip,
  );
}
