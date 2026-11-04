import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/features/drive/trip_detail_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_tracking_port.dart';
import '../art_harness.dart';
import '../../support/sqlite_support.dart';
import 'scene.dart';

/// One mediocre trip on the detail screen: the roast headline, the score
/// breakdown, the stats and the two events that cost the points.
class TripScene extends ArtScene {
  AppDatabase? _db;
  FakeTrackingPort? _port;

  static const _tripId = 'art-roast';

  @override
  String get id => '02-trip';

  @override
  String get headline => 'Roasts for the drive, not the driver.';

  @override
  String get subline =>
      'Every trip gets a verdict. Speeding and phone grabs cost points and '
      'get called out.';

  @override
  Future<Widget> build() async {
    final db = _db = memoryDatabase();
    final port = _port = FakeTrackingPort();
    await _seedTrip(db);

    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        trackingPortProvider.overrideWithValue(port),
        weatherClientProvider.overrideWithValue(const NoWeather()),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const TripDetailScreen(tripId: _tripId),
      ),
    );
  }

  @override
  Future<void> prepare(WidgetTester tester) async {
    // The seeded trip has no route, so the page opens on the hero: ring,
    // verdict and breakdown are the shot. Nothing to scroll.
  }

  @override
  Future<void> dispose() async {
    await _port?.dispose();
    await _db?.close();
  }

  /// A 9 mile evening commute scored 58: one speeding episode and one phone
  /// episode, the shape `TripScoreView` reads.
  static Future<void> _seedTrip(AppDatabase db) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 17, 42);
    final startT = start.millisecondsSinceEpoch;
    const movingS = 1380.0; // 23 min
    const totalS = 1500.0;
    const distanceM = 14800.0; // 9.2 mi
    final endT = startT + (totalS * 1000).round();

    const limit35 = 15.6464; // 35 mph in m/s
    const speed48 = 21.4603; // 48 mph
    const speed38 = 16.9926; // 38 mph

    await db.ensureTrip(
      TripsCompanion.insert(
        id: _tripId,
        startedAt: startT,
        endedAt: Value(endT),
        phase: TripPhase.scored.wire,
        endReason: const Value('stationary'),
        triggerKind: const Value('activity'),
        createdAt: startT,
        isPassenger: const Value(false),
        passengerAnswered: const Value(true),
        distanceM: const Value(distanceM),
        movingS: const Value(movingS),
        packRegion: const Value('us-tn'),
        packVersion: const Value('2026-10-01'),
        limitCoverage: const Value(0.82),
      ),
    );

    final speedingStart = startT + 9 * 60_000;
    final phoneStart = startT + 15 * 60_000;
    final events = <Map<String, dynamic>>[
      {
        'kind': 'speeding',
        'severity': 'moderate',
        'startT': speedingStart,
        'endT': speedingStart + 74_000,
        'durationS': 74,
        'startIdx': 540,
        'endIdx': 614,
        'lat': 36.1335,
        'lon': -86.8460,
        'detail': {
          'kind': 'speeding',
          'limit': limit35,
          'maxSpeed': speed48,
          'avgOver': 4.1,
          'maxOver': speed48 - limit35,
          'roadName': 'Harding Pike',
          'roadClass': 'primary',
          'timeSavedS': 11,
        },
      },
      {
        'kind': 'phone_handling',
        'severity': 'moderate',
        'startT': phoneStart,
        'endT': phoneStart + 23_000,
        'durationS': 23,
        'startIdx': 900,
        'endIdx': 923,
        'lat': 36.1190,
        'lon': -86.8695,
        'detail': {
          'kind': 'phone_handling',
          'interactions': 2,
          'maxSpeed': speed38,
          'kinds': ['unlock', 'touch'],
        },
      },
    ];
    const headline = 'Two phone grabs and 48 in a 35. The roast writes itself.';
    final json = {
      'tripId': _tripId,
      'scored': true,
      'score': 58,
      'penalties': {
        'speed': 24.0,
        'smoothness': 0.0,
        'attention': 18.0,
        'efficiency': 0.0,
      },
      'flags': <String>[],
      'reckless': false,
      'xp': 32,
      'events': events,
      'observations': <Map<String, dynamic>>[],
      'summary': {
        'distanceM': distanceM,
        'movingTimeS': movingS,
        'totalTimeS': totalS,
        'maxSpeed': speed48,
        'avgMovingSpeed': 10.72,
        'secondsOverLimit': 74,
        'secondsWithKnownLimit': 1132,
        'timeSavedBySpeedingS': 11,
        'startT': startT,
        'endT': endT,
        'nightFraction': 0.0,
        'gpsQuality': 0.96,
      },
      'feedback': {
        'headline': {'tone': 'roast', 'text': headline},
        // One line keeps the header the height of the ring, so the events
        // list stays inside the store frame.
        'lines': [
          {
            'tone': 'roast',
            'text': '48 in a 35 on Harding Pike. All that for 11 seconds.',
            'eventIndex': 0,
          },
        ],
      },
    };
    await db.upsertScore(
      TripScoresCompanion.insert(
        tripId: _tripId,
        scoreJson: jsonEncode(json),
        score: const Value(58),
        xp: 32,
        reckless: false,
        scored: true,
        roastText: const Value(headline),
        scoredAt: endT + 2_000,
      ),
    );
  }
}
