import 'package:drivalry/data/crash/crash_monitor.dart';
import 'package:drivalry/data/crash/crash_speaker.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/crash/crash_countdown_screen.dart';
import 'package:drivalry/features/crash/crash_status_card.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

/// The crash controls must always be reachable: the Drive-tab card shows the
/// running countdown, and the countdown screen cannot be swiped away.
void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  late List<String> navigated;
  var now = 1_000_000;

  setUp(() {
    db = memoryDatabase();
    port = FakeTrackingPort();
    navigated = [];
    now = 1_000_000;
  });
  tearDown(() async {
    await port.dispose();
    await db.close();
  });

  Widget harness(Widget home) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      crashSpeakerProvider.overrideWithValue(const SilentCrashSpeaker()),
      crashMonitorConfigProvider.overrideWithValue(
        CrashMonitorConfig(
          now: () => now,
          navigate: navigated.add,
          haptics: false,
          lifecycle: () => AppLifecycleState.resumed,
        ),
      ),
    ],
    child: MaterialApp(home: home),
  );

  CrashCandidateEvent candidate() => CrashCandidateEvent(
    tripId: 'c1',
    t: now,
    peakMps2: 45,
    speedBeforeMps: 15,
    lat: 38.9,
    lon: -77.0,
    accuracy: 10,
  );

  testWidgets(
    'the Drive-tab card shows the running countdown with an I\'m OK button',
    (tester) async {
      await tester.pumpWidget(harness(const Scaffold(body: CrashStatusCard())));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.byType(Card), findsNothing);

      final element = tester.element(find.byType(CrashStatusCard));
      final container = ProviderScope.containerOf(element);
      await container
          .read(crashMonitorProvider.notifier)
          .onCandidate(candidate());
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('Possible crash: countdown running'), findsOneWidget);
      expect(find.byKey(const Key('crash-card-im-ok')), findsOneWidget);
      expect(find.byKey(const Key('crash-card-show')), findsOneWidget);

      await tester.tap(find.byKey(const Key('crash-card-im-ok')));
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(container.read(crashMonitorProvider).countingDown, isFalse);
      expect(find.text('Possible crash: countdown running'), findsNothing);
      await unmountAndSettle(tester);
    },
    skip: skip,
  );

  testWidgets('the countdown screen ignores back while counting down', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const Scaffold(body: Text('home'))));
    await pumpFor(tester, const Duration(milliseconds: 200));
    final home = tester.element(find.text('home'));
    final container = ProviderScope.containerOf(home);
    Navigator.of(home).push(
      MaterialPageRoute<void>(builder: (_) => const CrashCountdownScreen()),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    container.read(crashMonitorProvider.notifier).startTest();
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const Key('crash-im-ok')), findsOneWidget);

    // maybePop reports "handled" (true) when a PopScope vetoes the pop, so
    // the proof is that the screen is still on top afterwards.
    final nav = Navigator.of(tester.element(find.byType(CrashCountdownScreen)));
    await nav.maybePop();
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byType(CrashCountdownScreen), findsOneWidget);
    expect(find.text('home'), findsNothing);

    await tester.tap(find.byKey(const Key('crash-im-ok')));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(container.read(crashMonitorProvider).countingDown, isFalse);
    await unmountAndSettle(tester);
  }, skip: skip);
}
