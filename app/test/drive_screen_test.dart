import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/drive/drive_screen.dart';
import 'package:drivalry/features/drive/widgets/score_ring.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

Widget harness(AppDatabase db, FakeTrackingPort port) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(db),
    trackingPortProvider.overrideWithValue(port),
    deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
  ],
  child: const MaterialApp(home: DriveScreen()),
);

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

  testWidgets('idle without permissions shows the permission call to action', (
    tester,
  ) async {
    port = FakeTrackingPort(state: const TrackingState());
    await tester.pumpWidget(harness(db, port));
    await pumpFor(tester, const Duration(seconds: 1));

    expect(find.text('Let Drivalry detect your drives'), findsOneWidget);
    expect(find.textContaining('all the time'), findsWidgets);
    expect(find.text('No trips yet'), findsOneWidget);
    // The friends map card sits on top. Tests build without a cloud project,
    // so it explains itself instead of building a GoogleMap.
    expect(find.textContaining('friends map needs'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.people_outline), findsOneWidget);

    await tester.tap(find.text('Allow'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(port.calls, contains('requestPermissions'));
    // Permissions granted: now watching.
    expect(find.text('Watching for a drive'), findsOneWidget);
    expect(find.text('Start now'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets(
    'while-in-use location keeps the call to action and allows a manual start',
    (tester) async {
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
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('Let Drivalry detect your drives'), findsOneWidget);
      expect(find.text('Record a drive now'), findsOneWidget);
      await tester.tap(find.text('Record a drive now'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(port.calls, contains('forceStartTrip'));
      await unmountAndSettle(tester);
    },
    skip: skip,
  );

  testWidgets('a recording trip shows live speed and distance', (tester) async {
    port = FakeTrackingPort(
      state: const TrackingState(
        phase: TrackingPhase.active,
        tripId: 'live',
        tripStartedAt: 1000,
        permissions: TrackingPermissions(
          location: LocationPermission.always,
          preciseLocation: true,
          motion: SimplePermission.granted,
        ),
      ),
    );
    await tester.pumpWidget(harness(db, port));
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

    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
    expect(find.text('End now'), findsOneWidget);
    // The recorder stored the batch.
    expect(await db.sampleCount('live'), 3);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('score ring renders the number and the reckless stamp', (
    tester,
  ) async {
    port = FakeTrackingPort();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              ScoreRing(score: 87, label: '+70 XP'),
              ScoreRing(score: 12, reckless: true),
              ScoreRing(score: null, size: 56),
            ],
          ),
        ),
      ),
    );
    expect(find.text('87'), findsOneWidget);
    expect(find.text('+70 XP'), findsOneWidget);
    expect(find.text('RECKLESS'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });
}
