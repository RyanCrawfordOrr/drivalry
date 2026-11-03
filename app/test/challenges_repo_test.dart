import 'dart:convert';

import 'package:drivalry/data/repos/challenges_repo.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show Xp;
import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

ChallengeTrip t(
  String u, {
  int score = 90,
  bool reckless = false,
  bool phone = false,
}) => ChallengeTrip(
  userId: u,
  score: score,
  reckless: reckless,
  phoneHandling: phone,
);

GroupChallenge challenge({
  String id = 'c1',
  ChallengeGoal goal = ChallengeGoal.cleanTrips,
  int target = 5,
  String status = 'active',
  DateTime? startsAt,
  DateTime? endsAt,
  double? value,
  DateTime? finalizedAt,
}) => GroupChallenge(
  id: id,
  leagueId: 'L1',
  createdBy: 'me',
  goal: goal,
  target: target,
  startsAt: startsAt ?? DateTime(2026, 11, 2),
  endsAt: endsAt ?? DateTime(2026, 11, 9),
  status: status,
  value: value,
  finalizedAt: finalizedAt,
);

LeagueMember member(String id) => LeagueMember(
  userId: id,
  handle: id,
  displayName: id,
  tier: LeagueTier.bronze,
  hiding: false,
);

class FakeChallengesApi implements ChallengesApi {
  final calls = <String>[];
  List<GroupChallenge> list = [];
  List<ChallengeTrip> tripRows = [];
  String finalizeStatus = 'succeeded';
  Object? failWith;

  void _call(String c) {
    calls.add(c);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<GroupChallenge>> forLeague(String leagueId) async {
    _call('forLeague:$leagueId');
    return list;
  }

  @override
  Future<void> create(Map<String, dynamic> row) async {
    _call('create:${row['id']}:${row['goal']}:${row['target']}');
    list = [
      GroupChallenge.fromJson({...row, 'status': 'active'}),
      ...list,
    ];
  }

  @override
  Future<Map<String, dynamic>> finalize(String challengeId) async {
    _call('finalize:$challengeId');
    list = [
      for (final c in list)
        if (c.id == challengeId)
          GroupChallenge.fromJson({
            ...c.toJson(),
            'status': finalizeStatus,
            'value': 7,
            'finalized_at': '2026-11-09T06:25:00Z',
          })
        else
          c,
    ];
    return {'status': finalizeStatus, 'value': 7};
  }

  @override
  Future<void> cancel(String challengeId) async => _call('cancel:$challengeId');

  @override
  Future<List<ChallengeTrip>> trips(
    List<String> userIds,
    DateTime from,
    DateTime to,
  ) async {
    _call('trips:${userIds.join(',')}');
    return tripRows;
  }
}

void main() {
  group('computeChallengeProgress', () {
    final members = ['a', 'b', 'c'];

    test('the clean line is the scoring package\'s clean-trip score', () {
      expect(challengeCleanScore, Xp.cleanTripScore);
    });

    test('clean trips: 80+ and not reckless, non-members ignored', () {
      final p = computeChallengeProgress(challenge(target: 5), members, [
        t('a', score: 90),
        t('a', score: 79),
        t('b', score: 80),
        t('b', score: 95, reckless: true),
        t('zz', score: 100),
      ]);
      expect(p.value, 2);
      expect(p.needed, 5);
      expect(p.met, isFalse);
      expect(p.fraction, 0.4);
      expect(p.perMember.map((m) => m.userId), ['a', 'b', 'c']);
      expect(p.perMember.first.trips, 2);
      expect(p.perMember.first.clean, 1);
      expect(p.perMember.last.trips, 0);
      expect(p.perMember.last.scoreAvg, isNull);
    });

    test('phone-free counts trips with no handling', () {
      final p = computeChallengeProgress(
        challenge(goal: ChallengeGoal.phoneFree, target: 2),
        members,
        [t('a'), t('a', phone: true), t('c')],
      );
      expect(p.value, 2);
      expect(p.met, isTrue);
      expect(p.fraction, 1);
    });

    test('average score is over every member trip', () {
      final p = computeChallengeProgress(
        challenge(goal: ChallengeGoal.scoreAvg, target: 85),
        members,
        [t('a', score: 90), t('b', score: 80), t('b', score: 86)],
      );
      expect(p.value, 85.33);
      expect(p.met, isTrue);
      final empty = computeChallengeProgress(
        challenge(goal: ChallengeGoal.scoreAvg, target: 85),
        members,
        const [],
      );
      expect(empty.value, 0);
      expect(empty.met, isFalse);
    });

    test('everyone drives: met only when every member hits the target', () {
      final c = challenge(goal: ChallengeGoal.everyoneDrives, target: 2);
      final partial = computeChallengeProgress(c, members, [
        t('a'),
        t('a'),
        t('b'),
        t('b'),
        t('c'),
      ]);
      expect(partial.value, 2);
      expect(partial.needed, 3);
      expect(partial.met, isFalse);
      final all = computeChallengeProgress(c, members, [
        t('a'),
        t('a'),
        t('b'),
        t('b'),
        t('c'),
        t('c'),
      ]);
      expect(all.met, isTrue);
      expect(
        computeChallengeProgress(c, const [], const []).met,
        isFalse,
        reason: 'an empty league meets nothing',
      );
    });

    test('json round trip keeps the window and the result', () {
      final c = challenge(
        status: 'failed',
        value: 3,
        finalizedAt: DateTime(2026, 11, 9, 7),
      );
      final back = GroupChallenge.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
      );
      expect(back.startsAt, c.startsAt);
      expect(back.endsAt, c.endsAt);
      expect(back.failed, isTrue);
      expect(back.value, 3);
      expect(back.title, 'Clean trips · 5 trips');
      expect(back.goal.badgeId, 'challenge_clean_trips');
    });
  });

  group('ChallengesRepo', () {
    final skip = skipWithoutSqlite();
    late FakeChallengesApi api;
    var now = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch;
    final awarded = <String>[];
    String? uid = 'me';

    setUp(() {
      api = FakeChallengesApi();
      now = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch;
      awarded.clear();
      uid = 'me';
    });

    ChallengesRepo build(dynamic db) {
      final worker = OutboxWorker(db, now: () => now);
      addTearDown(worker.dispose);
      return ChallengesRepo(
        db: db,
        api: api,
        outbox: worker,
        userId: () => uid,
        awardBadge: (id) async => awarded.add(id),
        now: () => now,
      );
    }

    test('create caches the challenge and delivers challenge_create', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      final c = await repo.create(
        leagueId: 'L1',
        goal: ChallengeGoal.phoneFree,
        target: 20,
        days: 14,
      );
      expect(c.isActive, isTrue);
      expect(c.endsAt.difference(c.startsAt).inDays, 14);
      expect(api.calls, contains('create:${c.id}:phone_free:20'));
      expect((await repo.current('L1', refresh: false))?.id, c.id);
    }, skip: skip);

    test('the queued payload carries the window and the account', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      api.failWith = StateError('offline');
      final c = await repo.create(
        leagueId: 'L1',
        goal: ChallengeGoal.everyoneDrives,
        target: 3,
      );
      final row = (await db.dueOutbox(now + 3_600_000)).single;
      expect(row.id, 'challenge_create:${c.id}');
      expect(row.kind, ChallengesRepo.kindCreate);
      final p = jsonDecode(row.payload) as Map<String, dynamic>;
      expect(p['league_id'], 'L1');
      expect(p['user_id'], 'me');
      expect(p['goal'], 'everyone_drives');
      expect(p['target'], 3);
      expect(DateTime.parse(p['starts_at'] as String).toLocal(), c.startsAt);
      expect(DateTime.parse(p['ends_at'] as String).toLocal(), c.endsAt);
    }, skip: skip);

    test(
      'one running challenge per league, sane targets, 7 or 14 days',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = build(db);
        await repo.create(
          leagueId: 'L1',
          goal: ChallengeGoal.cleanTrips,
          target: 5,
        );
        expect(
          () => repo.create(
            leagueId: 'L1',
            goal: ChallengeGoal.cleanTrips,
            target: 5,
          ),
          throwsA(isA<ChallengeException>()),
        );
        expect(
          () => repo.create(
            leagueId: 'L2',
            goal: ChallengeGoal.scoreAvg,
            target: 101,
          ),
          throwsA(isA<ChallengeException>()),
        );
        expect(
          () => repo.create(
            leagueId: 'L2',
            goal: ChallengeGoal.cleanTrips,
            target: 0,
          ),
          throwsA(isA<ChallengeException>()),
        );
        expect(
          () => repo.create(
            leagueId: 'L2',
            goal: ChallengeGoal.cleanTrips,
            target: 5,
            days: 3,
          ),
          throwsA(isA<ChallengeException>()),
        );
      },
      skip: skip,
    );

    test(
      'challenges() settles a due one and awards the badge locally',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.list = [
          challenge(
            startsAt: DateTime(2026, 10, 20),
            endsAt: DateTime(2026, 10, 27),
          ),
        ];
        final repo = build(db);
        final list = await repo.challenges('L1');
        expect(api.calls, ['forLeague:L1', 'finalize:c1', 'forLeague:L1']);
        expect(list.single.succeeded, isTrue);
        expect(awarded, ['challenge_clean_trips']);
        expect(await repo.current('L1', refresh: false), isNull);
      },
      skip: skip,
    );

    test('a missed challenge awards nothing', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.finalizeStatus = 'failed';
      api.list = [
        challenge(
          startsAt: DateTime(2026, 10, 20),
          endsAt: DateTime(2026, 10, 27),
        ),
      ];
      final repo = build(db);
      final list = await repo.challenges('L1');
      expect(list.single.failed, isTrue);
      expect(awarded, isEmpty);
    }, skip: skip);

    test(
      'progress: live from summaries, stored once settled, cached offline',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = build(db);
        final members = [member('me'), member('sam')];
        api.tripRows = [
          t('me', score: 90),
          t('sam', score: 70),
          t('sam', score: 88),
        ];
        final live = await repo.progress(challenge(target: 3), members);
        expect(live.value, 2);
        expect(live.needed, 3);
        expect(api.calls, ['trips:me,sam']);

        api.failWith = StateError('offline');
        final cached = await repo.progress(challenge(target: 3), members);
        expect(cached.value, 2, reason: 'last computed board');

        final done = await repo.progress(
          challenge(status: 'succeeded', value: 6),
          members,
        );
        expect(done.value, 6);
        expect(done.met, isTrue);
      },
      skip: skip,
    );

    test('cancel drops it from the cache', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      final c = await repo.create(
        leagueId: 'L1',
        goal: ChallengeGoal.cleanTrips,
        target: 5,
      );
      await repo.cancel(c);
      expect(api.calls, contains('cancel:${c.id}'));
      expect(await repo.current('L1', refresh: false), isNull);
    }, skip: skip);
  });
}
