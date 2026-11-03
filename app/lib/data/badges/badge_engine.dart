import 'package:drivalry_scoring/drivalry_scoring.dart' show EventKind, Xp;
import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../models/trip_score_view.dart';

/// A scored trip with its parsed score, the unit every rule reads.
class ScoredTrip {
  ScoredTrip(this.trip, this.score);
  final Trip trip;
  final TripScoreView score;

  bool get clean => score.score >= Xp.cleanTripScore && !score.reckless;
  bool get phoneFree =>
      !score.events.any((e) => e.kind == EventKind.phoneHandling);
}

/// Streak lengths over the newest-first list: consecutive trips from the most
/// recent one that keep the condition. Shared by badges and the Drive card.
int streakLength(List<ScoredTrip> newestFirst, bool Function(ScoredTrip) keep) {
  var n = 0;
  for (final t in newestFirst) {
    if (!keep(t)) break;
    n++;
  }
  return n;
}

/// Parses score rows once per (tripId, scoredAt) so repeated evaluations over
/// the same trips do not re-decode JSON.
class ScoredTripParser {
  final Map<String, (int, ScoredTrip)> _cache = {};

  List<ScoredTrip> parse(List<TripWithScore> rows) {
    final out = <ScoredTrip>[];
    final seen = <String>{};
    for (final r in rows) {
      final s = r.score;
      if (s == null) continue;
      seen.add(r.trip.id);
      final hit = _cache[r.trip.id];
      if (hit != null && hit.$1 == s.scoredAt) {
        out.add(hit.$2);
        continue;
      }
      final parsed = ScoredTrip(
        r.trip,
        TripScoreView.fromJsonString(s.scoreJson),
      );
      _cache[r.trip.id] = (s.scoredAt, parsed);
      out.add(parsed);
    }
    _cache.removeWhere((k, _) => !seen.contains(k));
    return out;
  }
}

/// Decides which badges the local trips have earned (docs/01 §4.3). Every
/// rule is monotonic, so the whole set is re-evaluated over the scored trips
/// each time one lands; [AppDatabase.awardBadge] makes awards idempotent.
///
/// Never by speed, never by raw distance: states visited counts regions,
/// altitude counts a place, everything else counts clean trips.
class BadgeEngine {
  BadgeEngine(this.db, {this.onAwarded, int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;
  final int Function() _now;

  /// Called once per new award with the badge id.
  final Future<void> Function(String badgeId, int awardedAt)? onAwarded;

  final ScoredTripParser _parser = ScoredTripParser();

  static const _altitudeKey = 'badges:altitude_checked_until';
  static const double highAltitudeM = 2500;

  /// Evaluates the trip rules over [rows] (newest first, driver trips only).
  /// Returns the ids newly awarded in this pass.
  Future<List<String>> evaluate(List<TripWithScore> rows) async {
    final trips = _parser.parse(rows);
    final earned = <String>{};
    if (trips.isNotEmpty) earned.add('first_trip');

    final clean = streakLength(trips, (t) => t.clean);
    if (clean >= 5) earned.add('clean_5');
    if (clean >= 20) earned.add('clean_20');
    if (streakLength(trips, (t) => t.phoneFree) >= 10) {
      earned.add('phone_free_10');
    }
    if (trips.any((t) => t.score.score >= 100)) earned.add('perfect_100');

    final nightGood = trips
        .where((t) => (t.trip.nightFraction ?? 0) >= 0.5 && t.score.score >= 85)
        .length;
    if (nightGood >= 10) earned.add('night_owl');

    final wetGood = trips
        .where(
          (t) =>
              (t.trip.weather == 'rain' || t.trip.weather == 'snow') &&
              t.score.score >= 85,
        )
        .length;
    if (wetGood >= 5) earned.add('rain_or_shine');

    final regions = {
      for (final t in trips)
        if (t.trip.packRegion != null && t.trip.packRegion!.isNotEmpty)
          t.trip.packRegion!,
    };
    if (regions.length >= 3) earned.add('three_states');
    if (regions.length >= 10) earned.add('ten_states');

    if (await _reachedHighAltitude(trips)) earned.add('high_altitude');

    final awarded = <String>[];
    for (final id in earned) {
      if (await award(id)) awarded.add(id);
    }
    return awarded;
  }

  /// Awards one badge if it is new. Used by the trip rules and by features
  /// that know about events this engine cannot see (friends, leagues).
  Future<bool> award(String badgeId) async {
    final awardedAt = _now();
    final isNew = await db.awardBadge(badgeId, awardedAt);
    if (isNew) {
      debugPrint('badge awarded: $badgeId');
      await onAwarded?.call(badgeId, awardedAt);
    }
    return isNew;
  }

  /// Checks samples only for trips newer than the last check, so the altitude
  /// rule costs one query per new trip, not one per evaluation.
  Future<bool> _reachedHighAltitude(List<ScoredTrip> newestFirst) async {
    final checkedUntil = int.tryParse(await db.getSetting(_altitudeKey) ?? '');
    var found = false;
    var newest = checkedUntil ?? 0;
    for (final t in newestFirst) {
      if (checkedUntil != null && t.trip.startedAt <= checkedUntil) break;
      if (t.trip.startedAt > newest) newest = t.trip.startedAt;
      if (found) continue;
      final samples = await db.samplesFor(t.trip.id);
      found = samples.any((s) => (s.altitude ?? 0) > highAltitudeM);
    }
    if (newest != (checkedUntil ?? 0)) {
      await db.setSetting(_altitudeKey, newest.toString());
    }
    return found;
  }
}
