import 'dart:convert';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drivalry/data/repos/duels_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/sqlite_support.dart';

DuelTrip trip(String u, {int xp = 50, int score = 90, bool phone = false}) =>
    DuelTrip(userId: u, xp: xp, score: score, phoneHandling: phone);

DuelParty party(String id) =>
    DuelParty(userId: id, handle: id, displayName: id.toUpperCase());

Duel duel({
  String id = 'd1',
  String challenger = 'me',
  String opponent = 'sam',
  DuelMetric metric = DuelMetric.xp,
  DuelStatus status = DuelStatus.pending,
  DateTime? createdAt,
  DateTime? startsAt,
  DateTime? endsAt,
  DateTime? finishedAt,
  double? challengerValue,
  double? opponentValue,
  String? winnerId,
  String? loserBadgeId,
}) => Duel(
  id: id,
  challenger: party(challenger),
  opponent: party(opponent),
  metric: metric,
  status: status,
  createdAt: createdAt ?? DateTime(2026, 11, 1),
  startsAt: startsAt,
  endsAt: endsAt,
  finishedAt: finishedAt,
  challengerValue: challengerValue,
  opponentValue: opponentValue,
  challengerTrips: challengerValue == null ? null : 3,
  opponentTrips: opponentValue == null ? null : 3,
  winnerId: winnerId,
  loserBadgeId: loserBadgeId,
);

/// Scriptable cloud for the repo tests.
class FakeDuelsApi implements DuelsApi {
  final calls = <String>[];
  List<Duel> duels = [];
  List<DuelTrip> tripRows = [];
  Object? failWith;

  /// Fails only `create` (the insert), leaving reads working.
  Object? failCreateWith;

  void _call(String call) {
    calls.add(call);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<Duel>> myDuels(String userId) async {
    _call('myDuels');
    return duels;
  }

  @override
  Future<void> create({
    required String id,
    required String challengerId,
    required String opponentId,
    required DuelMetric metric,
  }) async {
    _call('create:$id:$challengerId:$opponentId:${metric.wire}');
    if (failCreateWith != null) throw failCreateWith!;
    duels = [
      duel(
        id: id,
        challenger: challengerId,
        opponent: opponentId,
        metric: metric,
      ),
      ...duels,
    ];
  }

  @override
  Future<String> respond(String duelId, bool accept) async {
    _call('respond:$duelId:$accept');
    return accept ? 'active' : 'declined';
  }

  @override
  Future<Map<String, dynamic>> finalize(String duelId) async {
    _call('finalize:$duelId');
    duels = [
      for (final d in duels)
        if (d.id == duelId)
          d.copyWith(
            status: DuelStatus.finished,
            finishedAt: DateTime(2026, 11, 10),
            challengerValue: 10,
            opponentValue: 5,
            winnerId: d.challenger.userId,
          )
        else
          d,
    ];
    return {'status': 'finished'};
  }

  @override
  Future<void> pickBadge(String duelId, String badgeId) async =>
      _call('badge:$duelId:$badgeId');

  @override
  Future<void> cancel(String duelId) async => _call('cancel:$duelId');

  @override
  Future<List<DuelTrip>> trips(
    List<String> userIds,
    DateTime from,
    DateTime to,
  ) async {
    _call('trips:${userIds.join(',')}');
    return tripRows.where((t) => userIds.contains(t.userId)).toList();
  }
}

void main() {
  group('duelValue', () {
    test('xp sums every scored trip', () {
      final v = duelValue(DuelMetric.xp, [
        trip('a', xp: 60),
        trip('a', xp: 45),
        trip('a', xp: 0),
      ]);
      expect(v.value, 105);
      expect(v.trips, 3);
    });

    test('score average is forfeited under three trips', () {
      final two = duelValue(DuelMetric.scoreAvg, [
        trip('a', score: 100),
        trip('a', score: 100),
      ]);
      expect(two.value, 0);
      expect(two.trips, 2);
      final three = duelValue(DuelMetric.scoreAvg, [
        trip('a', score: 90),
        trip('a', score: 85),
        trip('a', score: 92),
      ]);
      expect(three.value, 89.0);
      final uneven = duelValue(DuelMetric.scoreAvg, [
        trip('a', score: 90),
        trip('a', score: 85),
        trip('a', score: 85),
      ]);
      expect(uneven.value, 86.67, reason: 'two decimals like the SQL');
    });

    test('phone-free counts trips the phone stayed down for', () {
      final v = duelValue(DuelMetric.phoneFree, [
        trip('a'),
        trip('a', phone: true),
        trip('a'),
      ]);
      expect(v.value, 2);
      expect(v.trips, 3);
    });

    test('scoreDuel splits trips by driver and names the leader', () {
      final d = duel(status: DuelStatus.active);
      final board = scoreDuel(d, [
        trip('me', xp: 100),
        trip('sam', xp: 60),
        trip('sam', xp: 60),
        trip('kim', xp: 999),
      ]);
      expect(board.challenger.value, 100);
      expect(board.opponent.value, 120);
      expect(board.leaderId(d), 'sam');
      final tie = scoreDuel(d, [trip('me', xp: 10), trip('sam', xp: 10)]);
      expect(tie.leaderId(d), isNull);
    });
  });

  group('Duel', () {
    test('json round-trips with both parties', () {
      final d = duel(
        status: DuelStatus.finished,
        startsAt: DateTime(2026, 11, 2, 9),
        endsAt: DateTime(2026, 11, 9, 9),
        finishedAt: DateTime(2026, 11, 9, 10),
        challengerValue: 88.5,
        opponentValue: 70,
        winnerId: 'me',
        loserBadgeId: 'lead_foot',
      );
      final back = Duel.fromJson(
        jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
      );
      expect(back.id, 'd1');
      expect(back.challenger.handle, 'me');
      expect(back.opponent.displayName, 'SAM');
      expect(back.status, DuelStatus.finished);
      expect(back.startsAt, d.startsAt);
      expect(back.challengerValue, 88.5);
      expect(back.winnerId, 'me');
      expect(back.loserId, 'sam');
      expect(back.loserBadgeId, 'lead_foot');
      expect(back.isDraw, isFalse);
    });

    test('reads the PostgREST row shape with embedded profiles', () {
      final d = Duel.fromJson({
        'id': 'x',
        'challenger_id': 'u1',
        'opponent_id': 'u2',
        'challenger': {'user_id': 'u1', 'handle': 'ryan', 'display_name': ''},
        'opponent': {'user_id': 'u2', 'handle': 'sam', 'display_name': 'Sam'},
        'metric': 'phone_free',
        'status': 'active',
        'created_at': '2026-11-01T10:00:00Z',
        'starts_at': '2026-11-01T11:00:00Z',
        'ends_at': '2026-11-08T11:00:00Z',
      });
      expect(d.metric, DuelMetric.phoneFree);
      expect(d.other('u1').handle, 'sam');
      expect(d.isDue(DateTime.utc(2026, 11, 8, 10)), isFalse);
      expect(d.isDue(DateTime.utc(2026, 11, 8, 11)), isTrue);
    });
  });

  group('DuelsRepo', () {
    final skip = skipWithoutSqlite();
    late FakeDuelsApi api;
    var now = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch;
    String? uid = 'me';

    setUp(() {
      api = FakeDuelsApi();
      now = DateTime(2026, 11, 3, 12).millisecondsSinceEpoch;
      uid = 'me';
    });

    DuelsRepo build(dynamic db) {
      final worker = OutboxWorker(db, now: () => now);
      addTearDown(worker.dispose);
      return DuelsRepo(
        db: db,
        api: api,
        outbox: worker,
        userId: () => uid,
        now: () => now,
      );
    }

    test('challenge caches a pending duel and delivers duel_create', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      final d = await repo.challenge(
        opponent: party('sam'),
        metric: DuelMetric.scoreAvg,
      );
      expect(d.status, DuelStatus.pending);
      expect(
        api.calls,
        contains('create:${d.id}:me:sam:score_avg'),
        reason: 'the outbox drained the create',
      );
      final cached = await repo.cachedMyDuels();
      expect(cached.single.id, d.id);
      expect(await db.dueOutbox(now + 1), isEmpty);
    }, skip: skip);

    test(
      'an undelivered challenge survives refreshes and blocks a second one',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.failCreateWith = StateError('offline');
        final repo = build(db);
        final d = await repo.challenge(
          opponent: party('sam'),
          metric: DuelMetric.xp,
        );
        expect(api.calls, contains('myDuels'), reason: 'the refresh still ran');
        expect((await repo.cachedMyDuels()).map((x) => x.id), [d.id]);
        expect((await db.outboxOfKind(DuelsRepo.kindCreate)).length, 1);
        expect(
          () => repo.challenge(opponent: party('sam'), metric: DuelMetric.xp),
          throwsA(isA<DuelException>()),
          reason: 'the pending row is still there to collide with',
        );
        await repo.refreshMyDuels();
        expect((await repo.cachedMyDuels()).map((x) => x.id), [d.id]);

        // Delivered later: the server row takes over and the outbox is empty.
        api.failCreateWith = null;
        now += 3_600_000;
        expect(await repo.outbox.drain(), 1);
        await repo.refreshMyDuels();
        expect((await repo.cachedMyDuels()).single.id, d.id);
        expect(await db.outboxOfKind(DuelsRepo.kindCreate), isEmpty);
      },
      skip: skip,
    );

    test(
      'the Leagues badge pulls duels as soon as someone is signed in',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.duels = [duel(id: 'd1', challenger: 'sam', opponent: 'me')];
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(db),
            duelsApiProvider.overrideWithValue(api),
            currentUserIdProvider.overrideWithValue('me'),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(pendingDuelCountProvider, (_, _) {});
        addTearDown(sub.close);
        for (
          var i = 0;
          i < 50 && container.read(pendingDuelCountProvider) == 0;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(api.calls, contains('myDuels'));
        expect(container.read(pendingDuelCountProvider), 1);
      },
      skip: skip,
    );

    test('one open duel per pair', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      await repo.challenge(opponent: party('sam'), metric: DuelMetric.xp);
      expect(
        () => repo.challenge(opponent: party('sam'), metric: DuelMetric.xp),
        throwsA(isA<DuelException>()),
      );
      expect(
        () => repo.challenge(opponent: party('me'), metric: DuelMetric.xp),
        throwsA(isA<DuelException>()),
        reason: 'not yourself',
      );
    }, skip: skip);

    test('challenge needs a signed-in user', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      uid = null;
      final repo = build(db);
      expect(
        () => repo.challenge(opponent: party('sam'), metric: DuelMetric.xp),
        throwsA(isA<DuelException>()),
      );
    }, skip: skip);

    test('respond flips the cache and queues duel_respond', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.duels = [duel(challenger: 'sam', opponent: 'me')];
      final repo = build(db);
      await repo.refreshMyDuels();
      await repo.respond('d1', accept: true);
      final cached = (await repo.cachedMyDuels()).single;
      expect(cached.status, DuelStatus.active);
      expect(cached.startsAt, DateTime.fromMillisecondsSinceEpoch(now));
      expect(
        cached.endsAt,
        DateTime.fromMillisecondsSinceEpoch(now).add(const Duration(days: 7)),
      );
      expect(api.calls, contains('respond:d1:true'));
    }, skip: skip);

    test('declining goes through the same kind with accept false', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.duels = [duel(challenger: 'sam', opponent: 'me')];
      final repo = build(db);
      await repo.refreshMyDuels();
      api.failWith = StateError('offline');
      await repo.respond('d1', accept: false);
      expect((await repo.cachedMyDuels()).single.status, DuelStatus.declined);
      final row = (await db.dueOutbox(now + 3_600_000)).single;
      expect(row.id, 'duel_respond:d1');
      expect(row.kind, DuelsRepo.kindRespond);
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      expect(payload, {'duel_id': 'd1', 'user_id': 'me', 'accept': false});
    }, skip: skip);

    test(
      'a respond the cloud already settled is dropped, not retried',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = build(db);
        api.failWith = PostgrestException(message: 'answered', code: 'P0006');
        await repo.outbox.enqueue(DuelsRepo.kindRespond, {
          'duel_id': 'd9',
          'user_id': 'me',
          'accept': true,
        }, id: 'duel_respond:d9');
        expect(await repo.outbox.drain(), 1, reason: 'counted as delivered');
        expect(await db.dueOutbox(now + 3_600_000), isEmpty);
      },
      skip: skip,
    );

    test("another account's rows stay queued for them", () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = build(db);
      await repo.outbox.enqueue(DuelsRepo.kindCreate, {
        'id': 'z',
        'challenger_id': 'someone_else',
        'opponent_id': 'sam',
        'metric': 'xp',
      });
      expect(await repo.outbox.drain(), 0);
      expect((await db.dueOutbox(now)).single.attempts, 0);
      expect(api.calls, isEmpty);
    }, skip: skip);

    test('refresh settles a running duel whose week is over', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.duels = [
        duel(
          status: DuelStatus.active,
          startsAt: DateTime(2026, 10, 20),
          endsAt: DateTime(2026, 10, 27),
        ),
      ];
      final repo = build(db);
      final list = await repo.refreshMyDuels();
      expect(api.calls, ['myDuels', 'finalize:d1', 'myDuels']);
      expect(list.single.status, DuelStatus.finished);
      expect(list.single.winnerId, 'me');
    }, skip: skip);

    test('refresh falls back to the cache when offline', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.duels = [duel()];
      final repo = build(db);
      await repo.refreshMyDuels();
      api.failWith = StateError('offline');
      expect(repo.refreshMyDuels(), throwsA(isA<StateError>()));
      expect((await repo.cachedMyDuels()).single.id, 'd1');
    }, skip: skip);

    test(
      'scoreboard: stored values when finished, summaries while running',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final repo = build(db);
        final finished = duel(
          status: DuelStatus.finished,
          challengerValue: 12,
          opponentValue: 7,
        );
        final board = await repo.scoreboard(finished);
        expect(board.challenger.value, 12);
        expect(api.calls, isEmpty);

        api.tripRows = [trip('me', xp: 30), trip('sam', xp: 80)];
        final running = duel(
          status: DuelStatus.active,
          startsAt: DateTime(2026, 11, 1),
          endsAt: DateTime(2026, 11, 8),
        );
        final live = await repo.scoreboard(running);
        expect(live.opponent.value, 80);
        expect(live.leaderId(running), 'sam');
        expect(api.calls, ['trips:me,sam']);

        // Offline: the last board is cached per duel.
        api.failWith = StateError('offline');
        final cached = await repo.scoreboard(running);
        expect(cached.challenger.value, 30);
      },
      skip: skip,
    );

    test(
      'pickBadge only accepts the fixed list and updates the cache',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        api.duels = [
          duel(
            status: DuelStatus.finished,
            challengerValue: 9,
            opponentValue: 1,
            winnerId: 'me',
          ),
        ];
        final repo = build(db);
        await repo.refreshMyDuels();
        expect(
          () => repo.pickBadge('d1', 'wall_of_shame'),
          throwsA(isA<DuelException>()),
        );
        await repo.pickBadge('d1', 'butterfingers');
        expect(api.calls, contains('badge:d1:butterfingers'));
        expect(
          (await repo.cachedMyDuels()).single.loserBadgeId,
          'butterfingers',
        );
      },
      skip: skip,
    );

    test('cancel removes a sent challenge', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.duels = [duel()];
      final repo = build(db);
      await repo.refreshMyDuels();
      await repo.cancel('d1');
      expect(api.calls, contains('cancel:d1'));
      expect(await repo.cachedMyDuels(), isEmpty);
    }, skip: skip);

    test('record counts wins and losses inside a window', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      api.duels = [
        duel(
          id: 'w',
          status: DuelStatus.finished,
          finishedAt: DateTime(2026, 11, 5),
          winnerId: 'me',
        ),
        duel(
          id: 'l',
          status: DuelStatus.finished,
          finishedAt: DateTime(2026, 11, 6),
          winnerId: 'sam',
        ),
        duel(
          id: 'old',
          status: DuelStatus.finished,
          finishedAt: DateTime(2026, 9, 1),
          winnerId: 'me',
        ),
        duel(
          id: 'draw',
          status: DuelStatus.finished,
          finishedAt: DateTime(2026, 11, 7),
        ),
      ];
      final repo = build(db);
      await repo.refreshMyDuels();
      expect(await repo.record(DateTime(2026, 10, 1), DateTime(2027, 1, 1)), (
        1,
        1,
      ));
    }, skip: skip);
  });
}
