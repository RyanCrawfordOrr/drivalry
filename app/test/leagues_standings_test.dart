import 'dart:convert';

import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/sqlite_support.dart';

LeagueMember member(
  String id, {
  LeagueTier tier = LeagueTier.bronze,
  double? rating,
  bool hiding = false,
}) => LeagueMember(
  userId: id,
  handle: id,
  displayName: id.toUpperCase(),
  tier: tier,
  hiding: hiding,
  rating: rating,
);

League league(String id, {String name = 'Crew', bool hiding = false}) => League(
  id: id,
  name: name,
  kind: 'friend',
  inviteCode: 'abcd1234',
  createdBy: 'u1',
  maxMembers: 30,
  createdAt: DateTime(2026, 11, 1),
  myTier: LeagueTier.learner,
  myHiding: hiding,
  memberCount: 1,
);

/// Scriptable cloud for the repo tests.
class FakeLeaguesApi implements LeaguesApi {
  final calls = <String>[];
  List<League> leagues = [];
  List<LeagueMember> memberList = [];
  List<WeekSummary> summaries = [];
  List<(String, List<dynamic>)> weekRows = [];
  Object? failWith;

  void _call(String call) {
    calls.add(call);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<League>> myLeagues(String userId) async {
    _call('myLeagues');
    return leagues;
  }

  @override
  Future<List<LeagueMember>> members(String leagueId) async {
    _call('members:$leagueId');
    return memberList;
  }

  @override
  Future<List<WeekSummary>> weekSummaries(
    List<String> userIds,
    DateTime fromLocal,
    DateTime toLocal,
  ) async {
    _call('weekSummaries:${userIds.length}');
    return summaries;
  }

  @override
  Future<List<(String, List<dynamic>)>> weeks(String leagueId) async {
    _call('weeks:$leagueId');
    return weekRows;
  }

  @override
  Future<String> joinByCode(String code) async {
    _call('join:$code');
    if (code == 'bad') {
      throw const LeagueJoinException(LeagueJoinError.invalidCode);
    }
    return 'league-from-$code';
  }

  @override
  Future<void> leave(String leagueId, String userId) async =>
      _call('leave:$leagueId');

  @override
  Future<void> finalizeWeek(String leagueId, String weekStartDate) async =>
      _call('finalize:$leagueId:$weekStartDate');

  @override
  Future<void> createLeague({
    required String id,
    required String name,
    required String userId,
  }) async {
    _call('create:$name');
    leagues = [...leagues, league(id, name: name)];
  }

  @override
  Future<void> setHiding({
    required String leagueId,
    required String userId,
    required bool hiding,
  }) async => _call('hiding:$leagueId:$hiding');
}

void main() {
  group('computeStandings', () {
    final members = [
      member('f', rating: 80),
      member('a', rating: 90),
      member('b', rating: 70),
      member('c'),
      member('d', rating: 95, tier: LeagueTier.gold),
      member('e', rating: 60),
      member('g', tier: LeagueTier.learner),
    ];
    final summaries = const [
      WeekSummary(userId: 'a', xp: 100),
      WeekSummary(userId: 'a', xp: 50),
      WeekSummary(userId: 'b', xp: 150),
      WeekSummary(userId: 'c', xp: 150),
      WeekSummary(userId: 'd', xp: 150),
      WeekSummary(userId: 'e', xp: 20),
      WeekSummary(userId: 'f', xp: 20),
    ];

    test('orders by XP, then rating with nulls last, then id', () {
      final rows = computeStandings(members, summaries);
      expect(rows.map((r) => r.userId).toList(), [
        'd',
        'a',
        'b',
        'c',
        'f',
        'e',
        'g',
      ]);
      expect(rows.map((r) => r.rank).toList(), [1, 2, 3, 4, 5, 6, 7]);
      expect(rows[1].xp, 150);
      expect(rows[1].trips, 2);
      expect(rows.last.trips, 0);
    });

    test('projects promotion and demotion zones like the database', () {
      final rows = computeStandings(members, summaries);
      final byId = {for (final r in rows) r.userId: r};
      expect(byId['d']!.projectedTier, LeagueTier.platinum);
      expect(byId['a']!.promotes, isTrue);
      // Rank 5 is in the top five even though it is also in the bottom five.
      expect(byId['f']!.promotes, isTrue);
      expect(byId['e']!.demotes, isTrue);
      expect(byId['e']!.projectedTier, LeagueTier.learner);
      // No trips: demoted, but Learner has no floor below it.
      expect(byId['g']!.projectedTier, LeagueTier.learner);
      expect(byId['g']!.demotes, isFalse);
    });

    test('with five or fewer members nobody moves', () {
      final rows = computeStandings(members.take(4).toList(), summaries);
      expect(rows.every((r) => !r.promotes && !r.demotes), isTrue);
    });

    test('reads a finalised week and sorts by rank', () {
      final rows = standingsFromFinalized(
        [
          {
            'user_id': 'b',
            'xp': 10,
            'trips': 1,
            'rank': 2,
            'tier_before': 'bronze',
            'tier_after': 'learner',
          },
          {
            'user_id': 'a',
            'xp': 90,
            'trips': 3,
            'rating': 88.5,
            'rank': 1,
            'tier_before': 'bronze',
            'tier_after': 'silver',
          },
        ],
        {'a': member('a'), 'b': member('b')},
      );
      expect(rows.map((r) => r.userId).toList(), ['a', 'b']);
      expect(rows.first.promotes, isTrue);
      expect(rows.first.rating, 88.5);
      expect(rows.last.demotes, isTrue);
      expect(rows.last.handle, 'b');
    });
  });

  group('mapJoinError', () {
    test('maps the RPC error codes', () {
      expect(
        mapJoinError(const PostgrestException(message: 'x', code: 'P0001')),
        LeagueJoinError.invalidCode,
      );
      expect(
        mapJoinError(const PostgrestException(message: 'x', code: 'P0002')),
        LeagueJoinError.full,
      );
      expect(
        mapJoinError(const PostgrestException(message: 'invalid invite code')),
        LeagueJoinError.invalidCode,
      );
      expect(
        mapJoinError(
          const PostgrestException(message: 'timeout', code: '57014'),
        ),
        LeagueJoinError.unavailable,
      );
      expect(mapJoinError(StateError('offline')), LeagueJoinError.unavailable);
    });
  });

  group('LeaguesRepo', () {
    late FakeLeaguesApi api;
    String? uid = 'u1';
    var now = DateTime(2026, 11, 4, 12).millisecondsSinceEpoch;

    LeaguesRepo build(dbInstance) {
      final outbox = OutboxWorker(dbInstance, now: () => now);
      return LeaguesRepo(
        db: dbInstance,
        api: api,
        outbox: outbox,
        userId: () => uid,
        now: () => now,
      );
    }

    setUp(() {
      api = FakeLeaguesApi();
      uid = 'u1';
    });

    test(
      'createLeague goes through the outbox and refreshes the cache',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = build(db);
        final created = await repo.createLeague('  Carpool Crew ');
        expect(created.name, 'Carpool Crew');
        expect(created.inviteCode, 'abcd1234');
        expect(api.calls, containsAll(['create:Carpool Crew', 'myLeagues']));
        expect((await repo.cachedMyLeagues()).single.name, 'Carpool Crew');
        expect(await db.dueOutbox(now), isEmpty, reason: 'delivered');
      },
    );

    test(
      'createLeague offline keeps the row queued and returns a stub',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.failWith = StateError('no network');
        final repo = build(db);
        final created = await repo.createLeague('Later');
        expect(created.name, 'Later');
        expect(created.inviteCode, '');
        final queued = (await db.dueOutbox(
          now + const Duration(hours: 7).inMilliseconds,
        )).single;
        expect(queued.kind, LeaguesRepo.kindCreate);
        expect(queued.attempts, 1);
      },
    );

    test('createLeague rejects bad names and signed-out users', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      expect(() => repo.createLeague('   '), throwsArgumentError);
      uid = null;
      expect(
        () => repo.createLeague('Crew'),
        throwsA(
          isA<LeagueJoinException>().having(
            (e) => e.error,
            'error',
            LeagueJoinError.notSignedIn,
          ),
        ),
      );
    });

    test(
      'setHiding flips the cache at once and queues the cloud write',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.leagues = [league('L1')];
        final repo = build(db);
        await repo.refreshMyLeagues();
        await repo.setHiding('L1', true);
        expect((await repo.cachedMyLeagues()).single.myHiding, isTrue);
        final row = (await db.dueOutbox(now)).single;
        expect(row.id, 'league_hiding:L1:u1');
        expect(jsonDecode(row.payload)['hiding'], isTrue);
        await repo.outbox.drain();
        expect(api.calls, contains('hiding:L1:true'));
      },
    );

    test(
      'currentWeek computes standings and falls back to the cache',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.memberList = [member('u1', rating: 80), member('u2', rating: 90)];
        api.summaries = const [
          WeekSummary(userId: 'u2', xp: 40),
          WeekSummary(userId: 'u1', xp: 70),
        ];
        final repo = build(db);
        final week = await repo.currentWeek(
          'L1',
          now: DateTime(2026, 11, 4, 12),
        );
        expect(week.weekStart, DateTime(2026, 11, 2));
        expect(week.finalized, isFalse);
        expect(week.rows.first.userId, 'u1');
        expect(week.rows.first.xp, 70);
        expect(week.rowFor('u2')!.rank, 2);

        api.failWith = StateError('offline');
        final again = await repo.currentWeek(
          'L1',
          now: DateTime(2026, 11, 4, 13),
        );
        expect(again.rows.map((r) => r.userId).toList(), ['u1', 'u2']);
        expect(again.rows.first.xp, 70, reason: 'served from cache');
      },
    );

    test(
      'pastWeeks finalises the previous week once when it is missing',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.memberList = [member('u1'), member('u2')];
        api.weekRows = [
          (
            '2026-10-19',
            [
              {
                'user_id': 'u1',
                'xp': 5,
                'trips': 1,
                'rank': 1,
                'tier_before': 'learner',
                'tier_after': 'learner',
              },
            ],
          ),
        ];
        final repo = build(db);
        final probe = DateTime(2026, 11, 4, 12); // previous week starts 10-26
        final weeks = await repo.pastWeeks('L1', now: probe);
        expect(weeks.single.weekStart, DateTime(2026, 10, 19));
        expect(weeks.single.finalized, isTrue);
        expect(weeks.single.rows.single.handle, 'u1');
        expect(api.calls.where((c) => c == 'finalize:L1:2026-10-26').length, 1);

        await repo.pastWeeks('L1', now: probe);
        expect(
          api.calls.where((c) => c == 'finalize:L1:2026-10-26').length,
          1,
          reason: 'remembered in settings',
        );
      },
    );

    test('pastWeeks does not finalise when the week already exists', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.weekRows = [('2026-10-26', const [])];
      final repo = build(db);
      await repo.pastWeeks('L1', now: DateTime(2026, 11, 4, 12));
      expect(api.calls.any((c) => c.startsWith('finalize:')), isFalse);
    });

    test('joinByCode maps errors and refreshes on success', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      expect(
        () => repo.joinByCode('bad'),
        throwsA(
          isA<LeagueJoinException>().having(
            (e) => e.message,
            'message',
            contains('not valid'),
          ),
        ),
      );
      expect(await repo.joinByCode('good'), 'league-from-good');
      expect(api.calls, contains('myLeagues'));
    });

    test('leave clears that league\'s caches', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      await db.cachePut('league:L1:members', '[]', now);
      await db.cachePut('league:L2:members', '[]', now);
      await repo.leave('L1');
      expect(await db.cacheGet('league:L1:members'), isNull);
      expect(await db.cacheGet('league:L2:members'), '[]');
      expect(api.calls, contains('leave:L1'));
    });
  }, skip: skipWithoutSqlite());
}
