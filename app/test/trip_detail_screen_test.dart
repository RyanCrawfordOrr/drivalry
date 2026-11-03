import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/drive/trip_detail_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/scored_trips.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

void main() {
  final skip = skipWithoutSqlite() != null;

  testWidgets('the trip screen is editorial: hero, bars, stats, timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final port = FakeTrackingPort();
    await seedScoredTrip(
      db,
      id: 'd1',
      startedAt: DateTime(2026, 11, 3, 17, 42).millisecondsSinceEpoch,
      score: 58,
      xp: 32,
      phoneHandling: true,
      packRegion: 'us-tn',
      headline: 'Two phone grabs. The roast writes itself.',
    );
    await db.updateTrip(
      'd1',
      const TripsCompanion(
        passengerAnswered: Value(true),
        limitCoverage: Value(0.82),
        packVersion: Value('2026-10-01'),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          trackingPortProvider.overrideWithValue(port),
          weatherClientProvider.overrideWithValue(const NoWeather()),
        ],
        child: const MaterialApp(home: TripDetailScreen(tripId: 'd1')),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 2));

    // Hero: ring with XP under it, verdict beside it.
    expect(find.text('58'), findsOneWidget);
    expect(find.text('+32 XP'), findsOneWidget);
    expect(
      find.text('Two phone grabs. The roast writes itself.'),
      findsOneWidget,
    );
    // Sections as kickers.
    expect(find.text('BREAKDOWN'), findsOneWidget);
    expect(find.text('STATS'), findsOneWidget);
    expect(find.text('WHAT HAPPENED'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Clean'), findsWidgets);
    // Timeline row in plain words, no severity jargon.
    expect(find.textContaining('Phone picked up once'), findsOneWidget);
    expect(find.textContaining('Phone use ·'), findsOneWidget);
    expect(find.textContaining('Moderate'), findsNothing);
    // Footnote in one line, no pack or OSM detail.
    expect(find.text('82% of this drive had known limits.'), findsOneWidget);
    expect(find.textContaining('OSM'), findsNothing);
    // No route: calm copy, never a build flag.
    expect(find.text('Route not saved for this trip.'), findsOneWidget);
    expect(find.textContaining('dart-define'), findsNothing);
    // Share is the only app-bar action besides the overflow.
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);

    await unmountAndSettle(tester);
    await port.dispose();
    await db.close();
  }, skip: skip);
}
