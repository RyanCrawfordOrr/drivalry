import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/profile/sign_in_screen.dart';
import 'package:drivalry/features/settings/attribution_screen.dart';
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

  Switch switchIn(WidgetTester tester, Key key) => tester.widget<Switch>(
    find.descendant(of: find.byKey(key), matching: find.byType(Switch)),
  );

  testWidgets('units segment writes the setting', (tester) async {
    await tester.pumpWidget(harness(const SettingsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('DRIVES'), findsOneWidget);
    expect(find.byKey(const Key('units-segments')), findsOneWidget);

    await tester.tap(find.text('km/h'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(await db.getSetting('units'), 'kmh');

    await tester.tap(find.text('mph'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(await db.getSetting('units'), 'mph');

    // Hiding needs a signed-in profile.
    expect(switchIn(tester, const Key('hide-location')).onChanged, isNull);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('a version without the online service says so plainly', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const SettingsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(
      find.text('Not available in this version yet.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    expect(find.text('Offline build'), findsNothing);
    expect(find.textContaining('cloud project'), findsNothing);
    expect(find.textContaining('JSON'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('turning auto-detect off offers Undo', (tester) async {
    await tester.pumpWidget(harness(const SettingsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(switchIn(tester, const Key('auto-detect')).value, isTrue);

    await tester.tap(find.byKey(const Key('auto-detect')));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(port.calls, contains('setEnabled:false'));
    expect(switchIn(tester, const Key('auto-detect')).value, isFalse);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(port.calls.last, 'setEnabled:true');
    expect(switchIn(tester, const Key('auto-detect')).value, isTrue);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('sign-in shows Apple and Google on iOS, Google only on Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(harness(const SignInScreen(cloudConfigured: true)));
    await tester.pump();
    expect(find.byKey(const Key('sign-in-apple')), findsOneWidget);
    expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
    expect(find.text(SignInScreen.privacyNote), findsOneWidget);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(harness(const SignInScreen(cloudConfigured: true)));
    await tester.pump();
    expect(find.byKey(const Key('sign-in-apple')), findsNothing);
    expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('sign-in explains an offline build', (tester) async {
    await tester.pumpWidget(
      harness(const SignInScreen(cloudConfigured: false)),
    );
    await tester.pump();
    expect(find.byKey(const Key('sign-in-google')), findsNothing);
    expect(find.textContaining('no Drivalry cloud project'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('about lists the data sources with one sentence each', (
    tester,
  ) async {
    // Tall enough that every section is on screen at once.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AttributionScreen()));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text('Drivalry'), findsOneWidget);
    expect(
      find.text('Free, open source, built on free services.'),
      findsOneWidget,
    );
    for (final (name, sentence, _, _) in AttributionScreen.entries) {
      expect(find.text(name.toUpperCase()), findsOneWidget);
      expect(find.text(sentence), findsOneWidget);
    }
    expect(find.textContaining('SDK'), findsNothing);
    expect(find.textContaining('API'), findsNothing);
  });
}
