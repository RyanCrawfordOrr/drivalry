import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/stats/stats_providers.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/stats/share_stats.dart';
import 'package:drivalry/features/stats/wrapped_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scored_trips.dart';
import '../../support/sqlite_support.dart';
import '../../support/widget_support.dart';
import '../art_harness.dart';
import 'scene.dart';

/// Store screenshot 06: the real [WrappedScreen] over one seeded season
/// (Oct–Dec 2026), opened on the "States visited" card.
///
/// The season is a fictional Nashville driver: nine commutes, a few long
/// weekends into Kentucky, Georgia, Alabama and North Carolina, a couple of
/// night drives and two rough trips so the numbers look lived-in rather
/// than perfect. Every per-trip aggregate the stats engine reads (schema 5:
/// extents, endpoints, road names, `statsAt`) is written on the row, so the
/// backfill has nothing to do and the screen settles in one pass.
class WrappedScene extends ArtScene {
  WrappedScene({this.card = 4});

  /// Index of the Wrapped card to show (0 cover, 1 distance, 2 score,
  /// 3 habits, 4 states, 5 groundhog, 6 reality, 7 records, 8 social,
  /// 9 outro).
  final int card;

  AppDatabase? _db;

  @override
  String get id => '06-wrapped';

  @override
  String get headline => 'Your season, wrapped.';

  @override
  String get subline =>
      'Streets, states, night miles and fun facts, shareable at the end of '
      'every quarter.';

  @override
  Duration get settle => const Duration(seconds: 3);

  /// Pinned "now": late December, so the current quarter is the season.
  static final DateTime now = DateTime(2026, 12, 29, 18);

  @override
  Future<Widget> build() async {
    final db = memoryDatabase();
    _db = db;
    await _seedSeason(db);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        statsClockProvider.overrideWithValue(() => now),
        shareImageProvider.overrideWithValue(_noShare),
        supabaseProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const WrappedScreen(),
      ),
    );
  }

  @override
  Future<void> prepare(WidgetTester tester) async {
    final pageView = tester.widget<PageView>(find.byType(PageView));
    pageView.controller!.jumpToPage(card);
    await pumpFor(tester, const Duration(seconds: 1));
  }

  @override
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _noShare({
    required Uint8List png,
    required String fileName,
    required String text,
  }) async {}
}

// ---------------------------------------------------------------- data --

enum _Route { toWork, toHome, errand, away }

typedef _TripSpec = ({
  int day,
  int hour,
  int minute,
  int score,
  double km,
  double night,
  String weather,
  String region,
  _Route route,
});

typedef _Point = ({double lat, double lon});

const _Point _home = (lat: 36.1200, lon: -86.7900);
const _Point _work = (lat: 36.1620, lon: -86.7810);

/// Day 0 is 1 October 2026. Mostly 70–95, two rough evenings, a few long
/// weekends out of state. Fictional throughout.
const List<_TripSpec> _season = [
  (
    day: 1,
    hour: 7,
    minute: 40,
    score: 88,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 1,
    hour: 17,
    minute: 35,
    score: 84,
    km: 10.2,
    night: 0.1,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 3,
    hour: 14,
    minute: 10,
    score: 92,
    km: 64,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.errand,
  ),
  (
    day: 5,
    hour: 7,
    minute: 45,
    score: 91,
    km: 9.6,
    night: 0,
    weather: 'rain',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 5,
    hour: 18,
    minute: 20,
    score: 79,
    km: 10.2,
    night: 0.2,
    weather: 'rain',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 8,
    hour: 21,
    minute: 30,
    score: 86,
    km: 14,
    night: 1,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.errand,
  ),
  (
    day: 10,
    hour: 9,
    minute: 0,
    score: 90,
    km: 285,
    night: 0,
    weather: 'clear',
    region: 'us-ky',
    route: _Route.away,
  ),
  (
    day: 11,
    hour: 16,
    minute: 0,
    score: 83,
    km: 290,
    night: 0.35,
    weather: 'clear',
    region: 'us-ky',
    route: _Route.away,
  ),
  (
    day: 13,
    hour: 7,
    minute: 50,
    score: 94,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 13,
    hour: 17,
    minute: 40,
    score: 58,
    km: 10.2,
    night: 0.15,
    weather: 'rain',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 15,
    hour: 12,
    minute: 15,
    score: 97,
    km: 4.8,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.errand,
  ),
  (
    day: 18,
    hour: 7,
    minute: 35,
    score: 89,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 18,
    hour: 18,
    minute: 5,
    score: 86,
    km: 10.2,
    night: 0.3,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 21,
    hour: 6,
    minute: 10,
    score: 93,
    km: 22,
    night: 0.8,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.errand,
  ),
  (
    day: 24,
    hour: 15,
    minute: 30,
    score: 87,
    km: 390,
    night: 0.25,
    weather: 'clear',
    region: 'us-ga',
    route: _Route.away,
  ),
  (
    day: 26,
    hour: 10,
    minute: 0,
    score: 81,
    km: 240,
    night: 0,
    weather: 'rain',
    region: 'us-al',
    route: _Route.away,
  ),
  (
    day: 27,
    hour: 19,
    minute: 45,
    score: 85,
    km: 180,
    night: 0.9,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.away,
  ),
  (
    day: 33,
    hour: 7,
    minute: 45,
    score: 90,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 33,
    hour: 17,
    minute: 50,
    score: 76,
    km: 10.2,
    night: 0.4,
    weather: 'rain',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 36,
    hour: 22,
    minute: 15,
    score: 88,
    km: 31,
    night: 1,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.errand,
  ),
  (
    day: 40,
    hour: 7,
    minute: 40,
    score: 92,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 40,
    hour: 17,
    minute: 30,
    score: 64,
    km: 10.2,
    night: 0.45,
    weather: 'rain',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 44,
    hour: 8,
    minute: 30,
    score: 89,
    km: 310,
    night: 0,
    weather: 'clear',
    region: 'us-nc',
    route: _Route.away,
  ),
  (
    day: 45,
    hour: 13,
    minute: 0,
    score: 91,
    km: 318,
    night: 0.5,
    weather: 'snow',
    region: 'us-nc',
    route: _Route.away,
  ),
  (
    day: 48,
    hour: 7,
    minute: 45,
    score: 87,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 48,
    hour: 18,
    minute: 30,
    score: 93,
    km: 10.2,
    night: 0.7,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 55,
    hour: 15,
    minute: 0,
    score: 84,
    km: 275,
    night: 0.3,
    weather: 'rain',
    region: 'us-ky',
    route: _Route.away,
  ),
  (
    day: 58,
    hour: 10,
    minute: 30,
    score: 90,
    km: 275,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.away,
  ),
  (
    day: 62,
    hour: 7,
    minute: 50,
    score: 96,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 62,
    hour: 17,
    minute: 45,
    score: 88,
    km: 10.2,
    night: 0.8,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 70,
    hour: 7,
    minute: 40,
    score: 91,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
  (
    day: 70,
    hour: 18,
    minute: 10,
    score: 85,
    km: 10.2,
    night: 0.9,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toHome,
  ),
  (
    day: 75,
    hour: 20,
    minute: 0,
    score: 94,
    km: 18,
    night: 1,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.errand,
  ),
  (
    day: 79,
    hour: 9,
    minute: 15,
    score: 90,
    km: 48,
    night: 0,
    weather: 'snow',
    region: 'us-tn',
    route: _Route.errand,
  ),
  (
    day: 84,
    hour: 11,
    minute: 0,
    score: 93,
    km: 95,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.away,
  ),
  (
    day: 86,
    hour: 14,
    minute: 0,
    score: 89,
    km: 95,
    night: 0.2,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.away,
  ),
  (
    day: 88,
    hour: 7,
    minute: 45,
    score: 95,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    route: _Route.toWork,
  ),
];

Future<void> _seedSeason(AppDatabase db) async {
  final seasonStart = DateTime(2026, 10, 1);
  for (final (id, label, kind, p) in [
    ('home', 'Home', 'home', _home),
    ('work', 'Work', 'work', _work),
  ]) {
    await db
        .into(db.places)
        .insert(
          PlacesCompanion.insert(
            id: id,
            label: label,
            kind: Value(kind),
            lat: p.lat,
            lon: p.lon,
            createdAt: seasonStart.millisecondsSinceEpoch,
          ),
        );
  }

  for (var i = 0; i < _season.length; i++) {
    final s = _season[i];
    final id = 'season-$i';
    final startedAt = seasonStart
        .add(Duration(days: s.day, hours: s.hour, minutes: s.minute))
        .millisecondsSinceEpoch;
    final highway = s.km > 60;
    final movingS = s.km / (highway ? 95 : 30) * 3600;
    await seedScoredTrip(
      db,
      id: id,
      startedAt: startedAt,
      score: s.score,
      xp: (s.score * 0.6).round() + (highway ? 20 : 0),
      phoneHandling: s.score < 70,
      nightFraction: s.night,
      weather: s.weather,
      packRegion: s.region,
      distanceM: s.km * 1000,
      movingS: movingS,
    );

    // Per-trip aggregates, as the finaliser would have stored them.
    final (_Point start, _Point end) = switch (s.route) {
      _Route.toWork => (_home, _work),
      _Route.toHome => (_work, _home),
      _Route.errand => (_home, (lat: 36.05 + 0.01 * i, lon: -86.9 + 0.004 * i)),
      _Route.away => (_home, (lat: 34.5 + 0.08 * i, lon: -84.0 - 0.06 * i)),
    };
    final roads = switch (s.route) {
      _Route.toWork || _Route.toHome => ['Broadway', 'West End Ave', 'I-440'],
      _Route.errand => ['Hillsboro Pike', 'I-440'],
      _Route.away => ['I-24', 'I-65', 'I-40'],
    };
    final altitude = switch (s.region) {
      'us-nc' => 1980.0,
      'us-ky' => 420.0,
      _ => 210.0 + i,
    };
    await db.updateTrip(
      id,
      TripsCompanion(
        minLat: Value(start.lat < end.lat ? start.lat : end.lat),
        maxLat: Value(start.lat < end.lat ? end.lat : start.lat),
        minLon: Value(start.lon < end.lon ? start.lon : end.lon),
        maxLon: Value(start.lon < end.lon ? end.lon : start.lon),
        maxAltitudeM: Value(altitude),
        startLat: Value(start.lat),
        startLon: Value(start.lon),
        endLat: Value(end.lat),
        endLon: Value(end.lon),
        roadNames: Value('["${roads.join('","')}"]'),
        statsAt: Value(startedAt + 1),
      ),
    );
  }
}
