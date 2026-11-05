import 'dart:convert';

import 'package:drivalry/data/repos/friends_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

const me = 'me-0000';

Map<String, dynamic> profile(String id, String handle) => {
  'id': id,
  'handle': handle,
  'display_name': handle.toUpperCase(),
  'avatar_path': null,
  'driver_rating': 88.5,
};

Map<String, dynamic> row(
  String requester,
  String addressee,
  String status, {
  String createdAt = '2026-11-02T10:00:00Z',
}) => {
  'requester_id': requester,
  'addressee_id': addressee,
  'status': status,
  'created_at': createdAt,
  'requester': profile(requester, 'r_$requester'),
  'addressee': profile(addressee, 'a_$addressee'),
};

void main() {
  group('FriendsSnapshot.fromRows', () {
    test('splits friends, incoming and outgoing from my point of view', () {
      final s = FriendsSnapshot.fromRows([
        row(me, 'bob', 'accepted'),
        row('carol', me, 'accepted'),
        row('dave', me, 'pending', createdAt: '2026-11-02T11:00:00Z'),
        row(me, 'erin', 'pending'),
        row('frank', me, 'blocked'),
      ], me);
      expect(s.friends.map((f) => f.id), ['bob', 'carol']);
      expect(s.incoming.single.other.id, 'dave');
      expect(s.incoming.single.direction, FriendRequestDirection.incoming);
      expect(s.outgoing.single.other.id, 'erin');
      expect(s.outgoing.single.direction, FriendRequestDirection.outgoing);
      expect(s.isFriend('bob'), isTrue);
      expect(s.hasIncomingFrom('dave'), isTrue);
      expect(s.hasOutgoingTo('erin'), isTrue);
      expect(s.isFriend('frank'), isFalse);
    });

    test('round-trips through JSON for the cache', () {
      final s = FriendsSnapshot.fromRows(
        [row(me, 'bob', 'accepted'), row('dave', me, 'pending')],
        me,
        fetchedAt: DateTime.utc(2026, 11, 2),
      );
      final back = FriendsSnapshot.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.friends.single.handle, 'a_bob');
      expect(back.friends.single.driverRating, 88.5);
      expect(back.incoming.single.requesterId, 'dave');
      expect(back.fetchedAt, DateTime.utc(2026, 11, 2));
    });

    test('isStale: never fetched, or fetched longer ago than maxAge', () {
      final at = DateTime.utc(2026, 11, 5, 12);
      const maxAge = Duration(seconds: 30);
      final s = FriendsSnapshot.fromRows(const [], me, fetchedAt: at);
      expect(s.isStale(at.add(const Duration(seconds: 10)), maxAge), isFalse);
      expect(s.isStale(at.add(const Duration(seconds: 30)), maxAge), isFalse);
      expect(s.isStale(at.add(const Duration(seconds: 31)), maxAge), isTrue);
      // The cache from a previous session and a brand-new empty snapshot
      // both carry no fetch time and must be refetched.
      expect(const FriendsSnapshot().isStale(at, maxAge), isTrue);
      // Optimistic writes keep the fetch time, so they do not force a fetch.
      expect(s.copyWith(friends: const []).isStale(at, maxAge), isFalse);
    });
  });

  test('initials', () {
    expect(initialsOf('Ryan Orr'), 'RO');
    expect(initialsOf('@ryan'), 'R');
    expect(initialsOf('  '), '?');
  });

  group('FriendsRepo writes', () {
    final skip = skipWithoutSqlite();

    test('request, accept and remove queue idempotent outbox rows', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final repo = FriendsRepo(
        clientOf: () => null,
        db: db,
        outbox: worker,
        me: () => me,
        now: () => 1,
      );

      const bob = FriendProfile(id: 'bob', handle: 'bob', displayName: 'Bob');
      await repo.sendRequest(bob);
      await repo.sendRequest(bob); // twice: still one row
      var due = await db.dueOutbox(1);
      expect(due, hasLength(1));
      expect(due.single.kind, FriendsRepo.kindRequest);
      expect(jsonDecode(due.single.payload), {
        'requester_id': me,
        'addressee_id': 'bob',
      });
      expect((await repo.cached())!.hasOutgoingTo('bob'), isTrue);

      final req = FriendRequest(
        requesterId: 'dave',
        addresseeId: me,
        other: const FriendProfile(
          id: 'dave',
          handle: 'dave',
          displayName: 'Dave',
        ),
        direction: FriendRequestDirection.incoming,
        createdAt: DateTime.utc(2026),
      );
      await repo.accept(req);
      due = await db.dueOutbox(1);
      expect(due.map((r) => r.kind), contains(FriendsRepo.kindRespond));
      final respond = due.firstWhere((r) => r.kind == FriendsRepo.kindRespond);
      expect(jsonDecode(respond.payload)['status'], 'accepted');
      expect((await repo.cached())!.isFriend('dave'), isTrue);

      await repo.remove('dave');
      due = await db.dueOutbox(1);
      final remove = due.firstWhere((r) => r.kind == FriendsRepo.kindRemove);
      expect(jsonDecode(remove.payload), {'a': me, 'b': 'dave'});
      expect((await repo.cached())!.isFriend('dave'), isFalse);
    }, skip: skip);

    test('handlers wait for a session instead of failing', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final repo = FriendsRepo(
        clientOf: () => null,
        db: db,
        outbox: worker,
        me: () => me,
      );
      repo.registerHandlers(worker);
      await repo.sendRequest(
        const FriendProfile(id: 'bob', handle: 'bob', displayName: 'Bob'),
      );
      expect(await worker.drain(), 0);
      final row = (await db.dueOutbox(1)).single;
      expect(row.attempts, 0, reason: 'OutboxRetryLater does not count');
    }, skip: skip);
  });
}
