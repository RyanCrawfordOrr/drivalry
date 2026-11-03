import 'package:drivalry/app/theme.dart';
import 'package:drivalry/features/cues/live_limit.dart';
import 'package:drivalry/features/drive/widgets/drive_status_capsule.dart';
import 'package:drivalry/features/drive/widgets/live_drive_block.dart';
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
  final now = DateTime.now().millisecondsSinceEpoch;
  final live = LiveTripStats(
    tripId: 't1',
    startedAt: now - 60_000,
    lastFixT: now,
    speedMps: 39 * 0.44704,
    distanceM: 1200,
  );
  final recording = TrackingUiState(
    plugin: const TrackingState(
      phase: TrackingPhase.active,
      tripId: 't1',
      permissions: granted,
    ),
    live: live,
    booted: true,
  );

  Widget harness(LiveLimitState? limit, {VoidCallback? onEnd}) => MaterialApp(
    theme: DrivalryTheme.dark(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: LiveDriveBlock(
          live: live,
          units: SpeedUnits.mph,
          liveLimit: limit,
          onEnd: onEnd ?? () {},
          nowMs: now,
        ),
      ),
    ),
  );

  testWidgets('the live block shows the speed, the limit and how far over', (
    tester,
  ) async {
    var ended = 0;
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
        onEnd: () => ended++,
      ),
    );
    // Numbers count up rather than jump.
    await tester.pump();
    expect(find.text('39'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('39'), findsOneWidget);
    expect(find.text('mph'), findsOneWidget);
    expect(find.text('Recording'), findsOneWidget);
    expect(find.byKey(const Key('live-limit')), findsOneWidget);
    expect(find.text('Limit 35 mph · Elm St'), findsOneWidget);
    expect(find.text('4 over the limit'), findsOneWidget);
    expect(find.text('0.7 mi'), findsOneWidget);
    expect(find.text('1 min'), findsOneWidget);

    final button = find.widgetWithText(FilledButton, 'End drive');
    expect(tester.getSize(button).height, 56);
    await tester.tap(button);
    expect(ended, 1);
  });

  testWidgets('no limit line without a usable limit', (tester) async {
    await tester.pumpWidget(harness(null));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('live-limit')), findsNothing);
    expect(find.textContaining('Scored when you park'), findsOneWidget);
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
    await tester.pump(const Duration(seconds: 1));
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
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Limit 45 mph'), findsOneWidget);
    expect(find.textContaining('over'), findsNothing);
  });

  group('status capsule', () {
    test('reads every state in a word or two', () {
      const ready = TrackingUiState(
        plugin: TrackingState(permissions: granted),
        booted: true,
      );
      expect(DriveStatusCapsule.statusText(ready), 'Ready');
      // The sentence the capsule has no room for goes in its sheet.
      expect(
        DriveStatusCapsule.statusDetail(ready),
        'Ready. Drives start on their own, even with the app closed.',
      );
      expect(
        DriveStatusCapsule.statusText(
          const TrackingUiState(plugin: TrackingState(), booted: true),
        ),
        'Set up auto-detect',
      );
      expect(
        DriveStatusCapsule.statusText(
          const TrackingUiState(
            plugin: TrackingState(enabled: false, permissions: granted),
          ),
        ),
        'Auto-detect off',
      );
      final until = DateTime(2026, 11, 3, 19);
      expect(
        DriveStatusCapsule.statusText(
          TrackingUiState(
            plugin: TrackingState(
              pausedUntil: until.millisecondsSinceEpoch,
              permissions: granted,
            ),
          ),
          nowMs: until.millisecondsSinceEpoch - 3_600_000,
        ),
        'Paused until 7 pm',
      );
      expect(
        DriveStatusCapsule.statusText(
          const TrackingUiState(
            plugin: TrackingState(
              phase: TrackingPhase.tentative,
              permissions: granted,
            ),
          ),
        ),
        'Checking…',
      );
      expect(
        DriveStatusCapsule.statusText(
          const TrackingUiState(plugin: TrackingState.unavailable()),
        ),
        'Auto-detect unavailable',
      );
      expect(DriveStatusCapsule.statusText(recording), isNull);
    });

    testWidgets('recording shows the speed in display with the limit beside', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: DrivalryTheme.dark(),
          home: Scaffold(
            body: Center(
              child: DriveStatusCapsule(
                state: recording,
                units: SpeedUnits.mph,
                liveLimit: const LiveLimitState(
                  tripId: 't1',
                  limitMps: 35 * 0.44704,
                  posted: 35,
                  unitLabel: 'mph',
                  confidence: 0.9,
                  speedMps: 39 * 0.44704,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('39'), findsOneWidget);
      expect(find.text('Limit 35'), findsOneWidget);
      final speed = tester.widget<Text>(find.text('39'));
      expect(speed.style?.fontSize, 64);
    });
  });
}
