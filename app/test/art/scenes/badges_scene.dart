import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/badges/badges_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/scored_trips.dart';
import '../../support/sqlite_support.dart';
import '../art_harness.dart';
import 'scene.dart';

/// Store screenshot 07: the real [BadgesScreen] with a handful of earned
/// badges above the locked ones, and live streaks in the top row.
///
/// Awards are written the way [BadgeEngine] writes them
/// (`AppDatabase.awardBadge`), with dates spread over the autumn. The streak
/// row is computed from seeded trips: the newest twelve are clean and the
/// newest twenty-three are phone-free, so both numbers differ. Definitions
/// come from the built-in list because the scene has no cloud.
class BadgesScene extends ArtScene {
  AppDatabase? _db;

  @override
  String get id => '07-badges';

  @override
  String get headline => 'Badges for streaks, not speed.';

  @override
  String get subline =>
      'Clean trips, phone-free weeks and perfect commutes. Nothing here '
      'rewards going fast.';

  @override
  Future<Widget> build() async {
    final db = memoryDatabase();
    _db = db;
    await _seed(db);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        supabaseProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const BadgesScreen(),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}

/// Earned badges (id, month, day), newest first as the screen lists them.
/// Exactly what [BadgeEngine] would award for the trips seeded below, on
/// the day of the trip that earned each one. Four, not more, so the first
/// locked badge is still in view under the streak row on the 9:16 frame.
const List<(String, int, int)> _awards = [
  ('perfect_100', 12, 19),
  ('phone_free_10', 11, 19),
  ('clean_5', 11, 1),
  ('first_trip', 10, 20),
];

Future<void> _seed(AppDatabase db) async {
  for (final (id, month, day) in _awards) {
    await db.awardBadge(
      id,
      DateTime(2026, month, day, 18).millisecondsSinceEpoch,
    );
  }

  // Trips for the streak row, one every three days back from 28 December,
  // newest first: twelve clean (one of them a 100), then one rough evening
  // (clean streak 12), then ten more phone-free ones and one with the phone
  // in hand (phone-free streak 23).
  const trips = 24;
  final newest = DateTime(2026, 12, 28, 17, 40);
  for (var i = 0; i < trips; i++) {
    final startedAt = newest
        .subtract(Duration(days: i * 3, hours: i.isEven ? 0 : 10))
        .millisecondsSinceEpoch;
    await seedScoredTrip(
      db,
      id: 'streak-$i',
      startedAt: startedAt,
      score: switch (i) {
        3 => 100,
        12 => 71,
        _ => 84 + (i * 7) % 15,
      },
      phoneHandling: i == 23,
      nightFraction: i.isEven ? 0.0 : 0.6,
      weather: i % 5 == 0 ? 'rain' : 'clear',
      packRegion: 'us-tn',
      distanceM: 6000.0 + 900 * (i % 7),
      movingS: 700 + 60.0 * (i % 7),
    );
  }
}
