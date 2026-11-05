import 'dart:convert';

import 'package:drivalry/data/repos/moderation_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

const me = 'me-0000';

const bob = BlockedUser(id: 'bob', handle: 'bob', displayName: 'Bob');

void main() {
  group('ModerationState', () {
    test('hides posts and comments by blocked people and reported ones', () {
      const s = ModerationState(
        blocked: [bob],
        hiddenPostIds: {'p-reported'},
        hiddenCommentIds: {'c-reported'},
      );
      expect(s.isBlocked('bob'), isTrue);
      expect(s.isBlocked('carol'), isFalse);
      expect(s.showsPost('p1', 'bob'), isFalse);
      expect(s.showsPost('p-reported', 'carol'), isFalse);
      expect(s.showsPost('p1', 'carol'), isTrue);
      expect(s.showsComment('c1', 'bob'), isFalse);
      expect(s.showsComment('c-reported', 'carol'), isFalse);
      expect(s.showsComment('c1', 'carol'), isTrue);
    });

    test('round-trips through JSON for the cache', () {
      final s = ModerationState(
        blocked: [
          BlockedUser(
            id: 'bob',
            handle: 'bob',
            displayName: 'Bob',
            avatarPath: 'avatars/bob.jpg',
            blockedAt: DateTime.utc(2026, 11, 5, 12),
          ),
        ],
        hiddenPostIds: const {'p1'},
        hiddenCommentIds: const {'c1'},
      );
      final back = ModerationState.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.blocked.single.id, 'bob');
      expect(back.blocked.single.avatarPath, 'avatars/bob.jpg');
      expect(back.blocked.single.blockedAt, DateTime.utc(2026, 11, 5, 12));
      expect(back.blocked.single.name, 'Bob');
      expect(back.hiddenPostIds, {'p1'});
      expect(back.hiddenCommentIds, {'c1'});
    });

    test('a person with no display name is shown by handle', () {
      const b = BlockedUser(id: 'x', handle: 'xx', displayName: '  ');
      expect(b.name, '@xx');
      expect(b.initials, 'X');
    });
  });

  test('report reasons use the wire names the database accepts', () {
    expect(ReportReason.values.map((r) => r.wire), [
      'abusive',
      'not_driving',
      'spam',
      'other',
    ]);
  });

  group('ModerationRepo writes', () {
    final skip = skipWithoutSqlite();

    test('block queues one idempotent row and updates the cache', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final repo = ModerationRepo(
        clientOf: () => null,
        db: db,
        outbox: worker,
        me: () => me,
        now: () => 1,
      );

      await repo.block(bob);
      await repo.block(bob); // twice: still one row, one cache entry
      final due = await db.dueOutbox(1);
      expect(due, hasLength(1));
      expect(due.single.kind, ModerationRepo.kindBlock);
      expect(due.single.id, 'block:$me:bob');
      final payload = jsonDecode(due.single.payload) as Map;
      expect(payload, {'blocker_id': me, 'blocked_id': 'bob'});

      final s = await repo.cached();
      expect(s.blocked.map((b) => b.id), ['bob']);
      expect(s.blocked.single.blockedAt, isNotNull);

      // Unblock: a second row, and the cache forgets them.
      await repo.unblock('bob');
      final all = await db.dueOutbox(1);
      expect(all.map((r) => r.kind), [
        ModerationRepo.kindBlock,
        ModerationRepo.kindUnblock,
      ]);
      expect((await repo.cached()).blocked, isEmpty);
    }, skip: skip);

    test('blocking yourself is ignored', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final repo = ModerationRepo(
        clientOf: () => null,
        db: db,
        outbox: worker,
        me: () => me,
        now: () => 1,
      );
      await repo.block(
        const BlockedUser(id: me, handle: 'me', displayName: ''),
      );
      expect(await db.dueOutbox(1), isEmpty);
      expect((await repo.cached()).blocked, isEmpty);
    }, skip: skip);

    test('a report queues the row and hides the content at once', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final repo = ModerationRepo(
        clientOf: () => null,
        db: db,
        outbox: worker,
        me: () => me,
        now: () => 1,
      );

      await repo.reportPost(
        postId: 'p1',
        authorId: 'bob',
        reason: ReportReason.abusive,
        details: '  rude  ',
        snapshot: const {'roast': 'Yikes.'},
      );
      await repo.reportComment(
        commentId: 'c1',
        postId: 'p1',
        authorId: 'carol',
        reason: ReportReason.spam,
      );
      final due = await db.dueOutbox(1);
      expect(due, hasLength(2));
      expect(due.map((r) => r.kind).toSet(), {ModerationRepo.kindReport});
      final post = jsonDecode(due.first.payload) as Map;
      expect(post['reporter_id'], me);
      expect(post['reported_user_id'], 'bob');
      expect(post['post_id'], 'p1');
      expect(post['comment_id'], isNull);
      expect(post['reason'], 'abusive');
      expect(post['details'], 'rude');
      expect(post['snapshot'], {'roast': 'Yikes.'});
      expect(post['id'], isA<String>());
      final comment = jsonDecode(due.last.payload) as Map;
      expect(comment['comment_id'], 'c1');
      expect(comment['post_id'], 'p1');
      expect(comment['reason'], 'spam');
      expect(comment['details'], isNull);

      final s = await repo.cached();
      expect(s.showsPost('p1', 'bob'), isFalse);
      expect(s.showsComment('c1', 'carol'), isFalse);
      // Reporting does not block.
      expect(s.isBlocked('bob'), isFalse);
      expect(s.showsPost('p2', 'bob'), isTrue);
    }, skip: skip);

    test('writes while signed out are dropped, not queued', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final repo = ModerationRepo(
        clientOf: () => null,
        db: db,
        outbox: worker,
        me: () => null,
        now: () => 1,
      );
      await repo.block(bob);
      await repo.reportPost(
        postId: 'p1',
        authorId: 'bob',
        reason: ReportReason.other,
      );
      expect(await db.dueOutbox(1), isEmpty);
    }, skip: skip);

    test('handlers skip rows that belong to another account', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final repo = ModerationRepo(
        clientOf: () => null,
        db: db,
        outbox: worker,
        me: () => me,
        now: () => 1,
      );
      // No client at all: the handler must say "retry later" for our own
      // rows (offline) and "skip" for someone else's, never crash.
      expect(
        () => repo.handleBlock({'blocker_id': me, 'blocked_id': 'bob'}),
        throwsA(isA<OutboxRetryLater>()),
      );
      expect(
        () => repo.handleReport({'reporter_id': me, 'post_id': 'p1'}),
        throwsA(isA<OutboxRetryLater>()),
      );
    }, skip: skip);
  });
}
