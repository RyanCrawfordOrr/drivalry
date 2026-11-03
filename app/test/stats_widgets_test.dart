import 'dart:typed_data';

import 'package:drivalry/app/routes.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/stats/stats_engine.dart';
import 'package:drivalry/data/stats/stats_providers.dart';
import 'package:drivalry/features/stats/profile_stats_card.dart';
import 'package:drivalry/features/stats/share_stats.dart';
import 'package:drivalry/features/stats/stats_screen.dart';
import 'package:drivalry/features/stats/wrapped_cards.dart';
import 'package:drivalry/features/stats/wrapped_screen.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/scored_trips.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

final now = DateTime(2026, 11, 3, 12);

class ShareCapture {
  final calls = <({Uint8List png, String fileName, String text})>[];
  Future<void> call({
    required Uint8List png,
    required String fileName,
    required String text,
  }) async {
    calls.add((png: png, fileName: fileName, text: text));
  }
}

Widget harness(AppDatabase db, ShareCapture share, Widget home) =>
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        shareImageProvider.overrideWithValue(share.call),
        statsClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(home: home),
    );

Future<void> seedSeason(AppDatabase db) async {
  for (var i = 0; i < 4; i++) {
    await db.insertFixBatch('t$i', 0, const []);
    await seedScoredTrip(
      db,
      id: 't$i',
      startedAt: DateTime(2026, 10, 10 + i, 8).millisecondsSinceEpoch,
      // The oldest trip is not clean, so the streak (3) differs from the
      // trip count (4) and the card's numbers can be told apart.
      score: i == 0 ? 60 : 80 + i * 4,
      packRegion: i == 3 ? 'us-ky' : 'us-tn',
      distanceM: 12000,
    );
  }
}

void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late ShareCapture share;
  setUp(() {
    Haptics.enabled = false;
    db = memoryDatabase();
    share = ShareCapture();
  });
  tearDown(() => db.close());

  testWidgets('stats screen explains the empty state', (tester) async {
    await tester.pumpWidget(harness(db, share, const StatsScreen()));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('No scored trips yet.'), findsOneWidget);
    expect(find.text('Finish a drive and the numbers appear.'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('stats screen shows sections, numbers and the states grid', (
    tester,
  ) async {
    await seedSeason(db);
    await tester.pumpWidget(harness(db, share, const StatsScreen()));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('TOTALS'), findsOneWidget);
    expect(find.text('TRIPS'), findsWidgets);
    expect(find.text('4'), findsWidgets);
    // The list builds lazily; scroll the lower sections into view.
    await tester.dragUntilVisible(
      find.text('GEOGRAPHY'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(find.text('GEOGRAPHY'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('TN'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pump();
    expect(find.text('TN'), findsOneWidget);
    expect(find.text('KY'), findsOneWidget);
    // Sections revealed by the scroll stagger in; let their timers finish.
    await pumpFor(tester, const Duration(milliseconds: 500));
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('share headline renders a PNG and hands it to the sharer', (
    tester,
  ) async {
    await seedSeason(db);
    await tester.pumpWidget(harness(db, share, const StatsScreen()));
    await pumpFor(tester, const Duration(seconds: 2));
    await tester.runAsync(() async {
      await tester.tap(find.text('Share headline'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    expect(share.calls, hasLength(1));
    expect(share.calls.single.png.length, greaterThan(100));
    expect(share.calls.single.fileName, startsWith('drivalry-stats-'));
    await unmountAndSettle(tester);
  }, skip: skip);

  test('the Wrapped always has ten cards, one colour each', () {
    final empty = computeDriverStats(
      const StatsInput(trips: []),
      StatsRange.season(now),
    );
    final cards = wrappedCards(empty, SpeedUnits.mph);
    expect(cards, hasLength(10));
    expect(
      wrappedCards(empty, SpeedUnits.kmh).map((c) => c.id).toSet(),
      hasLength(10),
    );
    expect(cards.map((c) => c.color).toList(), wrappedPalette);
  });

  testWidgets('wrapped screen explains the empty state', (tester) async {
    await tester.pumpWidget(harness(db, share, const WrappedScreen()));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Nothing to wrap yet.'), findsOneWidget);
    expect(find.text('Share this card'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('wrapped screen opens on the intro, pages through and shares', (
    tester,
  ) async {
    await seedSeason(db);
    await tester.pumpWidget(harness(db, share, const WrappedScreen()));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Oct–Dec 2026'), findsWidgets);
    expect(find.text('Swipe through your season.'), findsOneWidget);
    // Nothing to share on the intro page.
    final share0 = tester.widget<SecondaryButton>(find.byType(SecondaryButton));
    expect(share0.onPressed, isNull);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('trips as the driver'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Distance driven'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Share this card'));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    expect(share.calls, hasLength(1));
    expect(share.calls.single.fileName, 'drivalry-wrapped-distance.png');
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('profile card shows the all-time numbers and opens the stats', (
    tester,
  ) async {
    await seedSeason(db);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: ProfileStatsCard()),
        ),
        GoRoute(
          path: Routes.stats,
          builder: (_, _) => const Scaffold(body: Text('stats route')),
        ),
        GoRoute(
          path: Routes.wrapped,
          builder: (_, _) => const Scaffold(body: Text('wrapped route')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          statsClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('STATS'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('81'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Clean streak'), findsOneWidget);
    await tester.tap(find.text('All stats'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('stats route'), findsOneWidget);
    await unmountAndSettle(tester);
    router.dispose();
  }, skip: skip);
}
