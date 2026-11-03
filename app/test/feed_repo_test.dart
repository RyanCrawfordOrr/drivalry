import 'dart:convert';

import 'package:drivalry/data/repos/feed_repo.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

Map<String, dynamic> postRow({
  String id = 'p1',
  String kind = 'trip',
  Map<String, dynamic>? body,
  List<Map<String, dynamic>> reactions = const [],
  int comments = 0,
}) => {
  'id': id,
  'author_id': 'alice',
  'kind': kind,
  'trip_id': 't1',
  'body':
      body ?? {'score': 91, 'roast': 'Smooth as butter.', 'speeding': false},
  'created_at': '2026-11-02T10:00:00Z',
  'profiles': {'handle': 'alice', 'display_name': 'Alice', 'avatar_path': null},
  'feed_reactions': reactions,
  'feed_comments': [
    {'count': comments},
  ],
};

void main() {
  group('FeedPost.fromRow', () {
    test('counts reactions, marks mine, reads the comment count', () {
      final post = FeedPost.fromRow(
        postRow(
          reactions: [
            {'kind': 'fire', 'user_id': 'bob'},
            {'kind': 'fire', 'user_id': 'me'},
            {'kind': 'laugh', 'user_id': 'bob'},
          ],
          comments: 4,
        ),
        'me',
      );
      expect(post.reactions, {'fire': 2, 'laugh': 1});
      expect(post.myReactions, {'fire'});
      expect(post.commentCount, 4);
      expect(post.author.name, 'Alice');
      expect(post.score, 91);
      expect(post.roastText, 'Smooth as butter.');
      expect(post.hasSpeeding, isFalse);
      expect(post.reckless, isFalse);
    });

    test('speeding and reckless flags, roast as an object', () {
      final post = FeedPost.fromRow(
        postRow(
          body: {
            'score': 20,
            'reckless': true,
            'roast': {'templateId': 'x', 'text': 'Yikes.'},
            'events': [
              {'kind': 'speeding', 'severity': 'major'},
            ],
          },
        ),
        null,
      );
      expect(post.hasSpeeding, isTrue);
      expect(post.reckless, isTrue);
      expect(post.roastText, 'Yikes.');
      expect(FeedPost.fromRow(postRow(kind: 'shame'), null).reckless, isTrue);
    });

    test('toggled adds and removes with counts', () {
      final post = FeedPost.fromRow(
        postRow(
          reactions: [
            {'kind': 'clap', 'user_id': 'me'},
          ],
        ),
        'me',
      );
      final off = post.toggled('clap');
      expect(off.myReactions, isEmpty);
      expect(off.reactions.containsKey('clap'), isFalse);
      final on = off.toggled('skull');
      expect(on.myReactions, {'skull'});
      expect(on.reactions['skull'], 1);
    });

    test('round-trips through the cache JSON', () {
      final post = FeedPost.fromRow(
        postRow(
          reactions: [
            {'kind': 'fire', 'user_id': 'me'},
          ],
          comments: 2,
        ),
        'me',
      );
      final back = FeedPost.fromJson(
        jsonDecode(jsonEncode(post.toJson())) as Map<String, dynamic>,
      );
      expect(back.id, 'p1');
      expect(back.author.handle, 'alice');
      expect(back.reactions, {'fire': 1});
      expect(back.myReactions, {'fire'});
      expect(back.commentCount, 2);
      expect(back.createdAt, post.createdAt);
    });
  });

  test('filters have distinct cache keys', () {
    expect(FeedRepo.cacheKey(FeedFilter.all, 0), 'feed:all:0');
    expect(FeedRepo.cacheKey(FeedFilter.fame, 2), 'feed:fame:2');
    expect(
      FeedRepo.cacheKey(FeedFilter.friend('u1', 'Bob'), 0),
      'feed:friend:u1:0',
    );
    expect(FeedFilter.friend('u1', 'Bob'), FeedFilter.friend('u1', 'Robert'));
  });

  test('reaction vocabulary', () {
    expect(reactionKinds, contains('snitch'));
    expect(reactionLabel('snitch'), 'Snitch');
    expect(reactionLabel('fire'), 'Fire');
    expect(reactionEmoji('skull'), '💀');
  });

  group('FeedRepo writes', () {
    final skip = skipWithoutSqlite();

    test('reactions and comments go through the outbox', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final repo = FeedRepo(
        clientOf: () => null,
        db: db,
        outbox: worker,
        me: () => 'me',
        now: () => 1,
      );
      final post = FeedPost.fromRow(postRow(), 'me');

      await repo.toggleReaction(post, 'fire');
      var due = await db.dueOutbox(1);
      expect(due.single.kind, FeedRepo.kindReaction);
      expect(jsonDecode(due.single.payload), {
        'post_id': 'p1',
        'user_id': 'me',
        'kind': 'fire',
        'op': 'add',
      });

      await repo.toggleReaction(post.toggled('fire'), 'fire');
      due = await db.dueOutbox(1);
      expect(jsonDecode(due.last.payload)['op'], 'remove');

      final long = 'x' * 300;
      final c = await repo.addComment('p1', long);
      expect(c, isNotNull);
      expect(c!.pending, isTrue);
      expect(c.body.length, 280);
      due = await db.dueOutbox(1);
      final row = due.firstWhere((r) => r.kind == FeedRepo.kindComment);
      final payload = jsonDecode(row.payload) as Map;
      expect(payload['id'], c.id);
      expect(payload['author_id'], 'me');
      expect((payload['body'] as String).length, 280);

      expect(await repo.addComment('p1', '   '), isNull);
    }, skip: skip);
  });
}
