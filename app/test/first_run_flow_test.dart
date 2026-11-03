import 'package:drivalry/app/theme.dart';
import 'package:drivalry/features/drive/first_run_flow.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/widget_support.dart';

const _granted = TrackingPermissions(
  location: LocationPermission.always,
  preciseLocation: true,
  motion: SimplePermission.granted,
);
const _locationOnly = TrackingPermissions(
  location: LocationPermission.always,
  preciseLocation: true,
  motion: SimplePermission.denied,
);

void main() {
  testWidgets(
    'three pages, one button each; a partial grant goes on to motion, '
    'a second refusal points at Settings',
    (tester) async {
      var requests = 0;
      var settings = 0;
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: DrivalryTheme.dark(),
          home: FirstRunFlow(
            permissions: const TrackingPermissions(),
            onRequest: () async {
              requests++;
              return _locationOnly;
            },
            onOpenSettings: () => settings++,
            onDone: () => done++,
          ),
        ),
      );
      await pumpFor(tester, const Duration(seconds: 1));

      expect(find.text('DRIVALRY'), findsOneWidget);
      expect(find.text('Every drive gets a score.'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Not now'), findsNothing);

      await tester.tap(find.text('Next'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('LOCATION'), findsOneWidget);
      expect(find.text('Allow location all the time.'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);

      await tester.tap(find.text('Allow'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(requests, 1);
      // Location landed, motion did not: on to the motion page.
      expect(done, 0);
      expect(find.text('MOTION'), findsOneWidget);
      expect(find.text('Allow motion.'), findsOneWidget);

      await tester.tap(find.text('Allow'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(requests, 2);
      expect(find.text('Open settings'), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      expect(settings, 1);

      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(done, 1);
    },
  );

  testWidgets('a full grant on the location page finishes the flow', (
    tester,
  ) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: DrivalryTheme.dark(),
        home: FirstRunFlow(
          permissions: const TrackingPermissions(),
          onRequest: () async => _granted,
          onOpenSettings: () {},
          onDone: () => done++,
        ),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Next'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Allow'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(done, 1);
  });

  testWidgets('the motion page reads Done once motion is allowed', (
    tester,
  ) async {
    var done = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: DrivalryTheme.dark(),
        home: FirstRunFlow(
          permissions: _granted,
          onRequest: () async => _granted,
          onOpenSettings: () {},
          onDone: () => done++,
        ),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Next'));
    await pumpFor(tester, const Duration(seconds: 1));
    // Swipe past location to see the motion page's confirmation.
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Allowed'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(done, 1);
  });
}
