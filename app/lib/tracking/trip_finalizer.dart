import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drivalry_packs/drivalry_packs.dart' show LimitOverride;
import 'package:drivalry_scoring/drivalry_scoring.dart' as scoring;
import 'package:flutter/foundation.dart';

import '../data/db/database.dart';
import '../data/db/pack_bounds.dart';
import '../data/models/trip_phase.dart';
import '../data/models/trip_score_view.dart';
import '../widgets/units.dart';
import 'match_runner.dart';
import 'solar.dart';
import 'weather.dart';

/// What [TripFinalizer.finalize] produced.
class FinalizeResult {
  const FinalizeResult({required this.trip, required this.score});

  final Trip trip;

  /// Null when the trip had too few samples to run the engine at all.
  final TripScoreView? score;
}

/// Match → score → store, for a trip that has stopped recording
/// (docs/03 §3.4–3.5, docs/08 §7).
///
/// Everything happens on the phone. The only network call is the optional
/// weather lookup, which can fail silently.
class TripFinalizer {
  TripFinalizer(
    this._db, {
    MatchRunner? matcher,
    this.weather = const NoWeather(),
    int Function()? now,
  }) : _matcher = matcher ?? const IsolateMatchRunner(),
       _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final MatchRunner _matcher;

  /// Weather lookup; [NoWeather] when offline or in tests.
  final WeatherClient weather;
  final int Function() _now;

  /// Minimum samples for the engine to have anything to say.
  static const int minSamples = 2;

  /// Finalises [tripId]. [isPassenger] overrides the stored answer; when it
  /// is null the stored answer, then the native hint, is used.
  /// [markAnswered] records that the user has confirmed the passenger
  /// question, which removes the interstitial.
  Future<FinalizeResult?> finalize(
    String tripId, {
    bool? isPassenger,
    bool markAnswered = false,
  }) async {
    final trip = await _db.tripById(tripId);
    if (trip == null || trip.deletedAt != null) return null;

    final rows = await _db.samplesFor(tripId);
    final samples = toGpsSamples(rows);
    final passenger = isPassenger ?? trip.isPassenger ?? trip.passengerHint;

    if (samples.length < minSamples) {
      await _db.updateTrip(
        tripId,
        TripsCompanion(
          phase: Value(TripPhase.unscored.wire),
          isPassenger: Value(passenger),
          passengerAnswered: markAnswered
              ? const Value(true)
              : const Value.absent(),
        ),
      );
      return FinalizeResult(trip: (await _db.tripById(tripId))!, score: null);
    }

    // 1. Match against the installed pack covering the trip.
    final pack = await _packFor(samples);
    MatchOutcome match;
    if (pack == null) {
      match = MatchOutcome(
        segments: [
          scoring.RoadSegment(
            fromIdx: 0,
            toIdx: samples.length - 1,
            speedLimit: null,
            confidence: 0,
            roadClass: scoring.RoadClass.unknown,
          ),
        ],
        limitCoverage: 0,
        matchedFraction: 0,
      );
    } else {
      final overrides = await _pendingFlagOverrides(pack.region);
      match = await _matcher.run(samples, pack, overrides: overrides);
    }
    await _db.replaceSegments(tripId, match.segments);

    // 2. Context.
    final first = samples.first;
    final nightFraction = Solar.nightFraction(samples);
    final weather = await this.weather.weatherAt(
      first.lat,
      first.lon,
      DateTime.fromMillisecondsSinceEpoch(first.t, isUtc: true),
    );
    final startLocal = DateTime.fromMillisecondsSinceEpoch(first.t);
    final dayStart = DateTime(
      startLocal.year,
      startLocal.month,
      startLocal.day,
    ).millisecondsSinceEpoch;
    final creditedBefore = await _db.creditedKmBetween(
      dayStart,
      first.t,
      exceptTripId: tripId,
    );
    final streak = await _db.cleanStreakBefore(first.t);
    final phone = [
      for (final p in await _db.phoneEventsFor(tripId))
        scoring.PhoneEvent(
          t: p.t,
          kind: scoring.PhoneEventKind.fromWire(p.kind),
        ),
    ];

    final input = scoring.TripInput(
      id: tripId,
      samples: samples,
      segments: match.segments,
      phoneEvents: phone,
      context: scoring.TripContext(
        nightFraction: nightFraction,
        weather: weather,
        vehicleId: trip.vehicleLabel,
        isPassenger: passenger,
        dailyCreditedKmBefore: creditedBefore,
        cleanStreak: streak,
      ),
    );

    // 3. Score.
    final unitsSetting = UnitsSetting.fromWire(await _db.getSetting('units'));
    final units = resolveUnits(unitsSetting, packRegion: pack?.region);
    final score = scoring.scoreTrip(input, scoring.ScoreOptions(units: units));
    final view = TripScoreView.fromScore(score);

    // 4. Store.
    await _db.upsertScore(
      TripScoresCompanion.insert(
        tripId: tripId,
        scoreJson: jsonEncode(score.toJson()),
        score: Value(score.scored ? score.score : null),
        xp: score.xp,
        reckless: score.reckless,
        scored: score.scored,
        roastText: Value(view.roastText),
        scoredAt: _now(),
      ),
    );
    await _db.updateTrip(
      tripId,
      TripsCompanion(
        phase: Value(
          score.scored ? TripPhase.scored.wire : TripPhase.unscored.wire,
        ),
        distanceM: Value(score.summary.distanceM),
        movingS: Value(score.summary.movingTimeS),
        limitCoverage: Value(match.limitCoverage),
        nightFraction: Value(nightFraction),
        weather: Value(weather?.wire),
        packRegion: Value(pack?.region),
        packVersion: Value(pack?.version),
        isPassenger: Value(passenger),
        passengerAnswered: markAnswered
            ? const Value(true)
            : const Value.absent(),
        endedAt: trip.endedAt == null
            ? Value(samples.last.t)
            : const Value.absent(),
      ),
    );
    return FinalizeResult(trip: (await _db.tripById(tripId))!, score: view);
  }

  /// Finalises every trip that ended without being scored (app killed in
  /// between). Returns the ids processed.
  Future<List<String>> resumePending() async {
    final pending = await _db.tripsInPhase(TripPhase.pendingPassenger);
    final done = <String>[];
    for (final t in pending) {
      try {
        await finalize(t.id);
        done.add(t.id);
      } catch (e, s) {
        debugPrint('TripFinalizer: could not finalise ${t.id}: $e\n$s');
      }
    }
    return done;
  }

  /// The installed pack whose box contains the trip's first fix (then last
  /// fix as a fallback), or null.
  Future<PackRef?> _packFor(List<scoring.GpsSample> samples) async {
    final packs = await _db.installedPacks();
    if (packs.isEmpty) return null;
    final p =
        smallestPackContaining(packs, samples.first.lat, samples.first.lon) ??
        smallestPackContaining(packs, samples.last.lat, samples.last.lon);
    if (p == null) return null;
    return PackRef(region: p.region, path: p.path, version: p.osmTimestamp);
  }

  /// A limit the user has flagged as wrong drops to confidence 0.5 on this
  /// phone until the shared cache confirms it (docs/03 §4.4).
  Future<Map<int, LimitOverride>> _pendingFlagOverrides(String region) async {
    final flags = await (_db.select(
      _db.limitFlags,
    )..where((f) => f.region.equals(region) | f.region.isNull())).get();
    final out = <int, LimitOverride>{};
    for (final f in flags) {
      final id = int.tryParse(f.wayId);
      if (id == null) continue;
      out[id] = LimitOverride(
        wayId: id,
        limitMps: f.suggestedMps,
        confidence: 0.5,
      );
    }
    return out;
  }

  /// Database rows to engine samples. Fixes without an OS speed get one from
  /// the neighbouring positions so the engine never sees a hole.
  static List<scoring.GpsSample> toGpsSamples(List<Sample> rows) {
    final out = <scoring.GpsSample>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      var speed = r.speed;
      if (speed == null) {
        if (i > 0) {
          final p = rows[i - 1];
          final dt = (r.t - p.t) / 1000;
          speed = dt > 0
              ? scoring.haversine(p.lat, p.lon, r.lat, r.lon) / dt
              : 0;
        } else if (rows.length > 1) {
          final n = rows[1];
          final dt = (n.t - r.t) / 1000;
          speed = dt > 0
              ? scoring.haversine(r.lat, r.lon, n.lat, n.lon) / dt
              : 0;
        } else {
          speed = 0;
        }
      }
      out.add(
        scoring.GpsSample(
          t: r.t,
          lat: r.lat,
          lon: r.lon,
          speed: speed,
          accuracy: r.accuracy,
          heading: r.heading,
          altitude: r.altitude,
        ),
      );
    }
    return out;
  }
}
