import 'dart:typed_data';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/google/places_client.dart' show StopCategory;
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/sqlite_support.dart';

/// Records every call; answers from canned data.
class FakeConvoysApi implements ConvoysApi {
  final List<String> calls = [];
  List<Convoy> convoys = const [];
  Map<String, List<ConvoyMember>> membersBy = {};
  Map<String, List<ConvoyStop>> stopsBy = {};
  Object? joinError;

  @override
  Future<List<Convoy>> myConvoys(String userId) async {
    calls.add('myConvoys:$userId');
    return convoys;
  }

  @override
  Future<Convoy?> convoy(String id) async {
    calls.add('convoy:$id');
    return convoys.where((c) => c.id == id).firstOrNull;
  }

  @override
  Future<List<ConvoyMember>> members(String convoyId) async {
    calls.add('members:$convoyId');
    return membersBy[convoyId] ?? const [];
  }

  @override
  Future<List<ConvoyStop>> stops(String convoyId) async {
    calls.add('stops:$convoyId');
    return stopsBy[convoyId] ?? const [];
  }

  @override
  Future<List<ConvoyExpense>> expenses(String convoyId) async {
    calls.add('expenses:$convoyId');
    return const [];
  }

  @override
  Future<List<ConvoyPhoto>> photos(String convoyId) async {
    calls.add('photos:$convoyId');
    return const [];
  }

  @override
  Future<String> joinByCode(String code) async {
    calls.add('join:$code');
    final e = joinError;
    if (e != null) throw ConvoyJoinException(mapConvoyJoinError(e));
    return 'joined-convoy';
  }

  @override
  Future<void> createConvoy({
    required String id,
    required String name,
    required String userId,
    Destination? destination,
  }) async => calls.add('create:$id:$name:$userId:${destination?.name}');

  @override
  Future<void> updateConvoy(String id, Map<String, Object?> fields) async =>
      calls.add('update:$id:${fields.keys.join(',')}');

  @override
  Future<void> setStatus(String id, ConvoyStatus status, DateTime at) async =>
      calls.add('status:$id:${status.wire}');

  @override
  Future<void> leave({
    required String convoyId,
    required String userId,
  }) async => calls.add('leave:$convoyId:$userId');

  @override
  Future<void> proposeStop(Map<String, Object?> row) async =>
      calls.add('proposeStop:${row['id']}:${row['category']}');

  @override
  Future<void> vote({
    required String stopId,
    required String userId,
    required int vote,
  }) async => calls.add('vote:$stopId:$userId:$vote');

  @override
  Future<void> removeVote({
    required String stopId,
    required String userId,
  }) async => calls.add('unvote:$stopId:$userId');

  @override
  Future<void> setStopStatus(String stopId, StopStatus status) async =>
      calls.add('stopStatus:$stopId:${status.wire}');

  @override
  Future<void> addExpense(Map<String, Object?> row) async =>
      calls.add('addExpense:${row['id']}:${row['amount_cents']}');

  @override
  Future<void> deleteExpense(String id) async => calls.add('deleteExpense:$id');

  @override
  Future<void> uploadPhoto(String path, Uint8List jpeg) async =>
      calls.add('upload:$path:${jpeg.length}');

  @override
  Future<void> addPhoto(Map<String, Object?> row) async =>
      calls.add('addPhoto:${row['id']}');

  @override
  Future<void> deletePhoto(String id, String storagePath) async =>
      calls.add('deletePhoto:$id');

  @override
  Future<String> signedPhotoUrl(
    String storagePath, {
    int seconds = 3600,
  }) async {
    calls.add('signed:$storagePath');
    return 'https://x/$storagePath?sig';
  }

  @override
  Future<List<ConvoyTripSummary>> tripSummariesBetween(
    List<String> userIds,
    DateTime from,
    DateTime to,
  ) async {
    calls.add('summaries:${userIds.join(',')}');
    return const [];
  }
}

void main() {
  final skip = skipWithoutSqlite();

  group('mapping', () {
    test('Convoy.fromMembershipRow reads the embedded convoy', () {
      final c = Convoy.fromMembershipRow({
        'convoy_id': 'c1',
        'convoys': {
          'id': 'c1',
          'name': 'Coast run',
          'created_by': 'u1',
          'status': 'active',
          'destination': {'name': 'Big Sur', 'lat': 36.27, 'lon': -121.8},
          'invite_code': 'abc12345',
          'max_cars': 6,
          'created_at': '2026-11-01T00:00:00Z',
          'started_at': '2026-11-02T09:00:00Z',
        },
      }, memberCount: 3);
      expect(c.isActive, isTrue);
      expect(c.destination?.name, 'Big Sur');
      expect(c.memberCount, 3);
      expect(c.inviteLink, 'drivalry://join/convoy/abc12345');
      expect(Convoy.fromJson(c.toJson()).toJson(), c.toJson());
    });

    test('ConvoyStop.fromRow folds votes', () {
      final s = ConvoyStop.fromRow({
        'id': 's1',
        'convoy_id': 'c1',
        'proposed_by': 'u1',
        'category': 'food',
        'name': 'Tacos',
        'lat': 36.0,
        'lon': -121.0,
        'status': 'proposed',
        'created_at': '2026-11-01T00:00:00Z',
        'convoy_stop_votes': [
          {'user_id': 'u1', 'vote': 1},
          {'user_id': 'u2', 'vote': -1},
          {'user_id': 'u3', 'vote': 1},
        ],
      });
      expect(s.category, StopCategory.food);
      expect(s.upVotes, 2);
      expect(s.downVotes, 1);
      expect(s.score, 1);
      expect(ConvoyStop.fromRow(s.toJson()).votes, s.votes);
    });

    test('join errors map from the RPC codes', () {
      expect(
        mapConvoyJoinError(
          const PostgrestException(
            message: 'invalid invite code',
            code: 'P0001',
          ),
        ),
        ConvoyJoinError.invalidCode,
      );
      expect(
        mapConvoyJoinError(
          const PostgrestException(message: 'convoy is full', code: 'P0002'),
        ),
        ConvoyJoinError.full,
      );
      expect(mapConvoyJoinError(StateError('x')), ConvoyJoinError.unavailable);
    });
  });

  group('ConvoyRepo', () {
    late AppDatabase db;
    late FakeConvoysApi api;
    late OutboxWorker outbox;
    late ConvoyRepo repo;
    String? me = 'u1';
    var now = 1_000_000;

    setUp(() {
      db = memoryDatabase();
      api = FakeConvoysApi();
      outbox = OutboxWorker(db, now: () => now);
      me = 'u1';
      repo = ConvoyRepo(
        apiOf: () => me == null ? null : api,
        db: db,
        outbox: outbox,
        me: () => me,
        now: () => now,
      );
      repo.registerHandlers(outbox);
    });
    tearDown(() => db.close());

    test('create caches me as leader and uploads through the outbox', () async {
      final id = await repo.create(
        'Coast run',
        destination: const Destination(name: 'Big Sur', lat: 36, lon: -121),
      );
      final cached = await repo.cached();
      expect(cached!.single.id, id);
      expect(cached.single.createdBy, 'u1');
      expect(cached.single.status, ConvoyStatus.planning);
      expect((await repo.cachedMembers(id))!.single.isLeader, isTrue);
      await outbox.drain();
      expect(api.calls, ['create:$id:Coast run:u1:Big Sur']);
      // Idempotent id: a second drain sends nothing.
      await outbox.drain();
      expect(api.calls.length, 1);
    });

    test('join calls the RPC then refreshes the list', () async {
      api.convoys = [
        Convoy(
          id: 'joined-convoy',
          name: 'X',
          createdBy: 'u9',
          status: ConvoyStatus.planning,
          inviteCode: 'zz',
          createdAt: DateTime.utc(2026),
        ),
      ];
      final id = await repo.join('ZZ ');
      expect(id, 'joined-convoy');
      expect(api.calls, ['join:zz', 'myConvoys:u1']);
      expect((await repo.cached())!.single.id, 'joined-convoy');
    });

    test('join errors surface as ConvoyJoinException', () async {
      api.joinError = const PostgrestException(message: 'full', code: 'P0002');
      await expectLater(
        repo.join('abc'),
        throwsA(
          isA<ConvoyJoinException>().having(
            (e) => e.error,
            'error',
            ConvoyJoinError.full,
          ),
        ),
      );
      me = null;
      await expectLater(repo.join('abc'), throwsA(isA<ConvoyJoinException>()));
    });

    test('destination and status update the cache first', () async {
      final id = await repo.create('Trip');
      await repo.setDestination(
        id,
        const Destination(name: 'Lake', lat: 40, lon: -100),
      );
      expect((await repo.cachedConvoy(id))!.destination!.name, 'Lake');
      now += 1000;
      await repo.setStatus(id, ConvoyStatus.active);
      final c = (await repo.cachedConvoy(id))!;
      expect(c.isActive, isTrue);
      expect(c.startedAt!.millisecondsSinceEpoch, now);
      await outbox.drain();
      expect(api.calls, [
        'create:$id:Trip:u1:null',
        'update:$id:destination',
        'status:$id:active',
      ]);
    });

    test('each status change is its own outbox row', () async {
      final id = await repo.create('Trip');
      await repo.setStatus(id, ConvoyStatus.active);
      now += 1000;
      await repo.setStatus(id, ConvoyStatus.ended);
      await outbox.drain();
      // One shared id would make "ended" overwrite "active" before upload
      // and the server would never see started_at.
      expect(api.calls.where((c) => c.startsWith('status:')), [
        'status:$id:active',
        'status:$id:ended',
      ]);
    });

    test('stops: propose with my vote, vote, accept', () async {
      final sid = await repo.proposeStop(
        'c1',
        category: StopCategory.gas,
        name: '',
        lat: 40,
        lon: -100,
      );
      var stops = (await repo.cachedStops('c1'))!;
      expect(stops.single.name, 'Gas');
      expect(stops.single.votes, {'u1': 1});
      await repo.vote('c1', sid, -5);
      stops = (await repo.cachedStops('c1'))!;
      expect(stops.single.votes, {'u1': -1});
      await repo.vote('c1', sid, 0);
      expect((await repo.cachedStops('c1'))!.single.votes, isEmpty);
      await repo.vote('c1', sid, 1);
      await repo.setStopStatus('c1', sid, StopStatus.accepted);
      expect(
        (await repo.cachedStops('c1'))!.single.status,
        StopStatus.accepted,
      );
      await outbox.drain();
      // Same stable id: only the latest vote is sent.
      expect(api.calls, [
        'proposeStop:$sid:gas',
        'vote:$sid:u1:1',
        'stopStatus:$sid:accepted',
      ]);
    });

    test('expenses validate, cache and delete', () async {
      await expectLater(
        repo.addExpense('c1', amountCents: 0, category: 'gas'),
        throwsArgumentError,
      );
      final id = await repo.addExpense(
        'c1',
        amountCents: 4500,
        category: 'bogus',
        note: '  ',
      );
      final e = (await repo.cachedExpenses('c1'))!.single;
      expect(e.category, 'other');
      expect(e.note, isNull);
      expect(e.payerId, 'u1');
      await repo.deleteExpense('c1', id);
      expect(await repo.cachedExpenses('c1'), isEmpty);
      await outbox.drain();
      expect(api.calls, ['addExpense:$id:4500', 'deleteExpense:$id']);
    });

    test('photos: size and count limits, upload then row', () async {
      await expectLater(
        repo.addPhoto('c1', Uint8List(ConvoyRepo.maxPhotoBytes + 1)),
        throwsA(isA<ConvoyError>()),
      );
      final id = await repo.addPhoto('c1', Uint8List(1000));
      expect(api.calls, ['upload:c1/$id.jpg:1000']);
      expect((await repo.cachedPhotos('c1'))!.single.storagePath, 'c1/$id.jpg');
      await outbox.drain();
      expect(api.calls.last, 'addPhoto:$id');

      // Signed URLs are cached for an hour.
      expect(await repo.photoUrl('c1', 'c1/$id.jpg'), contains('sig'));
      expect(await repo.photoUrl('c1', 'c1/$id.jpg'), contains('sig'));
      expect(api.calls.where((c) => c.startsWith('signed:')).length, 1);

      me = null;
      await expectLater(
        repo.addPhoto('c1', Uint8List(10)),
        throwsA(isA<ConvoyError>()),
      );
    });

    test('leave drops the convoy and its caches', () async {
      final id = await repo.create('Trip');
      await repo.proposeStop(
        id,
        category: StopCategory.food,
        name: 'X',
        lat: 1,
        lon: 1,
      );
      await repo.leave(id);
      expect(await repo.cached(), isEmpty);
      expect(await repo.cachedStops(id), isNull);
      expect(await repo.cachedMembers(id), isNull);
      await outbox.drain();
      expect(api.calls.last, 'leave:$id:u1');
    });

    test('handlers skip rows queued by another account', () async {
      await outbox.enqueue(ConvoyRepo.kindStatus, {
        'convoy_id': 'c9',
        'user_id': 'someone-else',
        'status': 'ended',
        'at': '2026-11-03T00:00:00Z',
      }, id: 'convoy_status:c9');
      await outbox.drain();
      expect(api.calls, isEmpty);
    });

    test('fetchMembers caches; cache answers when signed out', () async {
      api.membersBy['c1'] = [
        ConvoyMember(
          userId: 'u2',
          handle: 'bo',
          displayName: 'Bo',
          role: 'member',
          joinedAt: DateTime.utc(2026),
        ),
      ];
      expect((await repo.fetchMembers('c1')).single.name, 'Bo');
      me = null;
      expect((await repo.fetchMembers('c1')).single.name, 'Bo');
      expect(api.calls, ['members:c1']);
    });
  }, skip: skip);
}
