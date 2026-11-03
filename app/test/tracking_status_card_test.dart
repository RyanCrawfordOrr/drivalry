import 'package:drivalry/features/cues/live_limit.dart';
import 'package:drivalry/features/drive/widgets/tracking_status_card.dart';
import 'package:drivalry/tracking/tracking_controller.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const granted = TrackingPermissions(
    location: LocationPermission.always,
    preciseLocation: true,
    motion: SimplePermission.granted,
    notifications: SimplePermission.granted,
    bluetooth: SimplePermission.granted,
  );
  final recording = TrackingUiState(
    plugin: const TrackingState(
      phase: TrackingPhase.active,
      tripId: 't1',
      permissions: granted,
    ),
    live: LiveTripStats(
      tripId: 't1',
      startedAt: DateTime.now().millisecondsSinceEpoch - 60_000,
      speedMps: 39 * 0.44704,
      distanceM: 1200,
    ),
    booted: true,
  );

  Widget harness(LiveLimitState? limit) => MaterialApp(
    home: Scaffold(
      body: TrackingStatusCard(
        state: recording,
        units: SpeedUnits.mph,
        liveLimit: limit,
        onRequestPermissions: () {},
        onOpenSettings: () {},
        onSetEnabled: (_) {},
        onPause: (_) {},
        onPauseUntilTomorrow: () {},
        onResume: () {},
        onStartNow: () {},
        onEndNow: () {},
      ),
    ),
  );

  testWidgets('recording card shows the live limit and how far over', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const LiveLimitState(
          tripId: 't1',
          limitMps: 35 * 0.44704,
          posted: 35,
          unitLabel: 'mph',
          roadName: 'Elm St',
          confidence: 0.9,
          speedMps: 39 * 0.44704,
        ),
      ),
    );
    expect(find.text('Recording'), findsOneWidget);
    expect(find.byKey(const Key('live-limit')), findsOneWidget);
    expect(find.text('Limit 35 mph · Elm St'), findsOneWidget);
    expect(find.text('4 over'), findsOneWidget);
  });

  testWidgets('no line without a usable limit', (tester) async {
    await tester.pumpWidget(harness(null));
    expect(find.byKey(const Key('live-limit')), findsNothing);
    await tester.pumpWidget(
      harness(
        const LiveLimitState(
          tripId: 't1',
          limitMps: 35 * 0.44704,
          posted: 35,
          confidence: 0.5,
          speedMps: 20,
        ),
      ),
    );
    expect(find.byKey(const Key('live-limit')), findsNothing);
  });

  testWidgets('at or under the limit shows no over count', (tester) async {
    await tester.pumpWidget(
      harness(
        const LiveLimitState(
          tripId: 't1',
          limitMps: 45 * 0.44704,
          posted: 45,
          unitLabel: 'mph',
          confidence: 0.9,
          speedMps: 39 * 0.44704,
        ),
      ),
    );
    expect(find.text('Limit 45 mph'), findsOneWidget);
    expect(find.textContaining('over'), findsNothing);
  });
}
