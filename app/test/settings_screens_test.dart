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

  testWidgets('units segment writes the setting', (tester) async {
    await tester.pumpWidget(harness(const SettingsScreen()));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Offline build'), findsOneWidget);
    expect(find.byKey(const Key('units-segments')), findsOneWidget);

    await tester.tap(find.text('km/h'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(await db.getSetting('units'), 'kmh');

    await tester.tap(find.text('mph'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(await db.getSetting('units'), 'mph');

    // Hiding needs a signed-in profile.
    final hide = tester.widget<SwitchListTile>(
      find.byKey(const Key('hide-location')),
    );
    expect(hide.onChanged, isNull);
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

  testWidgets('attribution lists the data sources', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AttributionScreen()));
    await tester.pump();
    for (final name in [
      'OpenStreetMap',
      'Google Maps Platform',
      'Open-Meteo',
      'Nominatim',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
  });
}
