import 'dart:convert';

import 'package:drivalry/data/badges/badge_engine.dart';
import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/data/repos/seasons_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scored_trips.dart';
import 'support/sqlite_support.dart';

class FakeSeasonsApi implements SeasonsApi {
  final calls = <String>[];
  List<Season> list = [];
  List<SeasonResult> results = [];
  final upserts = <Map<String, dynamic>>[];
  Object? failWith;

  void _call(String c) {
    calls.add(c);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<Season>> seasons() async {
    _call('seasons');
    return list;
  }

  @override
  Future<List<SeasonResult>> myResults(String userId) async {
    _call('results:$userId');
    return results;
  }

  @override
  Future<void> upsertResult(Map<String, dynamic> row) async {
    _call('upsert:${row['season_id']}');
    upserts.add(row);
  }
}

void main() {
  group('seasons calendar', () {
    test('built-in seasons are five contiguous quarters', () {
      expect(builtInSeasons.length, 5);
      expect(builtInSeasons.first.id, '2026-q4');
      expect(builtInSeasons.last.id, '2027-q4');
      for (var i = 1; i < builtInSeasons.length; i++) {
        expect(
          builtInSeasons[i].startsOn,
          builtInSeasons[i - 1].endExclusive,
          reason:
              'no gap between ${builtInSeasons[i - 1].id} and ${builtInSeasons[i].id}',
        );
        expect(builtInSeasons[i].number, i + 1);
      }
    });

    test('seasonFor finds the quarter, or nothing outside the calendar', () {
      expect(seasonFor(builtInSeasons, DateTime(2026, 11, 3))?.number, 1);
      expect(
        seasonFor(builtInSeasons, DateTime(2026, 12, 31, 23, 59))?.number,
        1,
      );
      expect(seasonFor(builtInSeasons, DateTime(2027, 1, 1))?.number, 2);
      expect(seasonFor(builtInSeasons, DateTime(2026, 9, 30)), isNull);
      expect(seasonFor(builtInSeasons, DateTime(2028, 1, 1)), isNull);
    });

    test('days left counts today; progress runs 0..1', () {
      final s = builtInSeasons.first;
      expect(s.daysLeft(DateTime(2026, 11, 3, 15)), 59);
      expect(s.daysLeft(DateTime(2026, 12, 31, 9)), 1);
      expect(s.daysLeft(DateTime(2027, 1, 1)), 0);
      expect(s.isOver(DateTime(2027, 1, 1)), isTrue);
      expect(s.isOver(DateTime(2026, 12, 31, 23, 59)), isFalse);
      expect(s.progress(DateTime(2026, 10, 1)), 0);
      expect(s.progress(DateTime(2027, 2, 1)), 1);
      final mid = s.progress(DateTime(2026, 11, 15));
      expect(mid, greaterThan(0.45));
      expect(mid, lessThan(0.55));
    });

    test('season json round trip', () {
      final s = Season.fromJson(
        jsonDecode(jsonEncode(builtInSeasons[1].toJson()))
            as Map<String, dynamic>,
      );
      expect(s.id, '2027-q1');
      expect(s.startsOn, DateTime(2027, 1, 1));
      expect(s.endsOn, DateTime(2027, 3, 31));
    });

    test('wrapped headline never mentions speed', () {
      final s = builtInSeasons.first;
      expect(wrappedHeadline(s, SeasonStats.none), contains('parked'));
      final good = SeasonStats(
        trips: 40,
        xp: 2000,
        scoreAvg: 93,
        cleanTrips: 38,
        phoneFreeTrips: 30,
        bestScore: 100,
      );
      expect(wrappedHeadline(s, good), contains('Chauffeur material'));
      final handsOff = SeasonStats(
        trips: 10,
        xp: 500,
        scoreAvg: 80,
        cleanTrips: 4,
        phoneFreeTrips: 10,
        bestScore: 95,
      );
      expect(wrappedHeadline(s, handsOff), contains('phone stayed down'));
      final plain = SeasonStats(
        trips: 10,
        xp: 500,
        scoreAvg: 80,
        cleanTrips: 4,
        phoneFreeTrips: 9,
        bestScore: 95,
      );
      expect(
        wrappedHeadline(s, plain),
        '${s.name}: 10 trips, 4 of them clean.',
      );
      for (final h in [
        wrappedHeadline(s, good),
        wrappedHeadline(s, handsOff),
        wrappedHeadline(s, plain),
      ]) {
        expect(h.toLowerCase(), isNot(contains('speed')));
        expect(h.toLowerCase(), isNot(contains('km')));
      }
    });

    test('season result json round trip', () {
      final r = SeasonResult(
        seasonId: '2026-q4',
        userId: 'me',
        stats: const SeasonStats(
          trips: 3,
          xp: 150,
          scoreAvg: 88.3,
          cleanTrips: 2,
          phoneFreeTrips: 3,
          bestScore: 95,
        ),
        bestTier: LeagueTier.gold,
        duelsWon: 2,
        duelsLost: 1,
      );
      final back = SeasonResult.fromJson(
        jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
      );
      expect(back.stats.scoreAvg, 88.3);
      expect(back.bestTier, LeagueTier.gold);
      expect(back.duelsWon, 2);
      expect(back.duelsLost, 1);
    });
  });

  group('SeasonsRepo', () {
    final skip = skipWithoutSqlite();
    late FakeSeasonsApi api;
    final awarded = <String>[];
    String? uid = 'me';
    var now = DateTime(2027, 1, 2, 9).millisecondsSinceEpoch;

    setUp(() {
      api = FakeSeasonsApi();
      awarded.clear();
      uid = 'me';
      now = DateTime(2027, 1, 2, 9).millisecondsSinceEpoch;
    });

    SeasonsRepo build(dynamic db, {LeagueTier? tier, (int, int)? duels}) {
      final worker = OutboxWorker(db, now: () => now);
      addTearDown(worker.dispose);
      return SeasonsRepo(
        db: db,
        api: api,
        outbox: worker,
        userId: () => uid,
        awardBadge: (id) async => awarded.add(id),
        bestTier: () async => tier,
        duelRecord: (from, to) async => duels ?? (0, 0),
        now: () => now,
      );
    }

    Future<void> seedSeasonOne(dynamic db) async {
      await seedScoredTrip(
        db,
        id: 't1',
        startedAt: DateTime(2026, 11, 3, 8).millisecondsSinceEpoch,
        score: 92,
        xp: 70,
      );
      await seedScoredTrip(
        db,
        id: 't2',
        startedAt: DateTime(2026, 12, 20, 18).millisecondsSinceEpoch,
        score: 80,
        xp: 40,
        phoneHandling: true,
      );
      // Season 2: must not count toward season 1.
      await seedScoredTrip(
        db,
        id: 't3',
        startedAt: DateTime(2027, 1, 1, 12).millisecondsSinceEpoch,
        score: 100,
        xp: 90,
      );
    }

    test('computeSeasonStats counts only trips inside the season', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      await seedSeasonOne(db);
      final trips = ScoredTripParser().parse(await db.scoredTripsWithScores());
      final s = computeSeasonStats(builtInSeasons.first, trips);
      expect(s.trips, 2);
      expect(s.xp, 110);
      expect(s.scoreAvg, 86.0);
      expect(s.cleanTrips, 2, reason: '80 is the clean-trip score');
      expect(s.phoneFreeTrips, 1);
      expect(s.bestScore, 92);
      final s2 = computeSeasonStats(builtInSeasons[1], trips);
      expect(s2.trips, 1);
      expect(s2.bestScore, 100);
    }, skip: skip);

    test(
      'an ended season uploads once, with the badge and the extras',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        await seedSeasonOne(db);
        api.failWith = StateError('offline'); // queue only; inspect the row
        final repo = build(db, tier: LeagueTier.gold, duels: (2, 1));
        final queued = await repo.uploadEndedSeasons(seasons: builtInSeasons);
        expect(queued, ['2026-q4']);
        expect(awarded, ['season_1']);
        final row = (await db.dueOutbox(now + 3_600_000)).single;
        expect(row.id, 'season_result:2026-q4:me');
        expect(row.kind, SeasonsRepo.kindResult);
        final p = jsonDecode(row.payload) as Map<String, dynamic>;
        expect(p['season_id'], '2026-q4');
        expect(p['user_id'], 'me');
        expect(p['trips'], 2);
        expect(p['xp'], 110);
        expect(p['score_avg'], 86.0);
        expect(p['clean_trips'], 2);
        expect(p['phone_free_trips'], 1);
        expect(p['best_score'], 92);
        expect(p['best_tier'], 'gold');
        expect(p['duels_won'], 2);
        expect(p['duels_lost'], 1);
        expect((p['wrapped'] as Map)['headline'], isNotEmpty);

        // Second call: nothing new.
        expect(await repo.uploadEndedSeasons(seasons: builtInSeasons), isEmpty);

        // Back online: the handler upserts the row.
        api.failWith = null;
        expect(await repo.outbox.drain(), 1);
        expect(api.upserts.single['season_id'], '2026-q4');
        expect(api.upserts.single['best_tier'], 'gold');
      },
      skip: skip,
    );

    test(
      'a running season is not uploaded, nor is a signed-out phone',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        await seedSeasonOne(db);
        now = DateTime(2026, 11, 3).millisecondsSinceEpoch;
        final repo = build(db);
        expect(await repo.uploadEndedSeasons(seasons: builtInSeasons), isEmpty);
        expect(awarded, isEmpty);

        now = DateTime(2027, 1, 2).millisecondsSinceEpoch;
        uid = null;
        expect(await repo.uploadEndedSeasons(seasons: builtInSeasons), isEmpty);
        expect(await db.dueOutbox(now), isEmpty);
      },
      skip: skip,
    );

    test(
      'no scored trips: nothing uploads and the season is remembered as empty',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = build(db);
        expect(await repo.uploadEndedSeasons(seasons: builtInSeasons), isEmpty);
        expect(awarded, isEmpty);
        expect(await db.dueOutbox(now + 1), isEmpty);
        expect(
          await db.getSetting(SeasonsRepo.uploadedKey('2026-q4', 'me')),
          'empty',
        );
        // Remembered: the next call does not re-parse the trips either.
        expect(await repo.uploadEndedSeasons(seasons: builtInSeasons), isEmpty);
      },
      skip: skip,
    );

    test('seasons(): cloud list, then cache, then built-in', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      expect(
        (await repo.seasons()).length,
        5,
        reason: 'empty cloud → built-in',
      );
      api.list = [builtInSeasons.first];
      expect((await repo.seasons()).length, 1);
      api.failWith = StateError('offline');
      expect((await repo.seasons()).length, 1, reason: 'cached cloud list');
    }, skip: skip);

    test("another account's result stays queued", () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      await repo.outbox.enqueue(SeasonsRepo.kindResult, {
        'season_id': '2026-q4',
        'user_id': 'someone_else',
        'trips': 1,
      });
      expect(await repo.outbox.drain(), 0);
      expect((await db.dueOutbox(now)).single.attempts, 0);
      expect(api.upserts, isEmpty);
    }, skip: skip);
  });
}
