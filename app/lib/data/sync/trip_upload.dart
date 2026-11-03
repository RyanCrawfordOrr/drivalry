import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/trip_score_view.dart';
import '../supabase/supabase_providers.dart';
import 'outbox.dart';

/// The cloud shape of one trip (docs/03 §3.6). No coordinates, no route, no
/// places: road names on events are the only geography that leaves the phone.
class TripSummaryPayload {
  const TripSummaryPayload._(this.summary, this.events);

  /// The `trip_summaries` row without `user_id` (filled at send time).
  final Map<String, Object?> summary;

  /// `trip_events` rows without `trip_id`.
  final List<Map<String, Object?>> events;

  static const Uuid _uuid = Uuid();

  /// Daily distance credit cap, mirrored from the engine (docs/02 §5).
  static const double dailyCreditedKmCap = 100;

  static TripSummaryPayload build(Trip trip, TripScoreView score) {
    final startedAt = trip.startedAt;
    final endedAt = trip.endedAt ?? score.summary.endT;
    final passenger = trip.isPassenger ?? false;
    final scored = score.scored && !passenger;
    final distanceKm = score.summary.distanceM / 1000;
    final headline = score.raw['feedback'] is Map
        ? (score.raw['feedback'] as Map)['headline']
        : null;

    final summary = <String, Object?>{
      'id': trip.id,
      'started_at': _iso(startedAt),
      'ended_at': _iso(endedAt < startedAt ? startedAt : endedAt),
      'distance_m': score.summary.distanceM.round(),
      'moving_s': score.summary.movingTimeS.round(),
      'scored': scored,
      'unscored_reason': scored
          ? null
          : (passenger ? 'passenger' : score.unscoredReason),
      'score': scored ? score.score : null,
      'components': scored
          ? {
              'speed': _r2(score.penalties.speed),
              'smoothness': _r2(score.penalties.smoothness),
              'attention': _r2(score.penalties.attention),
              'efficiency': _r2(score.penalties.efficiency),
            }
          : null,
      'reckless': scored && score.reckless,
      'xp': scored ? score.xp : 0,
      'credited_km': scored
          ? _r2(distanceKm.clamp(0, dailyCreditedKmCap).toDouble())
          : 0,
      'is_passenger': passenger,
      'vehicle_label': trip.vehicleLabel,
      'pack_region': trip.packRegion,
      'pack_version': trip.packVersion,
      'limit_coverage': trip.limitCoverage,
      'night_fraction': trip.nightFraction,
      'weather': trip.weather,
      'roast': scored && headline is Map
          ? Map<String, Object?>.from(headline)
          : null,
    };

    final events = <Map<String, Object?>>[
      if (scored)
        for (final e in score.events)
          {
            'kind': e.kind.wire,
            'severity': e.severity.wire,
            'offset_s': ((e.startT - startedAt) / 1000).round().clamp(
              0,
              1 << 30,
            ),
            'duration_s': e.durationS.round(),
            'over_mps': e.kind.wire == 'speeding'
                ? (e.detail['maxOver'] as num?)?.toDouble()
                : null,
            'road_name': e.roadName,
            'way_id': int.tryParse(e.wayId ?? ''),
          },
    ];
    return TripSummaryPayload._(summary, events);
  }

  /// Stable hash of what would be sent; a re-score changes it.
  String get hash =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  Map<String, Object?> toJson() => {'summary': summary, 'events': events};

  /// Deterministic post ids so retries never duplicate a post.
  static String postId(String tripId) =>
      _uuid.v5(Namespace.url.value, 'drivalry:post:$tripId');
  static String shamePostId(String tripId) =>
      _uuid.v5(Namespace.url.value, 'drivalry:post:$tripId:shame');

  static String _iso(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();

  static double _r2(double v) => (v * 100).round() / 100;
}

/// The cloud writes the uploader performs, behind an interface so the handler
/// logic (posts created, replaced and removed) is testable without Supabase.
abstract class TripCloud {
  Future<void> upsertSummary(Map<String, Object?> row);
  Future<void> replaceEvents(String tripId, List<Map<String, Object?>> rows);
  Future<void> upsertPost(Map<String, Object?> row);
  Future<void> deletePosts(List<String> ids);
  Future<void> deleteSummary(String tripId);
}

/// PostgREST implementation. RLS makes every call the signed-in user's own.
class SupabaseTripCloud implements TripCloud {
  SupabaseTripCloud(this._c);
  final SupabaseClient _c;

  @override
  Future<void> upsertSummary(Map<String, Object?> row) =>
      _c.from('trip_summaries').upsert(row, onConflict: 'id');

  @override
  Future<void> replaceEvents(
    String tripId,
    List<Map<String, Object?>> rows,
  ) async {
    await _c.from('trip_events').delete().eq('trip_id', tripId);
    if (rows.isNotEmpty) await _c.from('trip_events').insert(rows);
  }

  @override
  Future<void> upsertPost(Map<String, Object?> row) => _c
      .from('feed_posts')
      .upsert(row, onConflict: 'id', ignoreDuplicates: true);

  @override
  Future<void> deletePosts(List<String> ids) =>
      _c.from('feed_posts').delete().inFilter('id', ids);

  @override
  Future<void> deleteSummary(String tripId) =>
      _c.from('trip_summaries').delete().eq('id', tripId);
}

/// Watches the local database and queues uploads and deletes through the
/// outbox (docs/03 §7). One row per (trip, hash), so an unchanged trip is
/// never re-sent and a re-scored one is.
class TripUploader {
  TripUploader(this._db, this._outbox, {int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final OutboxWorker _outbox;
  final int Function() _now;
  StreamSubscription<List<TripWithScore>>? _trips;
  StreamSubscription<List<UploadedTrip>>? _deletes;

  /// How many payload hashes were computed so far (tests check that an
  /// unchanged trip is never re-hashed).
  @visibleForTesting
  int hashesComputed = 0;

  /// Outbox kinds and payloads (B and C: do not reuse these names).
  /// `trip_summary`: `{trip_id, hash, summary: {...}, events: [...]}`.
  /// `trip_delete`: `{trip_id}`.
  static const String kindSummary = 'trip_summary';
  static const String kindDelete = 'trip_delete';

  void start() {
    _trips ??= _db.watchUploadCandidates().listen(_onCandidates);
    _deletes ??= _db.watchUploadedDeletedTrips().listen(_onDeleted);
  }

  Future<void> stop() async {
    await _trips?.cancel();
    await _deletes?.cancel();
    _trips = null;
    _deletes = null;
  }

  /// One pass over the current candidates (also used by tests).
  Future<int> sweep() async {
    final rows = await _db.watchUploadCandidates().first;
    return _onCandidates(rows);
  }

  Future<int> _onCandidates(List<TripWithScore> rows) async {
    if (rows.isEmpty) return 0;
    final uploaded = {
      for (final u in await _db.uploadedTripsByIds([
        for (final r in rows) r.trip.id,
      ]))
        u.tripId: u,
    };
    var queued = 0;
    for (final r in rows) {
      final score = r.score;
      if (score == null) continue;
      try {
        final payload = TripSummaryPayload.build(
          r.trip,
          TripScoreView.fromJsonString(score.scoreJson),
        );
        final hash = payload.hash;
        hashesComputed++;
        if (uploaded[r.trip.id]?.summaryHash == hash) continue;
        await _outbox.enqueue(kindSummary, {
          'trip_id': r.trip.id,
          'hash': hash,
          ...payload.toJson(),
        }, id: '$kindSummary:${r.trip.id}:$hash');
        queued++;
      } catch (e) {
        debugPrint('TripUploader: could not build ${r.trip.id}: $e');
      }
    }
    return queued;
  }

  Future<void> _onDeleted(List<UploadedTrip> rows) async {
    for (final u in rows) {
      await _outbox.enqueue(kindDelete, {
        'trip_id': u.tripId,
      }, id: '$kindDelete:${u.tripId}');
      await _db.removeUploaded(u.tripId);
    }
  }

  /// Registers the two handlers on the outbox. [client] may be null for an
  /// offline build, in which case every row waits.
  void registerHandlers(SupabaseClient? client) => registerCloudHandlers(
    client == null ? null : SupabaseTripCloud(client),
    () => client?.auth.currentUser?.id,
  );

  /// Same as [registerHandlers] with the cloud and the identity injectable.
  void registerCloudHandlers(TripCloud? cloud, String? Function() userId) {
    _outbox.register(kindSummary, (p) async {
      final uid = userId();
      if (cloud == null || uid == null) {
        throw const OutboxRetryLater('signed out');
      }
      final tripId = p['trip_id'] as String;
      final hash = p['hash'] as String;
      final summary = Map<String, Object?>.from(p['summary'] as Map)
        ..['user_id'] = uid;
      final events = [
        for (final e in (p['events'] as List? ?? const []))
          Map<String, Object?>.from(e as Map)..['trip_id'] = tripId,
      ];

      await cloud.upsertSummary(summary);
      await cloud.replaceEvents(tripId, events);

      final scored = summary['scored'] == true;
      final passenger = summary['is_passenger'] == true;
      final reckless = summary['reckless'] == true;
      final postId = TripSummaryPayload.postId(tripId);
      final shameId = TripSummaryPayload.shamePostId(tripId);
      // Posts from an earlier upload of this trip may need to go: a trip
      // re-marked as a passenger ride loses its roast, a trip re-scored out
      // of reckless loses its Wall of Shame entry. The first upload has
      // nothing to clean up.
      final uploadedBefore = await _db.uploadedTrip(tripId) != null;

      if (scored && !passenger) {
        final roast = summary['roast'];
        final body = {
          'score': summary['score'],
          'xp': summary['xp'],
          'reckless': reckless,
          'roast': roast is Map ? roast['text'] : null,
          'tone': roast is Map ? roast['tone'] : null,
          // Read by the feed: components render as bars, speeding enables the
          // Snitch reaction.
          'components': summary['components'],
          'speeding': events.any((e) => e['kind'] == 'speeding'),
        };
        Map<String, Object?> post(String id, String kind) => {
          'id': id,
          'author_id': uid,
          'kind': kind,
          'trip_id': tripId,
          'body': body,
          'created_at': summary['ended_at'],
        };
        await cloud.upsertPost(post(postId, 'trip'));
        if (reckless) {
          await cloud.upsertPost(post(shameId, 'shame'));
        } else if (uploadedBefore) {
          await cloud.deletePosts([shameId]);
        }
      } else if (uploadedBefore) {
        await cloud.deletePosts([postId, shameId]);
      }
      await _db.markUploaded(tripId, hash, _now());
    });

    _outbox.register(kindDelete, (p) async {
      final uid = userId();
      if (cloud == null || uid == null) {
        throw const OutboxRetryLater('signed out');
      }
      await cloud.deleteSummary(p['trip_id'] as String);
    });
  }
}

final tripUploaderProvider = Provider<TripUploader>((ref) {
  final uploader = TripUploader(
    ref.watch(databaseProvider),
    ref.watch(outboxWorkerProvider),
  );
  uploader.registerHandlers(ref.watch(supabaseProvider));
  ref.onDispose(uploader.stop);
  return uploader;
});
