import 'dart:convert';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/circles_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/sqlite_support.dart';

/// Records every call; answers from canned data.
class FakeCirclesApi implements CirclesApi {
  final List<String> calls = [];
  List<Circle> circles = const [];
  Map<String, List<CircleMember>> membersByCircle = {};
  Object? joinError;

  @override
  Future<List<Circle>> myCircles(String userId) async {
    calls.add('myCircles:$userId');
    return circles;
  }

  @override
  Future<List<CircleMember>> members(String circleId) async {
    calls.add('members:$circleId');
    return membersByCircle[circleId] ?? const [];
  }

  @override
  Future<String> joinByCode(String code) async {
    calls.add('join:$code');
    final e = joinError;
    if (e != null) throw CircleJoinException(mapCircleJoinError(e));
    return 'joined-circle';
  }

  @override
  Future<void> createCircle({
    required String id,
    required String name,
    required String userId,
  }) async => calls.add('create:$id:$name:$userId');

  @override
  Future<void> setHiding({
    required String circleId,
    required String userId,
    required bool hiding,
  }) async => calls.add('hiding:$circleId:$userId:$hiding');

  @override
  Future<void> leave({
    required String circleId,
    required String userId,
  }) async => calls.add('leave:$circleId:$userId');

  @override
  Future<void> postCheckin({
    required String id,
    required String userId,
    required String label,
    required DateTime createdAt,
  }) async => calls.add('checkin:$userId:$label');
}

void main() {
  final skip = skipWithoutSqlite();

  group('mapping', () {
    test('Circle.fromMembershipRow reads the embedded circle', () {
      final c = Circle.fromMembershipRow({
        'circle_id': 'c1',
        'hiding': true,
        'joined_at': '2026-11-01T00:00:00Z',
        'circles': {
          'id': 'c1',
          'name': 'Family',
          'created_by': 'u1',
          'invite_code': 'abc12345',
          'created_at': '2026-10-01T00:00:00Z',
        },
      }, memberCount: 3);
      expect(c.id, 'c1');
      expect(c.name, 'Family');
      expect(c.myHiding, isTrue);
      expect(c.memberCount, 3);
      expect(c.inviteLink, 'drivalry://join/circle/abc12345');
      expect(Circle.fromJson(c.toJson()).toJson(), c.toJson());
    });

    test('CircleMember.fromRow reads the embedded profile', () {
      final m = CircleMember.fromRow({
        'user_id': 'u2',
        'hiding': false,
        'joined_at': '2026-11-01T00:00:00Z',
        'profiles': {'handle': 'sam', 'display_name': 'Sam Lee'},
      });
      expect(m.name, 'Sam Lee');
      expect(m.initials, 'SL');
      expect(m.hiding, isFalse);
      expect(CircleMember.fromRow(m.toJson()).name, 'Sam Lee');
    });

    test('join errors map from the RPC codes', () {
      expect(
        mapCircleJoinError(
          const PostgrestException(
            message: 'invalid invite code',
            code: 'P0001',
          ),
        ),
        CircleJoinError.invalidCode,
      );
      expect(
        mapCircleJoinError(
          const PostgrestException(message: 'boom', code: '500'),
        ),
        CircleJoinError.unavailable,
      );
      expect(mapCircleJoinError(StateError('x')), CircleJoinError.unavailable);
      expect(
        const CircleJoinException(CircleJoinError.invalidCode).message,
        contains('not valid'),
      );
    });
  });

  group('CirclesRepo', () {
    late AppDatabase db;
    late FakeCirclesApi api;
    late OutboxWorker outbox;
    late CirclesRepo repo;
    String? me = 'u1';
    var now = 1_000_000;

    setUp(() {
      db = memoryDatabase();
      api = FakeCirclesApi();
      outbox = OutboxWorker(db, now: () => now);
      me = 'u1';
      repo = CirclesRepo(
        apiOf: () => me == null ? null : api,
        db: db,
        outbox: outbox,
        me: () => me,
        now: () => now,
      );
      repo.registerHandlers(outbox);
    });
    tearDown(() async {
      outbox.dispose();
      await db.close();
    });

    test(
      'create caches optimistically and the handler reaches the api',
      () async {
        final id = await repo.create('  Roommates ');
        final cached = await repo.cached();
        expect(cached, hasLength(1));
        expect(cached!.single.name, 'Roommates');
        expect(cached.single.inviteCode, '');
        expect(cached.single.memberCount, 1);

        expect(await outbox.drain(), 1);
        expect(api.calls, ['create:$id:Roommates:u1']);
      },
    );

    test('fetch stores the list and mirrors hiding into Settings', () async {
      api.circles = [
        Circle(
          id: 'c1',
          name: 'Family',
          createdBy: 'u1',
          inviteCode: 'abc',
          createdAt: DateTime.utc(2026),
          memberCount: 2,
          myHiding: true,
        ),
      ];
      final list = await repo.fetch();
      expect(list.single.name, 'Family');
      expect(await db.getSetting('hiding:circle:c1'), 'true');
      expect((await repo.cached())!.single.myHiding, isTrue);
    });

    test(
      'setHiding mirrors locally, updates caches, queues the write',
      () async {
        api.circles = [
          Circle(
            id: 'c1',
            name: 'Family',
            createdBy: 'u1',
            inviteCode: 'abc',
            createdAt: DateTime.utc(2026),
          ),
        ];
        api.membersByCircle['c1'] = [
          CircleMember(
            userId: 'u1',
            handle: 'me',
            displayName: 'Me',
            hiding: false,
            joinedAt: DateTime.utc(2026),
          ),
        ];
        await repo.fetch();
        await repo.fetchMembers('c1');

        await repo.setHiding('c1', true);
        expect(await db.getSetting('hiding:circle:c1'), 'true');
        expect((await repo.cached())!.single.myHiding, isTrue);
        expect((await repo.cachedMembers('c1'))!.single.hiding, isTrue);

        // Flip again while offline: the stable id means the latest wins.
        await repo.setHiding('c1', false);
        expect(await outbox.drain(), 1);
        expect(api.calls.where((c) => c.startsWith('hiding:')), [
          'hiding:c1:u1:false',
        ]);
      },
    );

    test('checkIn posts only the label', () async {
      final id = await repo.checkIn('Home');
      expect(id, isNotNull);
      final row = (await db.dueOutbox(now)).single;
      expect(row.kind, CirclesRepo.kindCheckin);
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      expect(payload.keys.toSet(), {'id', 'user_id', 'label', 'created_at'});
      expect(payload['label'], 'Home');
      expect(payload.containsKey('lat'), isFalse);
      expect(await outbox.drain(), 1);
      expect(api.calls, ['checkin:u1:Home']);
    });

    test(
      'a row from another account is skipped, not delivered or dropped',
      () async {
        await repo.checkIn('Home');
        me = 'someone-else';
        expect(await outbox.drain(), 0);
        expect((await db.dueOutbox(now)).length, 1);
        expect(api.calls, isEmpty);
      },
    );

    test('signed out: handlers wait, writes are refused', () async {
      await repo.checkIn('Home');
      me = null;
      expect(await outbox.drain(), 0);
      expect((await db.dueOutbox(now)).single.attempts, 0);
      expect(await repo.checkIn('Work'), isNull);
      expect(() => repo.join('abc'), throwsA(isA<CircleJoinException>()));
    });

    test('join uses the RPC, then refreshes; errors surface typed', () async {
      api.circles = [
        Circle(
          id: 'joined-circle',
          name: 'Crew',
          createdBy: 'u9',
          inviteCode: 'zz',
          createdAt: DateTime.utc(2026),
        ),
      ];
      final id = await repo.join('ZZ');
      expect(id, 'joined-circle');
      expect(api.calls.first, 'join:ZZ');
      expect((await repo.cached())!.single.name, 'Crew');

      api.joinError = const PostgrestException(
        message: 'invalid invite code',
        code: 'P0001',
      );
      await expectLater(
        repo.join('nope'),
        throwsA(
          isA<CircleJoinException>().having(
            (e) => e.error,
            'error',
            CircleJoinError.invalidCode,
          ),
        ),
      );
    });

    test('leave drops the circle and its members from the cache', () async {
      api.circles = [
        Circle(
          id: 'c1',
          name: 'Family',
          createdBy: 'u1',
          inviteCode: 'abc',
          createdAt: DateTime.utc(2026),
        ),
      ];
      await repo.fetch();
      await repo.leave('c1');
      expect(await repo.cached(), isEmpty);
      expect(await outbox.drain(), 1);
      expect(api.calls.last, 'leave:c1:u1');
    });
  }, skip: skip);
}
