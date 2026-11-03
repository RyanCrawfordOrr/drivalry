import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

League league(String id, {String kind = 'friend'}) => League(
  id: id,
  name: kind == 'global' ? 'Global Bronze 1' : 'Crew',
  kind: kind,
  inviteCode: kind == 'global' ? '' : 'abcd1234',
  createdBy: kind == 'global' ? '' : 'u1',
  maxMembers: 30,
  createdAt: DateTime(2026, 11, 1),
  myTier: LeagueTier.bronze,
  myHiding: false,
  memberCount: 12,
);

/// Minimal scriptable cloud: only what the global-league paths touch.
class FakeApi implements LeaguesApi {
  final calls = <String>[];
  List<League> leagues = [];

  @override
  Future<List<League>> myLeagues(String userId) async {
    calls.add('myLeagues');
    return leagues;
  }

  @override
  Future<String> joinGlobalLeague() async {
    calls.add('joinGlobalLeague');
    leagues = [...leagues, league('G1', kind: 'global')];
    return 'G1';
  }

  @override
  Future<void> leaveGlobalLeague() async {
    calls.add('leaveGlobalLeague');
    leagues = [
      for (final l in leagues)
        if (!l.isGlobal) l,
    ];
  }

  @override
  Future<void> leave(String leagueId, String userId) async {
    calls.add('leave:$leagueId');
    leagues = [
      for (final l in leagues)
        if (l.id != leagueId) l,
    ];
  }

  @override
  Future<List<LeagueMember>> members(String leagueId) async => const [];

  @override
  Future<List<WeekSummary>> weekSummaries(
    List<String> userIds,
    DateTime fromLocal,
    DateTime toLocal,
  ) async => const [];

  @override
  Future<List<(String, List<dynamic>)>> weeks(String leagueId) async =>
      const [];

  List<(String, String, List<dynamic>)> recentRows = [];

  @override
  Future<List<(String, String, List<dynamic>)>> recentWeeks(
    String sinceDate,
  ) async {
    calls.add('recentWeeks:$sinceDate');
    return recentRows;
  }

  @override
  Future<String> joinByCode(String code) async => 'L1';

  @override
  Future<void> finalizeWeek(String leagueId, String weekStartDate) async {}

  @override
  Future<void> createLeague({
    required String id,
    required String name,
    required String userId,
  }) async {}

  @override
  Future<void> setHiding({
    required String leagueId,
    required String userId,
    required bool hiding,
  }) async {}
}

void main() {
  test('League.isGlobal follows kind; the default kind is friend', () {
    expect(league('G', kind: 'global').isGlobal, isTrue);
    expect(league('L').isGlobal, isFalse);
    expect(League.fromJson({'id': 'x', 'name': 'n'}).isGlobal, isFalse);
    expect(
      League.fromJson({'id': 'x', 'name': 'n', 'kind': 'global'}).isGlobal,
      isTrue,
    );
  });

  group('global leagues', () {
    final skip = skipWithoutSqlite();
    late FakeApi api;
    String? uid = 'me';

    setUp(() {
      api = FakeApi();
      uid = 'me';
    });

    LeaguesRepo build(AppDatabase db, {LeaguesApi? apiOverride}) {
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      return LeaguesRepo(
        db: db,
        api: apiOverride ?? api,
        outbox: worker,
        userId: () => uid,
        now: () => 1,
      );
    }

    test('joinGlobalLeague calls the RPC and refreshes the list', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      final id = await repo.joinGlobalLeague();
      expect(id, 'G1');
      expect(api.calls, ['joinGlobalLeague', 'myLeagues']);
      final cached = await repo.cachedMyLeagues();
      expect(cached.single.isGlobal, isTrue);
    }, skip: skip);

    test('joining needs a user and the cloud', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      uid = null;
      expect(
        () => build(db).joinGlobalLeague(),
        throwsA(
          isA<LeagueJoinException>().having(
            (e) => e.error,
            'error',
            LeagueJoinError.notSignedIn,
          ),
        ),
      );
      uid = 'me';
      final offline = LeaguesRepo(
        db: db,
        api: null,
        outbox: OutboxWorker(db, now: () => 1),
        userId: () => uid,
      );
      expect(
        () => offline.joinGlobalLeague(),
        throwsA(
          isA<LeagueJoinException>().having(
            (e) => e.error,
            'error',
            LeagueJoinError.unavailable,
          ),
        ),
      );
    }, skip: skip);

    test('leaving a global league goes through leave_global_league', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.leagues = [league('L1'), league('G1', kind: 'global')];
      final repo = build(db);
      await repo.refreshMyLeagues();
      await repo.leave('G1');
      expect(api.calls, contains('leaveGlobalLeague'));
      expect(api.calls, isNot(contains('leave:G1')));
      await repo.leave('L1');
      expect(api.calls, contains('leave:L1'));
      expect(await repo.cachedMyLeagues(), isEmpty);
    }, skip: skip);

    test('myGlobalLeagueProvider picks the global membership', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.leagues = [league('L1'), league('G1', kind: 'global')];
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          leaguesApiProvider.overrideWithValue(api),
          currentUserIdProvider.overrideWithValue('me'),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(myLeaguesProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(leaguesRepoProvider).refreshMyLeagues();
      await container.read(myLeaguesProvider.future);
      // Let the cache stream deliver the refreshed snapshot.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(myGlobalLeagueProvider)?.id, 'G1');
    }, skip: skip);

    test('a closed global league is dropped from my leagues', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.leagues = [
        league('L1'),
        League.fromJson({
          ...league('G0', kind: 'global').toJson(),
          'closed_at': '2026-11-02T06:10:00Z',
        }),
        league('G1', kind: 'global'),
      ];
      final repo = build(db);
      final mine = await repo.refreshMyLeagues();
      expect(mine.map((l) => l.id), ['L1', 'G1']);
      expect((await repo.cachedMyLeagues()).map((l) => l.id), ['L1', 'G1']);
    }, skip: skip);

    test(
      'week badges come from league_weeks rows, league listed or not',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.leagues = [league('L1')];
        api.recentRows = [
          (
            'G0', // closed global league: no longer in myLeagues
            '2026-10-26',
            [
              {
                'user_id': 'me',
                'rank': 2,
                'tier_before': 'bronze',
                'tier_after': 'silver',
              },
              {
                'user_id': 'u2',
                'rank': 1,
                'tier_before': 'bronze',
                'tier_after': 'silver',
              },
            ],
          ),
          (
            'L1',
            '2026-10-19',
            [
              {
                'user_id': 'me',
                'rank': 9,
                'tier_before': 'bronze',
                'tier_after': 'bronze',
              },
            ],
          ),
          (
            'L1',
            '2026-10-12',
            [
              {
                'user_id': 'u2',
                'rank': 1,
                'tier_before': 'bronze',
                'tier_after': 'silver',
              },
            ],
          ),
        ];
        final repo = build(db);
        final awarded = <String>[];
        Future<bool> award(String id) async {
          awarded.add(id);
          return true;
        }

        final now = DateTime(2026, 11, 3);
        expect(await repo.awardRecentWeekBadges(award, now: now), 2);
        expect(awarded, ['league_week', 'promoted', 'league_week']);
        expect(api.calls.single, 'recentWeeks:2026-09-08');
        expect(
          await db.getSetting(LeaguesRepo.weekBadgesKey('me')),
          '2026-10-26',
        );

        // The next pass asks only for weeks after the newest one seen.
        api.calls.clear();
        api.recentRows = [];
        expect(await repo.awardRecentWeekBadges(award, now: now), 0);
        expect(api.calls.single, 'recentWeeks:2026-10-27');
      },
      skip: skip,
    );

    test('week badges need a user and the cloud', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      uid = null;
      expect(await build(db).awardRecentWeekBadges((_) async => true), 0);
    }, skip: skip);
  });
}
