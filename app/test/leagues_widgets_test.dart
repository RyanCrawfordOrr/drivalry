import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/features/leagues/leagues_screen.dart';
import 'package:drivalry/features/leagues/widgets/standings_table.dart';
import 'package:drivalry/features/leagues/widgets/tier_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('LeaguesScreen explains itself in an offline build', (
    tester,
  ) async {
    // Tests run without --dart-define, so Env.hasSupabase is false and the
    // SignedInScope renders the offline notice instead of the list.
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LeaguesScreen())),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Leagues'), findsOneWidget);
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    expect(find.byTooltip('Badges'), findsOneWidget);
    await unmountAndSettle(tester);
  });

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
    await tester.pump();
    expect(find.text('@ryan'), findsOneWidget);
    expect(find.text('@sam (you)'), findsOneWidget);
    expect(find.text('180 XP'), findsOneWidget);
    expect(
      find.text("Didn't drive? That's fine. The league didn't wait."),
      findsOneWidget,
    );
    expect(find.text('Promotion zone'), findsOneWidget);
    expect(find.text('Relegation zone'), findsOneWidget);
    expect(
      find.byIcon(Icons.arrow_upward),
      findsNWidgets(6),
    ); // 5 rows + zone label
    // The zone label plus the one member who did not drive (Bronze → Learner).
    expect(find.byIcon(Icons.arrow_downward), findsNWidgets(2));
    expect(find.byType(TierChip), findsNWidgets(6));
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
    await tester.pump();
    expect(find.textContaining('Final.'), findsOneWidget);
    expect(find.text('Promotion zone'), findsNothing);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });
}
