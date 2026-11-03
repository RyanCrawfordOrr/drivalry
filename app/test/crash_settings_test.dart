import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/crash/crash_monitor.dart';
import 'package:drivalry/data/crash/crash_speaker.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/crash/crash_countdown_screen.dart';
import 'package:drivalry/features/settings/crash_settings_screen.dart';
import 'package:drivalry/features/settings/emergency_contacts_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

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

  testWidgets('crash settings toggle writes the setting', (tester) async {
    await tester.pumpWidget(harness(const CrashSettingsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byKey(const Key('crash-enabled')), findsOneWidget);
    expect(
      find.text('None yet. Add at least one so the text has somewhere to go.'),
      findsOneWidget,
    );
    // The false-alarm counter is a stat tile, the explainer two sentences.
    expect(find.byType(StatTile), findsNWidgets(2));
    expect(find.text('False alarms'), findsOneWidget);
    expect(find.text('Never'), findsOneWidget);

    await tester.tap(find.byKey(const Key('crash-enabled')));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(await db.getSetting(CrashKeys.enabled), 'false');

    await tester.tap(find.byKey(const Key('crash-enabled')));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(await db.getSetting(CrashKeys.enabled), 'true');
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('emergency contacts can be added and removed', (tester) async {
    await tester.pumpWidget(harness(const EmergencyContactsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Who should get the text?'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Add contact'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.enterText(find.byKey(const Key('contact-name')), 'Sam');
    await tester.enterText(
      find.byKey(const Key('contact-phone')),
      '+1 (555) 010-2020',
    );
    await tester.tap(find.byKey(const Key('contact-save')));
    await pumpFor(tester, const Duration(milliseconds: 800));

    final rows = await db.allEmergencyContacts();
    expect(rows.length, 1);
    expect(rows.single.name, 'Sam');
    expect(rows.single.phone, '+15550102020');
    expect(find.text('Sam'), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
    expect(find.byKey(const Key('contact-add')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(await db.allEmergencyContacts(), isEmpty);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect((await db.allEmergencyContacts()).single.name, 'Sam');
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets(
    'test countdown runs on screen and "I\'m OK" ends it without sending',
    (tester) async {
      await tester.pumpWidget(harness(const CrashCountdownScreen()));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('No crash detected.'), findsOneWidget);

      final element = tester.element(find.byType(CrashCountdownScreen));
      final container = ProviderScope.containerOf(element);
      container.read(crashMonitorProvider.notifier).startTest();
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('TEST: nothing will be sent'), findsOneWidget);
      expect(find.byKey(const Key('crash-im-ok')), findsOneWidget);
      expect(navigated, ['/crash']);

      // The in-car sizes are the reference for the whole app.
      expect(tester.getSize(find.byKey(const Key('crash-im-ok'))).height, 96);
      expect(
        tester.getSize(find.byKey(const Key('crash-send-help'))).height,
        56,
      );

      // Twelve seconds pass.
      now += 12_000;
      await pumpFor(tester, const Duration(seconds: 12));
      expect(find.text('18'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crash-im-ok')));
      await pumpFor(tester, const Duration(milliseconds: 500));
      final state = container.read(crashMonitorProvider);
      expect(state.countingDown, isFalse);
      expect(state.unresolved, isNull);
      // A test run is not a false positive.
      expect(await db.getSetting(CrashKeys.falsePositives), isNull);
      await unmountAndSettle(tester);
    },
    skip: skip,
  );
}
