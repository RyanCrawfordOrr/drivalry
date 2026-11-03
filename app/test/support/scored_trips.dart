import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';

/// Inserts a scored driver trip with a minimal but well-formed score JSON,
/// the shape `TripScoreView` reads. Returns the trip id.
Future<String> seedScoredTrip(
  AppDatabase db, {
  required String id,
  required int startedAt,
  int score = 90,
  int xp = 60,
  bool reckless = false,
  bool phoneHandling = false,
  double? nightFraction,
  String? weather,
  String? packRegion,
  double? altitudeM,
  double distanceM = 8000,
  double movingS = 900,
  String headline = 'Smooth. Keep it up.',
}) async {
  await db.ensureTrip(
    TripsCompanion.insert(
      id: id,
      startedAt: startedAt,
      endedAt: Value(startedAt + (movingS * 1000).round()),
      phase: TripPhase.scored.wire,
      createdAt: startedAt,
      isPassenger: const Value(false),
      distanceM: Value(distanceM),
      movingS: Value(movingS),
      nightFraction: Value(nightFraction),
      weather: Value(weather),
      packRegion: Value(packRegion),
    ),
  );
  final events = <Map<String, dynamic>>[];
  if (phoneHandling) {
    events.add({
      'kind': 'phone_handling',
      'severity': 'minor',
      'startT': startedAt + 60_000,
      'endT': startedAt + 65_000,
      'durationS': 5,
      'startIdx': 60,
      'endIdx': 65,
      'lat': 36.16,
      'lon': -86.78,
      'detail': {},
    });
  }
  final json = {
    'tripId': id,
    'scored': true,
    'score': score,
    'penalties': {
      'speed': 0,
      'smoothness': 100 - score > 0 ? (100 - score).toDouble() : 0,
      'attention': 0,
      'efficiency': 0,
    },
    'flags': reckless ? ['reckless'] : [],
    'reckless': reckless,
    'xp': xp,
    'events': events,
    'observations': [],
    'summary': {
      'distanceM': distanceM,
      'movingTimeS': movingS,
      'totalTimeS': movingS + 60,
      'maxSpeed': 20,
      'avgMovingSpeed': 12,
      'secondsOverLimit': 0,
      'secondsWithKnownLimit': movingS,
      'timeSavedBySpeedingS': 0,
      'startT': startedAt,
      'endT': startedAt + (movingS * 1000).round(),
      'nightFraction': nightFraction ?? 0,
      'gpsQuality': 1,
    },
    'feedback': {
      'headline': {'tone': 'praise', 'text': headline},
      'lines': [],
    },
  };
  await db.upsertScore(
    TripScoresCompanion.insert(
      tripId: id,
      scoreJson: jsonEncode(json),
      score: Value(score),
      xp: xp,
      reckless: reckless,
      scored: true,
      roastText: Value(headline),
      scoredAt: startedAt + 1,
    ),
  );
  if (altitudeM != null) {
    await db.insertFixBatch(id, startedAt, [
      SamplesCompanion.insert(
        tripId: id,
        t: startedAt,
        lat: 36.16,
        lon: -86.78,
        accuracy: 5,
        altitude: Value(altitudeM),
      ),
    ]);
  }
  return id;
}
