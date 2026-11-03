import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/leagues/leagues_screen.dart';
import 'package:drivalry/features/leagues/widgets/standings_table.dart';
import 'package:drivalry/features/leagues/widgets/tier_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

Standing row(
  String id,
  int rank, {
  int xp = 10,
  int trips = 1,
  LeagueTier tier = LeagueTier.bronze,
  LeagueTier? projected,
}) => Standing(
  userId: id,
  handle: id,
  displayName: id,
  xp: xp,
  trips: trips,
  rating: null,
  rank: rank,
  tier: tier,
  projectedTier: projected ?? tier,
);

void main() {
  setUp(() => Haptics.enabled = false);

  testWidgets('LeaguesScreen explains itself in an offline build', (
    tester,
  ) async {
    // Tests run without --dart-define, so Env.hasSupabase is false and the
    // SignedInScope renders the offline notice under the large title.
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LeaguesScreen())),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Leagues'), findsWidgets);
    expect(find.text('Offline build'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    await unmountAndSettle(tester);
  });

  testWidgets(
    'signed in with no leagues: hub tiles, season hero and the empty state '
    'with its own button',
    (tester) async {
      final db = memoryDatabase();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            currentUserIdProvider.overrideWithValue('me'),
            cloudConfiguredProvider.overrideWithValue(true),
            supabaseProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(home: LeaguesScreen()),
        ),
      );
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('Duels'), findsOneWidget);
      expect(find.text('Badges'), findsOneWidget);
      expect(find.text('SEASON 1'), findsOneWidget);
      expect(find.text('Global league'), findsOneWidget);
      // The list builds lazily; the empty state sits under the hero tiles.
      await tester.dragUntilVisible(
        find.text('No friend leagues yet.'),
        find.byType(CustomScrollView),
        const Offset(0, -300),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('No friend leagues yet.'), findsOneWidget);
      expect(find.text('Create or join'), findsOneWidget);
      // The empty state owns the action; no FAB competes with it.
      expect(find.byType(FloatingActionButton), findsNothing);
      await unmountAndSettle(tester);
      await db.close();
    },
    skip: skipWithoutSqlite() != null,
  );

  testWidgets('StandingsTable shows ranks, XP, arrows and the no-drive line', (
    tester,
  ) async {
    final week = WeekStandings(
      weekStart: DateTime(2026, 11, 2),
      finalized: false,
      rows: [
        row('ryan', 1, xp: 180, trips: 4, projected: LeagueTier.silver),
        row('sam', 2, xp: 120, trips: 3, projected: LeagueTier.silver),
        row('kim', 3, xp: 90, trips: 2, projected: LeagueTier.silver),
        row('lee', 4, xp: 60, trips: 2, projected: LeagueTier.silver),
        row('ash', 5, xp: 30, trips: 1, projected: LeagueTier.silver),
        row('pat', 6, xp: 0, trips: 0, projected: LeagueTier.learner),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StandingsTable(week: week, me: 'sam'),
          ),
        ),
      ),
    );
    // Rows stagger in and the XP counts up; let both finish.
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('@ryan'), findsOneWidget);
    expect(find.text('@sam'), findsOneWidget);
    expect(find.text('180 XP'), findsOneWidget);
    expect(find.text("Didn't drive. The league didn't wait."), findsOneWidget);
    expect(find.text('PROMOTION ZONE'), findsOneWidget);
    expect(find.text('RELEGATION ZONE'), findsOneWidget);
    expect(
      find.byIcon(Icons.arrow_upward),
      findsNWidgets(6),
    ); // 5 rows + zone label
    // The zone label plus the one member who did not drive (Bronze → Learner).
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(2));
    expect(find.byType(TierPill), findsNWidgets(6));
    // Your row carries the ring; nobody else does.
    final mine = tester.widget<Avatar>(
      find.byWidgetPredicate((w) => w is Avatar && w.name == 'sam'),
    );
    expect(mine.isMe, isTrue);
  });

  testWidgets('a standing row counts its XP up instead of popping in', (
    tester,
  ) async {
    final week = WeekStandings(
      weekStart: DateTime(2026, 11, 2),
      finalized: false,
      rows: [row('ryan', 1, xp: 180, trips: 4)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StandingsTable(week: week, me: null)),
      ),
    );
    String xpText() =>
        tester.widget<Text>(find.textContaining(' XP')).data ?? '';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final midway = xpText();
    expect(midway, isNot('180 XP'));
    expect(midway, endsWith(' XP'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(xpText(), '180 XP');
  });

  testWidgets('a finalised week says so and hides projections for stayers', (
    tester,
  ) async {
    final week = WeekStandings(
      weekStart: DateTime(2026, 10, 26),
      finalized: true,
      rows: [row('a', 1, xp: 50), row('b', 2, xp: 40)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StandingsTable(week: week, me: null)),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.textContaining('Final'), findsOneWidget);
    expect(find.text('PROMOTION ZONE'), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });
}
