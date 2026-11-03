import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/data/sync/trip_upload.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

/// Records every cloud write instead of talking to Supabase.
class FakeTripCloud implements TripCloud {
  final List<String> calls = [];
  final Map<String, Map<String, Object?>> posts = {};
  final Map<String, Map<String, Object?>> summaries = {};

  @override
  Future<void> upsertSummary(Map<String, Object?> row) async {
    calls.add('summary:${row['id']}');
    summaries[row['id'] as String] = row;
  }

  @override
  Future<void> replaceEvents(
    String tripId,
    List<Map<String, Object?>> rows,
  ) async {
    calls.add('events:$tripId:${rows.length}');
  }

  @override
  Future<void> upsertPost(Map<String, Object?> row) async {
    calls.add('post:${row['kind']}');
    posts[row['id'] as String] = row;
  }

  @override
  Future<void> deletePosts(List<String> ids) async {
    calls.add('deletePosts:${ids.length}');
    ids.forEach(posts.remove);
  }

  @override
  Future<void> deleteSummary(String tripId) async {
    calls.add('deleteSummary:$tripId');
    summaries.remove(tripId);
  }
}

Map<String, dynamic> payload({
  required bool scored,
  bool passenger = false,
  bool reckless = false,
  bool speeding = true,
  String hash = 'h1',
}) => {
  'trip_id': 't1',
  'hash': hash,
  'summary': {
    'id': 't1',
    'started_at': '2026-11-03T10:00:00.000Z',
    'ended_at': '2026-11-03T10:30:00.000Z',
    'distance_m': 12000,
    'moving_s': 1500,
    'scored': scored,
    'is_passenger': passenger,
    'reckless': reckless,
    'score': scored ? 71 : null,
    'xp': scored ? 48 : 0,
    'components': scored
        ? {'speed': 9.5, 'smoothness': 4, 'attention': 7, 'efficiency': 8.5}
        : null,
    'roast': scored ? {'text': '41 in a 25 on Elm St', 'tone': 'savage'} : null,
  },
  'events': [
    if (scored && speeding)
      {
        'kind': 'speeding',
        'severity': 'moderate',
        'offset_s': 120,
        'duration_s': 90,
        'over_mps': 7.1,
        'road_name': 'Elm St',
        'way_id': 123,
      },
  ],
};

void main() {
  final skip = skipWithoutSqlite();
  final postId = TripSummaryPayload.postId('t1');
  final shameId = TripSummaryPayload.shamePostId('t1');

  group('trip_summary handler', () {
    test('first upload of a reckless trip creates both posts', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final outbox = OutboxWorker(db, now: () => 1);
      addTearDown(outbox.dispose);
      final cloud = FakeTripCloud();
      TripUploader(
        db,
        outbox,
        now: () => 1,
      ).registerCloudHandlers(cloud, () => 'me');

      await outbox.enqueue(
        TripUploader.kindSummary,
        payload(scored: true, reckless: true),
      );
      expect(await outbox.drain(), 1);
      expect(cloud.summaries['t1']!['user_id'], 'me');
      expect(cloud.posts.keys, containsAll([postId, shameId]));
      expect(cloud.posts[postId]!['body'], containsPair('speeding', true));
      expect(
        cloud.posts[postId]!['body'],
        containsPair('components', isA<Map>()),
      );
      expect(cloud.calls.where((c) => c.startsWith('deletePosts')), isEmpty);
      expect((await db.uploadedTrip('t1'))!.summaryHash, 'h1');
    }, skip: skip);

    test(
      're-marking the trip as a passenger ride removes both posts',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        final outbox = OutboxWorker(db, now: () => 1);
        addTearDown(outbox.dispose);
        final cloud = FakeTripCloud();
        TripUploader(
          db,
          outbox,
          now: () => 1,
        ).registerCloudHandlers(cloud, () => 'me');

        await outbox.enqueue(
          TripUploader.kindSummary,
          payload(scored: true, reckless: true),
          id: 'a',
        );
        await outbox.drain();
        expect(cloud.posts, hasLength(2));

        await outbox.enqueue(
          TripUploader.kindSummary,
          payload(scored: false, passenger: true, hash: 'h2'),
          id: 'b',
        );
        await outbox.drain();
        expect(cloud.posts, isEmpty);
        expect(cloud.summaries['t1']!['is_passenger'], isTrue);
        expect((await db.uploadedTrip('t1'))!.summaryHash, 'h2');
      },
      skip: skip,
    );

    test('a re-score out of reckless removes only the shame post', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final outbox = OutboxWorker(db, now: () => 1);
      addTearDown(outbox.dispose);
      final cloud = FakeTripCloud();
      TripUploader(
        db,
        outbox,
        now: () => 1,
      ).registerCloudHandlers(cloud, () => 'me');

      await outbox.enqueue(
        TripUploader.kindSummary,
        payload(scored: true, reckless: true),
        id: 'a',
      );
      await outbox.drain();
      await outbox.enqueue(
        TripUploader.kindSummary,
        payload(scored: true, reckless: false, hash: 'h2'),
        id: 'b',
      );
      await outbox.drain();
      expect(cloud.posts.keys, [postId]);
      expect(cloud.posts[postId]!['body'], containsPair('reckless', false));
    }, skip: skip);

    test('signed out waits; a delete removes the summary', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final outbox = OutboxWorker(db, now: () => 1);
      addTearDown(outbox.dispose);
      final cloud = FakeTripCloud();
      String? uid;
      TripUploader(
        db,
        outbox,
        now: () => 1,
      ).registerCloudHandlers(cloud, () => uid);
      await outbox.enqueue(TripUploader.kindSummary, payload(scored: true));
      expect(await outbox.drain(), 0);
      uid = 'me';
      expect(await outbox.drain(), 1);
      await outbox.enqueue(TripUploader.kindDelete, {'trip_id': 't1'});
      await outbox.drain();
      expect(cloud.summaries, isEmpty);
    }, skip: skip);
  });
}
