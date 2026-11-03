import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/cues/live_limit.dart';
import 'package:drivalry/features/drive/drive_screen.dart';
import 'package:drivalry/features/drive/drive_sheet.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/scored_trips.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

const _granted = TrackingPermissions(
  location: LocationPermission.always,
  preciseLocation: true,
  motion: SimplePermission.granted,
  notifications: SimplePermission.granted,
  bluetooth: SimplePermission.granted,
);

/// A phone-sized surface so the sheet's peek has room for the live block.
void phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget harness(
  AppDatabase db,
  FakeTrackingPort port, {
  LiveLimitState? liveLimit,
}) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    trackingPortProvider.overrideWithValue(port),
    deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
    weatherClientProvider.overrideWithValue(const NoWeather()),
    devToolsVisibleProvider.overrideWithValue(false),
    if (liveLimit != null)
      liveLimitProvider.overrideWith((_) => Stream.value(liveLimit)),
  ],
  child: const MaterialApp(home: DriveScreen()),
);

/// Top edge of the Drive sheet, in logical pixels from the top of the screen.
double sheetTop(WidgetTester tester) => tester
    .getTopLeft(
      find.descendant(
        of: find.byKey(const Key('drive-sheet')),
        matching: find.byType(ListView),
      ),
    )
    .dy;

Future<void> seedAnsweredTrip(
  AppDatabase db, {
  required String id,
  required DateTime startedAt,
  int score = 90,
  String headline = 'Smooth. Keep it up.',
}) async {
  await seedScoredTrip(
    db,
    id: id,
    startedAt: startedAt.millisecondsSinceEpoch,
    score: score,
    packRegion: 'us-tn',
    headline: headline,
  );
  await db.updateTrip(id, const TripsCompanion(passengerAnswered: Value(true)));
}

void main() {
  // testWidgets takes a bool; the reason is printed by the unit tests.
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  setUp(() => db = memoryDatabase());
  // Closing the database inside the fake-async test body would hang; the
  // group tearDown runs on the real event loop.
  tearDown(() async {
    await port.dispose();
    await db.close();
  });

  testWidgets(
    'first launch without permissions shows the three pages, then the home',
    (tester) async {
      phoneSize(tester);
      port = FakeTrackingPort(state: const TrackingState());
      await tester.pumpWidget(harness(db, port));
      await pumpFor(tester, const Duration(seconds: 1));

      // Page one: what Drivalry does, one button.
      expect(find.byKey(const Key('first-run')), findsOneWidget);
      expect(find.text('Every drive gets a score.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
      // No permission paragraphs, no bullets.
      expect(find.textContaining('•'), findsNothing);

      await tester.tap(find.text('Next'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('Allow location all the time.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Allow'), findsOneWidget);

      // The fake grants everything, so the flow finishes itself.
      await tester.tap(find.text('Allow'));
      await pumpFor(tester, const Duration(seconds: 2));
      expect(port.calls, contains('requestPermissions'));
      expect(await db.getSetting(firstRunDoneKey), '1');

      // Map-first home: capsule, round buttons, empty sheet copy.
      expect(find.byKey(const Key('first-run')), findsNothing);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Go for a drive.'), findsOneWidget);
      expect(find.text("We'll score it when you park."), findsOneWidget);
      expect(find.textContaining('imulate'), findsNothing);
      expect(find.byIcon(Icons.mark_email_unread_outlined), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      // Tests build without a cloud project: the map explains itself calmly.
      expect(
        find.text('Friends are not available in this version.'),
        findsOneWidget,
      );
      expect(find.textContaining('dart-define'), findsNothing);
      await unmountAndSettle(tester);
    },
    skip: skip,
  );

  testWidgets(
    'with trips and partial permissions the sheet offers one tile and the '
    'capsule opens the detection sheet',
    (tester) async {
      phoneSize(tester);
      await seedAnsweredTrip(
        db,
        id: 't1',
        startedAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      port = FakeTrackingPort(
        state: const TrackingState(
          permissions: TrackingPermissions(
            location: LocationPermission.whileInUse,
            preciseLocation: true,
            motion: SimplePermission.granted,
          ),
        ),
      );
      await tester.pumpWidget(harness(db, port));
      await pumpFor(tester, const Duration(seconds: 2));

      expect(find.byKey(const Key('first-run')), findsNothing);
      expect(find.text('Set up auto-detect'), findsOneWidget);
      expect(find.byKey(const Key('auto-detect-tile')), findsOneWidget);
      expect(find.text('Turn on auto-detect'), findsOneWidget);
      expect(find.text('LAST TRIP'), findsOneWidget);
      expect(find.text('Smooth. Keep it up.'), findsOneWidget);
      // Idle peek: the sheet leaves the map as the stage.
      expect(
        sheetTop(tester),
        closeTo(844 * (1 - DriveSheetSizes.peekIdle), 1),
      );

      await tester.tap(find.text('Set up auto-detect'));
      await pumpFor(tester, const Duration(seconds: 1));
      // The sheet carries the sentence the capsule has no room for.
      expect(
        find.text(
          'Finish setting up auto-detect so drives start on their own.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start a drive now'), findsOneWidget);
      await tester.tap(find.text('Start a drive now'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(port.calls, contains('forceStartTrip'));
      await unmountAndSettle(tester);
    },
    skip: skip,
  );

  testWidgets('a recording trip shows the live block and End drive', (
    tester,
  ) async {
    phoneSize(tester);
    port = FakeTrackingPort(
      state: const TrackingState(
        phase: TrackingPhase.active,
        tripId: 'live',
        tripStartedAt: 1000,
        permissions: _granted,
      ),
    );
    const limit = LiveLimitState(
      tripId: 'live',
      limitMps: 35 * 0.44704,
      posted: 35,
      unitLabel: 'mph',
      roadName: 'Elm St',
      confidence: 0.9,
      speedMps: 20.1168,
    );
    await tester.pumpWidget(harness(db, port, liveLimit: limit));
    await pumpFor(tester, const Duration(seconds: 1));

    port.emit(
      const PhaseEvent(
        tripId: 'live',
        t: 1000,
        phase: TripPhaseSignal.active,
        startedAt: 1000,
      ),
    );
    port.emit(
      const FixesEvent(
        tripId: 'live',
        t: 3000,
        fixes: [
          Fix(
            t: 1000,
            lat: 36.0,
            lon: -86.0,
            accuracy: 5,
            speed: 20.1168,
          ), // 45 mph
          Fix(t: 2000, lat: 36.0002, lon: -86.0, accuracy: 5, speed: 20.1168),
          Fix(t: 3000, lat: 36.0004, lon: -86.0, accuracy: 5, speed: 20.1168),
        ],
      ),
    );
    await pumpFor(tester, const Duration(seconds: 2));

    // The speed counts up to 45 in the capsule and in the live block.
    expect(find.text('45'), findsNWidgets(2));
    expect(find.text('Recording'), findsOneWidget);
    expect(find.byKey(const Key('live-limit')), findsOneWidget);
    expect(find.text('Limit 35 mph · Elm St'), findsOneWidget);
    expect(find.text('10 over the limit'), findsOneWidget);
    expect(find.text('End now'), findsNothing);
    expect(find.text('End drive'), findsOneWidget);
    // Recording peek: the live block is visible, the map stays the stage.
    expect(
      sheetTop(tester),
      closeTo(844 * (1 - DriveSheetSizes.peekRecording), 1),
    );
    // The recorder stored the batch.
    expect(await db.sampleCount('live'), 3);

    await tester.tap(find.text('End drive'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(port.calls, contains('forceEndTrip'));
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('the sheet snaps from the idle peek to the recording peek', (
    tester,
  ) async {
    phoneSize(tester);
    final now = DateTime.now();
    await seedAnsweredTrip(
      db,
      id: 'a',
      startedAt: now.subtract(const Duration(hours: 3)),
    );
    await seedAnsweredTrip(
      db,
      id: 'b',
      startedAt: now.subtract(const Duration(days: 1)),
      score: 64,
      headline: 'Three hard brakes. Give the car in front some room.',
    );
    port = FakeTrackingPort(state: const TrackingState(permissions: _granted));
    await tester.pumpWidget(harness(db, port));
    await pumpFor(tester, const Duration(seconds: 2));

    expect(find.text('LAST TRIP'), findsOneWidget);
    expect(find.text('Smooth. Keep it up.'), findsOneWidget);
    expect(sheetTop(tester), closeTo(844 * (1 - DriveSheetSizes.peekIdle), 1));

    // Dragging the sheet up reveals the recents (it snaps to half or full).
    await tester.drag(find.text('LAST TRIP'), const Offset(0, -500));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('RECENT'), findsOneWidget);
    expect(
      find.text('Three hard brakes. Give the car in front some room.'),
      findsOneWidget,
    );
    expect(sheetTop(tester), lessThan(844 * (1 - DriveSheetSizes.half) + 1));

    port.emit(
      PhaseEvent(
        tripId: 'live2',
        t: now.millisecondsSinceEpoch,
        phase: TripPhaseSignal.active,
        startedAt: now.millisecondsSinceEpoch,
      ),
    );
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byKey(const Key('live-block')), findsOneWidget);
    expect(
      sheetTop(tester),
      closeTo(844 * (1 - DriveSheetSizes.peekRecording), 1),
    );
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('an unanswered trip asks the passenger question as one tile', (
    tester,
  ) async {
    phoneSize(tester);
    await seedScoredTrip(
      db,
      id: 'p1',
      startedAt: DateTime.now()
          .subtract(const Duration(hours: 1))
          .millisecondsSinceEpoch,
      packRegion: 'us-tn',
    );
    port = FakeTrackingPort(state: const TrackingState(permissions: _granted));
    await tester.pumpWidget(harness(db, port));
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byKey(const Key('passenger-card')), findsOneWidget);
    expect(find.text('Were you the passenger?'), findsOneWidget);
    expect(find.text('Passenger'), findsOneWidget);
    expect(find.text('I drove'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);
}
