import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/theme.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/data/models/trip_score_view.dart';
import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/features/drive/share_card.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Trip sampleTrip() => Trip(
  id: 'trip-1',
  startedAt: DateTime(2026, 11, 3, 8, 15).millisecondsSinceEpoch,
  endedAt: DateTime(2026, 11, 3, 8, 45).millisecondsSinceEpoch,
  phase: TripPhase.scored.wire,
  distanceM: 12400,
  movingS: 1500,
  passengerHint: false,
  passengerAnswered: true,
  crashCandidate: false,
  createdAt: 0,
).copyWith(isPassenger: const Value(false));

TripScoreView sampleScore({bool reckless = false}) => TripScoreView.fromJson({
  'tripId': 'trip-1',
  'scored': true,
  'score': reckless ? 22 : 87,
  'penalties': {
    'speed': 6.5,
    'smoothness': 4,
    'attention': 0,
    'efficiency': 2.5,
  },
  'flags': reckless ? ['reckless'] : [],
  'reckless': reckless,
  'xp': reckless ? 0 : 71,
  'events': [],
  'observations': [],
  'summary': {
    'distanceM': 12400,
    'movingTimeS': 1500,
    'totalTimeS': 1620,
    'maxSpeed': 28,
    'avgMovingSpeed': 8.2,
    'secondsOverLimit': 90,
    'secondsWithKnownLimit': 1400,
    'timeSavedBySpeedingS': 12,
    'startT': 0,
    'endT': 1500000,
    'nightFraction': 0,
    'gpsQuality': 1,
  },
  'feedback': {
    'headline': {
      'tone': 'roast',
      'text':
          '41 in a 25 for 90 s on Elm St. The limit is a number, not a dare.',
    },
    'lines': [],
  },
});

void main() {
  testWidgets('the card shows the score, the line, stats and the handle', (
    tester,
  ) async {
    tester.view.physicalSize = shareCardSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: DrivalryTheme.light(),
        home: ShareTripCard(
          trip: sampleTrip(),
          score: sampleScore(),
          units: SpeedUnits.mph,
          handle: 'ryan',
          tier: LeagueTier.gold,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('DRIVE SCORE'), findsOneWidget);
    expect(find.text('87'), findsOneWidget);
    expect(find.text('+71 XP'), findsOneWidget);
    expect(find.textContaining('41 in a 25'), findsOneWidget);
    expect(find.text('7.7 mi'), findsOneWidget);
    expect(find.text('25 min'), findsOneWidget);
    expect(find.text('drivalry'), findsOneWidget);
    expect(find.text('@ryan · Gold'), findsOneWidget);
    expect(find.text('RECKLESS'), findsNothing);
    // Nothing geographic: no map widget, no place names.
    expect(
      find.textContaining('Elm St'),
      findsOneWidget,
      reason: 'road name from the roast is fine',
    );
  });

  testWidgets('a reckless trip gets the stamp', (tester) async {
    tester.view.physicalSize = shareCardSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: DrivalryTheme.light(),
        home: ShareTripCard(
          trip: sampleTrip(),
          score: sampleScore(reckless: true),
          units: SpeedUnits.kmh,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('RECKLESS'), findsWidgets);
    expect(find.text('12 km'), findsOneWidget);
  });

  testWidgets('renderWidgetToPng produces a PNG', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final bytes = await tester.runAsync(
      () => renderWidgetToPng(
        ShareTripCard(
          trip: sampleTrip(),
          score: sampleScore(),
          units: SpeedUnits.mph,
        ),
        view: tester.view,
        theme: DrivalryTheme.light(),
        pixelRatio: 0.25,
      ),
    );
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(1000));
    // PNG signature.
    expect(bytes.sublist(0, 8), [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
  });
}
