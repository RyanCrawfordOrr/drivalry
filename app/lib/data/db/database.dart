import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' as scoring;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trip_phase.dart';
import 'tables.dart';

part 'database.g.dart';

/// Ninety days, the raw-sample retention promised in docs/05.
const Duration sampleRetention = Duration(days: 90);

/// A trip row joined with its score row, when one exists.
class TripWithScore {
  const TripWithScore(this.trip, this.score);
  final Trip trip;
  final TripScoreRow? score;
}

/// The phone's source of truth (docs/03 §7). Pure data access; the rules live
/// in `lib/tracking/`.
@DriftDatabase(
  tables: [
    Trips,
    Samples,
    MotionPeaks,
    PhoneEvents,
    Segments,
    TripScores,
    Packs,
    LimitFlags,
    Settings,
    FixBatches,
    Outbox,
    RemoteCache,
    UploadedTrips,
    BadgeAwards,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// The on-device database file, managed by drift_flutter.
  AppDatabase.open() : super(driftDatabase(name: 'drivalry'));

  /// In-memory database for tests and the simulator.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(outbox);
        await m.createTable(remoteCache);
        await m.createTable(uploadedTrips);
        await m.createTable(badgeAwards);
      }
    },
  );

  // ---------------------------------------------------------------- trips --

  Future<Trip?> tripById(String id) =>
      (select(trips)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Trip?> watchTrip(String id) =>
      (select(trips)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// Inserts the row if it is new; otherwise leaves it alone.
  Future<void> ensureTrip(TripsCompanion row) =>
      into(trips).insert(row, mode: InsertMode.insertOrIgnore);

  Future<void> updateTrip(String id, TripsCompanion changes) =>
      (update(trips)..where((t) => t.id.equals(id))).write(changes);

  Future<void> setPhase(String id, TripPhase phase) =>
      updateTrip(id, TripsCompanion(phase: Value(phase.wire)));

  /// Trips the user can see, newest first, with their scores.
  Stream<List<TripWithScore>> watchRecentTrips({int limit = 50}) {
    final query =
        select(trips).join([
            leftOuterJoin(tripScores, tripScores.tripId.equalsExp(trips.id)),
          ])
          ..where(
            trips.deletedAt.isNull() &
                trips.phase.isNotValue(TripPhase.discarded.wire),
          )
          ..orderBy([OrderingTerm.desc(trips.startedAt)])
          ..limit(limit);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          TripWithScore(r.readTable(trips), r.readTableOrNull(tripScores)),
      ],
    );
  }

  Future<List<Trip>> tripsInPhase(TripPhase phase) => (select(
    trips,
  )..where((t) => t.phase.equals(phase.wire) & t.deletedAt.isNull())).get();

  /// Trips whose passenger question has not been answered yet, newest first.
  /// Only trips the answer can change: scored ones and ones about to be
  /// scored. A trip that was too short to judge stays unscored either way,
  /// so it never asks.
  Stream<List<Trip>> watchUnansweredTrips() =>
      (select(trips)
            ..where(
              (t) =>
                  t.passengerAnswered.equals(false) &
                  t.deletedAt.isNull() &
                  t.phase.isIn([
                    TripPhase.scored.wire,
                    TripPhase.pendingPassenger.wire,
                  ]),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .watch();

  /// Removes a trip and everything attached to it. Used for discarded
  /// tentatives; user deletes are soft (see [softDeleteTrip]).
  Future<void> deleteTripHard(String id) => transaction(() async {
    await (delete(samples)..where((s) => s.tripId.equals(id))).go();
    await (delete(motionPeaks)..where((m) => m.tripId.equals(id))).go();
    await (delete(phoneEvents)..where((p) => p.tripId.equals(id))).go();
    await (delete(segments)..where((s) => s.tripId.equals(id))).go();
    await (delete(tripScores)..where((s) => s.tripId.equals(id))).go();
    await (delete(fixBatches)..where((b) => b.tripId.equals(id))).go();
    await (delete(trips)..where((t) => t.id.equals(id))).go();
  });

  Future<void> softDeleteTrip(String id, int nowMs) =>
      updateTrip(id, TripsCompanion(deletedAt: Value(nowMs)));

  // -------------------------------------------------------------- samples --

  Future<bool> hasFixBatch(String tripId, int batchT) async {
    final row =
        await (select(fixBatches)
              ..where((b) => b.tripId.equals(tripId) & b.batchT.equals(batchT)))
            .getSingleOrNull();
    return row != null;
  }

  /// Stores a batch of fixes once. Returns false when the batch was already
  /// known (replayed spool).
  Future<bool> insertFixBatch(
    String tripId,
    int batchT,
    List<SamplesCompanion> rows,
  ) => transaction(() async {
    if (await hasFixBatch(tripId, batchT)) return false;
    await into(
      fixBatches,
    ).insert(FixBatchesCompanion(tripId: Value(tripId), batchT: Value(batchT)));
    await batch(
      (b) => b.insertAll(samples, rows, mode: InsertMode.insertOrIgnore),
    );
    return true;
  });

  Future<List<Sample>> samplesFor(String tripId) =>
      (select(samples)
            ..where((s) => s.tripId.equals(tripId))
            ..orderBy([(s) => OrderingTerm.asc(s.t)]))
          .get();

  Future<int> sampleCount(String tripId) async {
    final count = samples.tripId.count();
    final row =
        await (selectOnly(samples)
              ..addColumns([count])
              ..where(samples.tripId.equals(tripId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> insertMotionPeaks(List<MotionPeaksCompanion> rows) => batch(
    (b) => b.insertAll(motionPeaks, rows, mode: InsertMode.insertOrIgnore),
  );

  Future<void> insertPhoneEvent(PhoneEventsCompanion row) =>
      into(phoneEvents).insert(row, mode: InsertMode.insertOrIgnore);

  /// Phone events of a trip within ±[windowMs] of [t].
  Future<List<PhoneEventRow>> phoneEventsNear(
    String tripId,
    int t,
    int windowMs,
  ) =>
      (select(phoneEvents)..where(
            (p) =>
                p.tripId.equals(tripId) &
                p.t.isBiggerOrEqualValue(t - windowMs) &
                p.t.isSmallerOrEqualValue(t + windowMs),
          ))
          .get();

  Future<void> deletePhoneEvent(String tripId, int t, String kind) =>
      (delete(phoneEvents)..where(
            (p) =>
                p.tripId.equals(tripId) & p.t.equals(t) & p.kind.equals(kind),
          ))
          .go();

  Future<List<PhoneEventRow>> phoneEventsFor(String tripId) =>
      (select(phoneEvents)
            ..where((p) => p.tripId.equals(tripId))
            ..orderBy([(p) => OrderingTerm.asc(p.t)]))
          .get();

  Future<List<MotionPeak>> motionPeaksFor(String tripId) =>
      (select(motionPeaks)
            ..where((p) => p.tripId.equals(tripId))
            ..orderBy([(p) => OrderingTerm.asc(p.t)]))
          .get();

  /// Drops raw fixes older than [sampleRetention] and finishes the purge of
  /// soft-deleted trips whose samples have aged out.
  Future<int> purgeOldSamples(int nowMs) async {
    final cutoff = nowMs - sampleRetention.inMilliseconds;
    final removed = await (delete(
      samples,
    )..where((s) => s.t.isSmallerThanValue(cutoff))).go();
    final stale =
        await (select(trips)..where(
              (t) =>
                  t.deletedAt.isNotNull() &
                  t.deletedAt.isSmallerThanValue(cutoff),
            ))
            .get();
    for (final t in stale) {
      await deleteTripHard(t.id);
    }
    return removed;
  }

  // ------------------------------------------------------------- segments --

  Future<void> replaceSegments(String tripId, List<scoring.RoadSegment> rows) =>
      transaction(() async {
        await (delete(segments)..where((s) => s.tripId.equals(tripId))).go();
        await batch(
          (b) => b.insertAll(segments, [
            for (final s in rows)
              SegmentsCompanion.insert(
                tripId: tripId,
                fromIdx: s.fromIdx,
                toIdx: s.toIdx,
                speedLimitMps: Value(s.speedLimit),
                confidence: s.confidence,
                roadClass: s.roadClass.wire,
                name: Value(s.name),
                wayId: Value(s.wayId),
              ),
          ]),
        );
      });

  Future<List<scoring.RoadSegment>> segmentsFor(String tripId) async {
    final rows =
        await (select(segments)
              ..where((s) => s.tripId.equals(tripId))
              ..orderBy([(s) => OrderingTerm.asc(s.fromIdx)]))
            .get();
    return [
      for (final r in rows)
        scoring.RoadSegment(
          fromIdx: r.fromIdx,
          toIdx: r.toIdx,
          speedLimit: r.speedLimitMps,
          confidence: r.confidence,
          roadClass: scoring.RoadClass.fromWire(r.roadClass),
          name: r.name,
          wayId: r.wayId,
        ),
    ];
  }

  // --------------------------------------------------------------- scores --

  Future<void> upsertScore(TripScoresCompanion row) =>
      into(tripScores).insertOnConflictUpdate(row);

  Future<TripScoreRow?> scoreFor(String tripId) => (select(
    tripScores,
  )..where((s) => s.tripId.equals(tripId))).getSingleOrNull();

  Stream<TripScoreRow?> watchScore(String tripId) => (select(
    tripScores,
  )..where((s) => s.tripId.equals(tripId))).watchSingleOrNull();

  /// Kilometres of scored driver trips that started in `[fromMs, toMs)`,
  /// excluding [exceptTripId]. Feeds the daily XP distance cap.
  Future<double> creditedKmBetween(
    int fromMs,
    int toMs, {
    String? exceptTripId,
  }) async {
    final rows =
        await (select(trips)..where(
              (t) =>
                  t.phase.equals(TripPhase.scored.wire) &
                  t.deletedAt.isNull() &
                  t.isPassenger.equals(false) &
                  t.startedAt.isBiggerOrEqualValue(fromMs) &
                  t.startedAt.isSmallerThanValue(toMs),
            ))
            .get();
    var km = 0.0;
    for (final t in rows) {
      if (t.id == exceptTripId) continue;
      km += t.distanceM / 1000;
    }
    return km;
  }

  /// Consecutive most-recent scored trips (before [beforeMs]) that kept the
  /// clean streak alive: score >= 80 and not reckless.
  Future<int> cleanStreakBefore(int beforeMs) async {
    final rows =
        await (select(trips).join([
                innerJoin(tripScores, tripScores.tripId.equalsExp(trips.id)),
              ])
              ..where(
                trips.deletedAt.isNull() &
                    trips.phase.equals(TripPhase.scored.wire) &
                    trips.startedAt.isSmallerThanValue(beforeMs),
              )
              ..orderBy([OrderingTerm.desc(trips.startedAt)])
              ..limit(100))
            .get();
    var streak = 0;
    for (final r in rows) {
      final s = r.readTable(tripScores);
      if (s.reckless || (s.score ?? 0) < scoring.Xp.cleanTripScore) break;
      streak++;
    }
    return streak;
  }

  // ---------------------------------------------------------------- packs --

  Future<List<Pack>> installedPacks() => select(packs).get();
  Stream<List<Pack>> watchInstalledPacks() => select(packs).watch();

  Future<Pack?> packByRegion(String region) =>
      (select(packs)..where((p) => p.region.equals(region))).getSingleOrNull();

  Future<void> upsertPack(PacksCompanion row) =>
      into(packs).insertOnConflictUpdate(row);

  Future<void> removePack(String region) =>
      (delete(packs)..where((p) => p.region.equals(region))).go();

  // ---------------------------------------------------------- limit flags --

  Future<void> addLimitFlag(LimitFlagsCompanion row) =>
      into(limitFlags).insert(row);

  Future<List<LimitFlag>> limitFlagsFor(String tripId) =>
      (select(limitFlags)..where((f) => f.tripId.equals(tripId))).get();

  // ------------------------------------------------------------- settings --

  Future<String?> getSetting(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchSetting(String key) => (select(
    settings,
  )..where((s) => s.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> setSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(
        SettingsCompanion(key: Value(key), value: Value(value)),
      );

  // --------------------------------------------------------------- outbox --

  /// Adds a pending cloud write. A row with the same id is replaced, so the
  /// newest intent for a stable id (a setting toggled twice) is what uploads.
  Future<void> enqueueOutbox(OutboxCompanion row) =>
      into(outbox).insertOnConflictUpdate(row);

  Future<List<OutboxData>> dueOutbox(int nowMs, {int limit = 50}) =>
      (select(outbox)
            ..where((o) => o.nextAttemptAt.isSmallerOrEqualValue(nowMs))
            ..orderBy([(o) => OrderingTerm.asc(o.createdAt)])
            ..limit(limit))
          .get();

  Future<void> deleteOutbox(String id) =>
      (delete(outbox)..where((o) => o.id.equals(id))).go();

  Future<void> failOutbox(
    String id, {
    required int attempts,
    required int nextAttemptAt,
    required String error,
  }) => (update(outbox)..where((o) => o.id.equals(id))).write(
    OutboxCompanion(
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      lastError: Value(error),
    ),
  );

  Stream<int> watchOutboxCount() {
    final c = outbox.id.count();
    return (selectOnly(
      outbox,
    )..addColumns([c])).watchSingle().map((r) => r.read(c) ?? 0);
  }

  // --------------------------------------------------------- remote cache --

  Future<String?> cacheGet(String key) async {
    final row = await (select(
      remoteCache,
    )..where((c) => c.key.equals(key))).getSingleOrNull();
    return row?.json;
  }

  Stream<String?> watchCache(String key) => (select(
    remoteCache,
  )..where((c) => c.key.equals(key))).watchSingleOrNull().map((r) => r?.json);

  Future<void> cachePut(String key, String json, int nowMs) =>
      into(remoteCache).insertOnConflictUpdate(
        RemoteCacheCompanion(
          key: Value(key),
          json: Value(json),
          updatedAt: Value(nowMs),
        ),
      );

  Future<void> cacheDeletePrefix(String prefix) =>
      (delete(remoteCache)..where((c) => c.key.like('$prefix%'))).go();

  Future<void> cacheClear() => delete(remoteCache).go();

  // ------------------------------------------------------- uploaded trips --

  Future<UploadedTrip?> uploadedTrip(String tripId) => (select(
    uploadedTrips,
  )..where((u) => u.tripId.equals(tripId))).getSingleOrNull();

  /// Upload records for several trips in one query.
  Future<List<UploadedTrip>> uploadedTripsByIds(List<String> tripIds) =>
      tripIds.isEmpty
      ? Future.value(const [])
      : (select(uploadedTrips)..where((u) => u.tripId.isIn(tripIds))).get();

  /// Forgets everything tied to the signed-in account so a different account
  /// on this phone uploads the trips and badges afresh: upload records,
  /// badge sync marks, the whole outbox, cached cloud reads, and the hidden-
  /// location mirror. Local trips and scores are untouched.
  Future<void> resetAccountState() => transaction(() async {
    await delete(uploadedTrips).go();
    await update(
      badgeAwards,
    ).write(const BadgeAwardsCompanion(synced: Value(false)));
    await delete(outbox).go();
    await delete(remoteCache).go();
    await (delete(
      settings,
    )..where((s) => s.key.equals('location_hidden'))).go();
  });

  Future<void> markUploaded(String tripId, String summaryHash, int nowMs) =>
      into(uploadedTrips).insertOnConflictUpdate(
        UploadedTripsCompanion(
          tripId: Value(tripId),
          uploadedAt: Value(nowMs),
          summaryHash: Value(summaryHash),
        ),
      );

  // --------------------------------------------------------------- badges --

  Future<List<BadgeAward>> allBadgeAwards() => select(badgeAwards).get();
  Stream<List<BadgeAward>> watchAllBadgeAwards() => select(badgeAwards).watch();

  Future<BadgeAward?> badgeAward(String badgeId) => (select(
    badgeAwards,
  )..where((b) => b.badgeId.equals(badgeId))).getSingleOrNull();

  /// Records an award once. Returns true when it was new.
  Future<bool> awardBadge(String badgeId, int nowMs) async {
    final existing = await (select(
      badgeAwards,
    )..where((b) => b.badgeId.equals(badgeId))).getSingleOrNull();
    if (existing != null) return false;
    await into(badgeAwards).insert(
      BadgeAwardsCompanion(badgeId: Value(badgeId), awardedAt: Value(nowMs)),
      mode: InsertMode.insertOrIgnore,
    );
    return true;
  }

  Future<void> markBadgeSynced(String badgeId) =>
      (update(badgeAwards)..where((b) => b.badgeId.equals(badgeId))).write(
        const BadgeAwardsCompanion(synced: Value(true)),
      );

  // ------------------------------------------------- sync (stage 2, part A) --

  /// Trips that have a score row and may need uploading: scored or unscored
  /// (passenger), not deleted, not discarded, and either never uploaded or
  /// scored again since the last upload. The uploader hashes only these and
  /// compares with [uploadedTrips], so an unchanged trip costs nothing.
  Stream<List<TripWithScore>> watchUploadCandidates() {
    final query =
        select(trips).join([
            innerJoin(tripScores, tripScores.tripId.equalsExp(trips.id)),
            leftOuterJoin(
              uploadedTrips,
              uploadedTrips.tripId.equalsExp(trips.id),
            ),
          ])
          ..where(
            trips.deletedAt.isNull() &
                trips.phase.isIn([
                  TripPhase.scored.wire,
                  TripPhase.unscored.wire,
                ]) &
                (uploadedTrips.tripId.isNull() |
                    tripScores.scoredAt.isBiggerThan(uploadedTrips.uploadedAt)),
          )
          ..orderBy([OrderingTerm.desc(trips.startedAt)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          TripWithScore(r.readTable(trips), r.readTable(tripScores)),
      ],
    );
  }

  /// Soft-deleted trips that were uploaded and still need a cloud delete.
  Stream<List<UploadedTrip>> watchUploadedDeletedTrips() {
    final query = select(uploadedTrips).join([
      innerJoin(trips, trips.id.equalsExp(uploadedTrips.tripId)),
    ])..where(trips.deletedAt.isNotNull());
    return query.watch().map(
      (rows) => [for (final r in rows) r.readTable(uploadedTrips)],
    );
  }

  Future<void> removeUploaded(String tripId) =>
      (delete(uploadedTrips)..where((u) => u.tripId.equals(tripId))).go();

  Stream<List<LimitFlag>> watchUnsyncedLimitFlags() =>
      (select(limitFlags)..where((f) => f.synced.equals(false))).watch();

  Future<void> markLimitFlagSynced(int id) =>
      (update(limitFlags)..where((f) => f.id.equals(id))).write(
        const LimitFlagsCompanion(synced: Value(true)),
      );

  // ---------------------------------------------------------- diagnostics --

  Future<Map<String, int>> tableCounts() async {
    Future<int> count(TableInfo table) async {
      final row = await customSelect(
        'SELECT COUNT(*) AS c FROM ${table.actualTableName}',
      ).getSingle();
      return row.read<int>('c');
    }

    return {
      'trips': await count(trips),
      'samples': await count(samples),
      'motionPeaks': await count(motionPeaks),
      'phoneEvents': await count(phoneEvents),
      'segments': await count(segments),
      'tripScores': await count(tripScores),
      'packs': await count(packs),
      'limitFlags': await count(limitFlags),
      'outbox': await count(outbox),
      'remoteCache': await count(remoteCache),
      'uploadedTrips': await count(uploadedTrips),
      'badgeAwards': await count(badgeAwards),
    };
  }

  // ----------------------------------------- stage 2 (badges, streaks) --

  /// Scored driver trips with their scores, newest first. Badges and streaks
  /// evaluate over this list; it stays small (a few hundred rows at most).
  Future<List<TripWithScore>> scoredTripsWithScores({int limit = 1000}) =>
      _scoredTripsQuery(limit).get().then(_rowsToTripsWithScores);

  Stream<List<TripWithScore>> watchScoredTripsWithScores({int limit = 1000}) =>
      _scoredTripsQuery(limit).watch().map(_rowsToTripsWithScores);

  JoinedSelectStatement<HasResultSet, dynamic> _scoredTripsQuery(int limit) =>
      select(
          trips,
        ).join([innerJoin(tripScores, tripScores.tripId.equalsExp(trips.id))])
        ..where(
          trips.deletedAt.isNull() &
              trips.phase.equals(TripPhase.scored.wire) &
              (trips.isPassenger.isNull() | trips.isPassenger.equals(false)),
        )
        ..orderBy([OrderingTerm.desc(trips.startedAt)])
        ..limit(limit);

  List<TripWithScore> _rowsToTripsWithScores(List<TypedResult> rows) => [
    for (final r in rows)
      TripWithScore(r.readTable(trips), r.readTable(tripScores)),
  ];
}

/// The app's database. Overridden in tests with [AppDatabase.memory].
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});
