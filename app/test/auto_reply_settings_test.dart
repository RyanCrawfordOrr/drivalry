import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/settings/auto_reply_settings_screen.dart';
import 'package:drivalry/features/settings/settings_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/foundation.dart';
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

  setUp(() {
    db = memoryDatabase();
    port = FakeTrackingPort();
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await port.dispose();
    await db.close();
  });

  Widget harness(Widget home) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
    ],
    child: MaterialApp(home: home),
  );

  testWidgets('Settings lists the row under Safety', (tester) async {
    await tester.pumpWidget(harness(const SettingsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 300));
    // The row sits below the fold of the settings list.
    await tester.scrollUntilVisible(
      find.byKey(const Key('auto-reply')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.byKey(const Key('auto-reply')), findsOneWidget);
    expect(find.text('Auto-reply to texts'), findsOneWidget);
    expect(find.text('SAFETY'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('Android: the button asks the plugin to open DND settings', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(harness(const AutoReplySettingsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.textContaining('Drivalry never sends replies'), findsOneWidget);
    expect(find.byKey(const Key('auto-reply-copy')), findsNothing);
    expect(find.byType(PrimaryButton), findsOneWidget);

    await tester.tap(find.byKey(const Key('auto-reply-open')));
    await tester.pump();
    expect(port.calls, contains('openDrivingModeSettings'));
    expect(find.textContaining('Could not open it'), findsNothing);

    // When nothing resolves, say where to look instead.
    port.drivingModeSettingsOpens = false;
    await tester.tap(find.byKey(const Key('auto-reply-open')));
    await tester.pump();
    expect(find.textContaining('Could not open it here'), findsOneWidget);
    await unmountAndSettle(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS: numbered steps to a Driving Focus and a copy button', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(harness(const AutoReplySettingsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('DRIVING FOCUS'), findsOneWidget);
    for (var i = 0; i < AutoReplySettingsScreen.iosSteps.length; i++) {
      expect(find.text(AutoReplySettingsScreen.iosSteps[i]), findsOneWidget);
      expect(find.text('${i + 1}'), findsOneWidget);
    }
    // The step numerals are the 32 px display face.
    final numeral = tester.widget<Text>(find.text('1'));
    expect(numeral.style?.fontSize, 32);
    expect(find.byKey(const Key('auto-reply-open')), findsNothing);
    expect(find.byKey(const Key('auto-reply-copy')), findsOneWidget);
    expect(port.calls, isNot(contains('openDrivingModeSettings')));
    await unmountAndSettle(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
