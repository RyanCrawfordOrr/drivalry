import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/data/models/trip_score_view.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/data/sync/trip_upload.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' as scoring;
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

Future<Trip> insertScoredTrip(
  AppDatabase db,
  String id,
  scoring.TripScore score, {
  bool? passenger,
  String? region = 'us-dc',
}) async {
  final view = TripScoreView.fromScore(score);
  await db.ensureTrip(
    TripsCompanion.insert(
      id: id,
      startedAt: score.summary.startT,
      endedAt: Value(score.summary.endT),
      phase: score.scored ? TripPhase.scored.wire : TripPhase.unscored.wire,
      createdAt: score.summary.startT,
      distanceM: Value(score.summary.distanceM),
      movingS: Value(score.summary.movingTimeS),
      isPassenger: Value(passenger),
      packRegion: Value(region),
      packVersion: const Value('2026-10-31T00:00:00Z'),
      limitCoverage: const Value(0.9),
      nightFraction: const Value(0.0),
      weather: const Value('clear'),
    ),
  );
  await db.upsertScore(
    TripScoresCompanion.insert(
      tripId: id,
      scoreJson: jsonEncode(score.toJson()),
      score: Value(score.scored ? score.score : null),
      xp: score.xp,
      reckless: score.reckless,
      scored: score.scored,
      roastText: Value(view.roastText),
      scoredAt: score.summary.endT,
    ),
  );
  return (await db.tripById(id))!;
}

void main() {
  final skip = skipWithoutSqlite();
  final messy = scoring.scoreTrip(scoring.messyCommute());
  final clean = scoring.scoreTrip(scoring.cleanCommute());

  group('TripSummaryPayload', () {
    test('maps a scored trip field by field, with no coordinates', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final trip = await insertScoredTrip(db, 'messy', messy);
      final view = TripScoreView.fromScore(messy);
      final p = TripSummaryPayload.build(trip, view);
      final s = p.summary;

      expect(s['id'], 'messy');
      expect(s['started_at'], isA<String>());
      expect(
        DateTime.parse(s['started_at'] as String).millisecondsSinceEpoch,
        messy.summary.startT,
      );
      expect(s['distance_m'], messy.summary.distanceM.round());
      expect(s['moving_s'], messy.summary.movingTimeS.round());
      expect(s['scored'], isTrue);
      expect(s['score'], messy.score);
      expect(s['xp'], messy.xp);
      expect(s['reckless'], messy.reckless);
      expect(s['is_passenger'], isFalse);
      expect(s['pack_region'], 'us-dc');
      expect(s['limit_coverage'], 0.9);
      expect(s['weather'], 'clear');
      final components = s['components'] as Map;
      expect(
        components.keys,
        containsAll(['speed', 'smoothness', 'attention', 'efficiency']),
      );
      expect(components['speed'], closeTo(messy.penalties.speed, 0.01));
      expect(s['credited_km'], closeTo(messy.summary.distanceM / 1000, 0.01));
      final roast = s['roast'] as Map?;
      expect(roast, isNotNull);
      expect(roast!['text'], view.roastText);

      expect(p.events.length, messy.events.length);
      expect(p.events, isNotEmpty);
      for (final e in p.events) {
        expect(e.keys, isNot(contains('lat')));
        expect(e.keys, isNot(contains('lon')));
        expect(e['offset_s'], greaterThanOrEqualTo(0));
      }
      final speeding = p.events.where((e) => e['kind'] == 'speeding');
      expect(speeding, isNotEmpty);
      expect(speeding.first['over_mps'], isA<double>());
      expect(jsonEncode(p.toJson()), isNot(contains('"lat"')));
    }, skip: skip);

    test('a passenger trip uploads as unscored with no events', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final trip = await insertScoredTrip(db, 'pax', messy, passenger: true);
      final p = TripSummaryPayload.build(trip, TripScoreView.fromScore(messy));
      expect(p.summary['scored'], isFalse);
      expect(p.summary['is_passenger'], isTrue);
      expect(p.summary['unscored_reason'], 'passenger');
      expect(p.summary['xp'], 0);
      expect(p.summary['score'], isNull);
      expect(p.events, isEmpty);
    }, skip: skip);

    test('hash is stable and changes with the score', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final trip = await insertScoredTrip(db, 'h', messy);
      final a = TripSummaryPayload.build(trip, TripScoreView.fromScore(messy));
      final b = TripSummaryPayload.build(trip, TripScoreView.fromScore(messy));
      final c = TripSummaryPayload.build(trip, TripScoreView.fromScore(clean));
      expect(a.hash, b.hash);
      expect(a.hash, isNot(c.hash));
      expect(a.hash.length, 64);
    }, skip: skip);

    test('post ids are deterministic per trip', () {
      expect(TripSummaryPayload.postId('t1'), TripSummaryPayload.postId('t1'));
      expect(
        TripSummaryPayload.postId('t1'),
        isNot(TripSummaryPayload.postId('t2')),
      );
      expect(
        TripSummaryPayload.shamePostId('t1'),
        isNot(TripSummaryPayload.postId('t1')),
      );
    });
  });

  group('TripUploader', () {
    test('enqueues once per hash and again after a re-score', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      var now = 1_000_000;
      final outbox = OutboxWorker(db, now: () => now);
      addTearDown(outbox.dispose);
      final sent = <Map<String, dynamic>>[];
      outbox.register(TripUploader.kindSummary, (p) async {
        sent.add(p);
        await db.markUploaded(p['trip_id'] as String, p['hash'] as String, now);
      });
      final uploader = TripUploader(db, outbox, now: () => now);

      await insertScoredTrip(db, 't1', messy);
      expect(await uploader.sweep(), 1);
      expect(
        await uploader.sweep(),
        1,
        reason: 'same id, ignored by the outbox',
      );
      await outbox.drain();
      expect(sent.length, 1);
      expect(sent.single['summary']['id'], 't1');

      // Nothing changed: no new row.
      expect(await uploader.sweep(), 0);
      await outbox.drain();
      expect(sent.length, 1);

      // Re-scored (different engine output): uploaded again.
      await db.upsertScore(
        TripScoresCompanion.insert(
          tripId: 't1',
          scoreJson: jsonEncode(clean.toJson()),
          score: Value(clean.score),
          xp: clean.xp,
          reckless: clean.reckless,
          scored: clean.scored,
          roastText: const Value(null),
          scoredAt: ++now,
        ),
      );
      expect(await uploader.sweep(), 1);
      await outbox.drain();
      expect(sent.length, 2);
      expect(sent.last['summary']['score'], clean.score);
    }, skip: skip);

    test('an uploaded, unchanged trip is not even re-hashed', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      // The clock is later than the trip, so uploadedAt > scoredAt.
      final now = messy.summary.endT + 60_000;
      final outbox = OutboxWorker(db, now: () => now);
      addTearDown(outbox.dispose);
      outbox.register(TripUploader.kindSummary, (p) async {
        await db.markUploaded(p['trip_id'] as String, p['hash'] as String, now);
      });
      final uploader = TripUploader(db, outbox, now: () => now);
      await insertScoredTrip(db, 'u1', messy);

      expect(await uploader.sweep(), 1);
      expect(uploader.hashesComputed, 1);
      await outbox.drain();

      expect(
        await db.watchUploadCandidates().first,
        isEmpty,
        reason: 'filtered out in SQL once uploaded',
      );
      expect(await uploader.sweep(), 0);
      expect(uploader.hashesComputed, 1, reason: 'no hashing for a clean trip');

      // A later re-score makes it a candidate again.
      await db.upsertScore(
        TripScoresCompanion.insert(
          tripId: 'u1',
          scoreJson: jsonEncode(clean.toJson()),
          score: Value(clean.score),
          xp: clean.xp,
          reckless: clean.reckless,
          scored: clean.scored,
          roastText: const Value(null),
          scoredAt: now + 1,
        ),
      );
      expect(await uploader.sweep(), 1);
      expect(uploader.hashesComputed, 2);
    }, skip: skip);

    test('a deleted uploaded trip enqueues a cloud delete once', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final outbox = OutboxWorker(db, now: () => 5);
      addTearDown(outbox.dispose);
      final deleted = <String>[];
      outbox.register(TripUploader.kindDelete, (p) async {
        deleted.add(p['trip_id'] as String);
      });
      final uploader = TripUploader(db, outbox, now: () => 5);
      await insertScoredTrip(db, 'd1', messy);
      await db.markUploaded('d1', 'hash', 5);
      uploader.start();
      await db.softDeleteTrip('d1', 6);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await outbox.drain();
      await uploader.stop();
      expect(deleted, ['d1']);
      expect(await db.uploadedTrip('d1'), isNull);
    }, skip: skip);
  });
}
