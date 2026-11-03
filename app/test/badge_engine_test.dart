import 'dart:convert';

import 'package:drivalry/data/badges/badge_engine.dart';
import 'package:drivalry/data/badges/badges_sync.dart';
import 'package:drivalry/data/badges/badge_defs.dart';
import 'package:drivalry/data/badges/streaks.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scored_trips.dart';
import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();
  const day = 24 * 60 * 60 * 1000;
  final t0 = DateTime(2026, 10, 1, 8).millisecondsSinceEpoch;

  late AppDatabase db;
  late List<String> awarded;
  late BadgeEngine engine;

  setUp(() {
    db = memoryDatabase();
    awarded = [];
    engine = BadgeEngine(
      db,
      onAwarded: (id, _) async => awarded.add(id),
      now: () => t0 + 100 * day,
    );
  });
  tearDown(() => db.close());

  Future<List<String>> run() async =>
      engine.evaluate(await db.scoredTripsWithScores());

  group('BadgeEngine', () {
    test('first_trip after the first scored trip, and only once', () async {
      expect(await run(), isEmpty);
      await seedScoredTrip(db, id: 't1', startedAt: t0);
      expect(await run(), ['first_trip']);
      expect(await run(), isEmpty, reason: 'idempotent');
      expect(awarded, ['first_trip']);
      expect((await db.allBadgeAwards()).single.badgeId, 'first_trip');
    });

    test(
      'clean_5 needs five consecutive clean trips; a reckless one resets',
      () async {
        for (var i = 0; i < 4; i++) {
          await seedScoredTrip(
            db,
            id: 't$i',
            startedAt: t0 + i * day,
            score: 85,
          );
        }
        expect(await run(), isNot(contains('clean_5')));
        await seedScoredTrip(db, id: 't4', startedAt: t0 + 4 * day, score: 80);
        expect(await run(), contains('clean_5'));

        // A later reckless trip breaks the streak for the badge rule, but the
        // award stays.
        await seedScoredTrip(
          db,
          id: 't5',
          startedAt: t0 + 5 * day,
          score: 20,
          reckless: true,
        );
        expect(await run(), isEmpty);
        final streaks = computeStreaks(
          ScoredTripParser().parse(await db.scoredTripsWithScores()),
        );
        expect(streaks.clean, 0);
      },
    );

    test('clean_20 after twenty', () async {
      for (var i = 0; i < 20; i++) {
        await seedScoredTrip(db, id: 't$i', startedAt: t0 + i * day, score: 91);
      }
      final got = await run();
      expect(got, containsAll(['first_trip', 'clean_5', 'clean_20']));
    });

    test(
      'phone_free_10 counts consecutive trips without phone handling',
      () async {
        for (var i = 0; i < 10; i++) {
          await seedScoredTrip(
            db,
            id: 't$i',
            startedAt: t0 + i * day,
            phoneHandling: i == 0,
          );
        }
        expect(await run(), isNot(contains('phone_free_10')));
        await seedScoredTrip(db, id: 't10', startedAt: t0 + 10 * day);
        expect(await run(), contains('phone_free_10'));
      },
    );

    test('perfect_100', () async {
      await seedScoredTrip(db, id: 't1', startedAt: t0, score: 99);
      expect(await run(), isNot(contains('perfect_100')));
      await seedScoredTrip(db, id: 't2', startedAt: t0 + day, score: 100);
      expect(await run(), contains('perfect_100'));
    });

    test('night_owl needs ten good night trips', () async {
      for (var i = 0; i < 10; i++) {
        await seedScoredTrip(
          db,
          id: 'n$i',
          startedAt: t0 + i * day,
          score: 86,
          nightFraction: i == 0 ? 0.2 : 0.8,
        );
      }
      expect(await run(), isNot(contains('night_owl')));
      await seedScoredTrip(
        db,
        id: 'n10',
        startedAt: t0 + 10 * day,
        score: 90,
        nightFraction: 1,
      );
      expect(await run(), contains('night_owl'));
    });

    test('rain_or_shine counts rain and snow trips at 85 or better', () async {
      for (var i = 0; i < 5; i++) {
        await seedScoredTrip(
          db,
          id: 'r$i',
          startedAt: t0 + i * day,
          score: i == 0 ? 70 : 88,
          weather: i.isEven ? 'rain' : 'snow',
        );
      }
      expect(await run(), isNot(contains('rain_or_shine')));
      await seedScoredTrip(
        db,
        id: 'r5',
        startedAt: t0 + 5 * day,
        score: 85,
        weather: 'rain',
      );
      expect(await run(), contains('rain_or_shine'));
    });

    test('three_states and ten_states count distinct pack regions', () async {
      for (var i = 0; i < 3; i++) {
        await seedScoredTrip(
          db,
          id: 's$i',
          startedAt: t0 + i * day,
          packRegion: 'us-tn',
        );
      }
      expect(await run(), isNot(contains('three_states')));
      await seedScoredTrip(
        db,
        id: 's3',
        startedAt: t0 + 3 * day,
        packRegion: 'us-ky',
      );
      await seedScoredTrip(
        db,
        id: 's4',
        startedAt: t0 + 4 * day,
        packRegion: 'us-ga',
      );
      expect(await run(), contains('three_states'));
      final regions = ['al', 'ar', 'ca', 'co', 'dc', 'de', 'fl'];
      for (var i = 0; i < regions.length; i++) {
        await seedScoredTrip(
          db,
          id: 'x$i',
          startedAt: t0 + (10 + i) * day,
          packRegion: 'us-${regions[i]}',
        );
      }
      expect(await run(), contains('ten_states'));
    });

    test('high_altitude looks at samples once per new trip', () async {
      await seedScoredTrip(db, id: 'a1', startedAt: t0, altitudeM: 1200);
      expect(await run(), isNot(contains('high_altitude')));
      await seedScoredTrip(db, id: 'a2', startedAt: t0 + day, altitudeM: 2600);
      expect(await run(), contains('high_altitude'));
      expect(
        await db.getSetting('badges:altitude_checked_until'),
        '${t0 + day}',
      );
    });

    test('award() is idempotent and reports through onAwarded', () async {
      expect(await engine.award('first_friend'), isTrue);
      expect(await engine.award('first_friend'), isFalse);
      expect(awarded, ['first_friend']);
    });
  }, skip: skip);

  group('Streaks', () {
    test('bonus XP and label', () {
      expect(const Streaks(clean: 4, phoneFree: 0).bonusXp, 0);
      expect(const Streaks(clean: 5, phoneFree: 0).bonusXp, 5);
      expect(const Streaks(clean: 20, phoneFree: 3).bonusXp, 10);
      expect(Streaks.none.label, isNull);
      expect(
        const Streaks(clean: 6, phoneFree: 2).label,
        '6 clean · 2 phone-free · +5 XP',
      );
    });
  });

  group('BadgesSync', () {
    test('queues an upload with a stable post id when signed in', () async {
      final outbox = OutboxWorker(db, now: () => t0);
      final sync = BadgesSync(
        db: db,
        outbox: outbox,
        client: null,
        userId: () => 'user-1',
        defs: () async => fallbackBadgeDefs,
        now: () => t0,
      );
      addTearDown(sync.dispose);
      await sync.engine.award('perfect_100');
      final row = (await db.dueOutbox(t0)).single;
      expect(row.kind, 'user_badge');
      expect(row.id, 'user_badge:user-1:perfect_100');
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      expect(payload['name'], 'Flawless');
      expect(payload['user_id'], 'user-1');
      expect(payload['post_id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      // Deterministic: the same user and badge give the same post id.
      await db.deleteOutbox(row.id);
      await sync.syncPending();
      final again = (await db.dueOutbox(t0)).single;
      expect(jsonDecode(again.payload)['post_id'], payload['post_id']);

      // Without a client the handler asks to retry later: nothing is lost.
      expect(await outbox.drain(), 0);
      expect((await db.dueOutbox(t0)).single.attempts, 0);
    });

    test('an award while signed out is queued once a user appears', () async {
      String? uid;
      final outbox = OutboxWorker(db, now: () => t0);
      final sync = BadgesSync(
        db: db,
        outbox: outbox,
        client: null,
        userId: () => uid,
        defs: () async => fallbackBadgeDefs,
        now: () => t0,
      );
      addTearDown(sync.dispose);
      await sync.engine.award('first_trip');
      expect(await db.dueOutbox(t0), isEmpty);
      uid = 'user-2';
      await sync.syncPending();
      expect(
        (await db.dueOutbox(t0)).single.id,
        'user_badge:user-2:first_trip',
      );
    });
  }, skip: skip);
}
