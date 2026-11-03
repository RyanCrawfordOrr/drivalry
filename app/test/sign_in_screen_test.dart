import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/supabase/auth_service.dart';
import 'package:drivalry/features/profile/sign_in_screen.dart';
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

  testWidgets('sign-in shows Apple and Google on iOS, Google only on Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      harness(
        const SignInScreen(cloudConfigured: true, googleConfigured: true),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('sign-in-apple')), findsOneWidget);
    expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
    expect(find.text(SignInScreen.privacyNote), findsOneWidget);
    expect(
      find.text('Score your drives. Beat your friends. Get roasted.'),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      harness(
        const SignInScreen(cloudConfigured: true, googleConfigured: true),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('sign-in-apple')), findsNothing);
    expect(find.byKey(const Key('sign-in-google')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('a version without sign-in says so in plain words', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const SignInScreen(cloudConfigured: false)),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('sign-in-google')), findsNothing);
    expect(find.text(SignInScreen.unavailableNote), findsOneWidget);
    expect(find.textContaining('cloud project'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('Not now pops the sign-in screen', (tester) async {
    await tester.pumpWidget(
      harness(
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SignInScreen(
                      cloudConfigured: true,
                      googleConfigured: true,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(SignInScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('sign-in-not-now')));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(SignInScreen), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  test('sign-in errors never mention configuration', () {
    expect(
      signInErrorText(
        const SignInFailure('Google sign-in is not configured for this build.'),
      ),
      SignInScreen.unavailableNote,
    );
    expect(
      signInErrorText(
        const SignInFailure(
          'This build has no Drivalry cloud project configured.',
        ),
      ),
      SignInScreen.unavailableNote,
    );
    expect(
      signInErrorText(
        const SignInFailure('New accounts are closed right now.'),
      ),
      'New accounts are closed right now.',
    );
    expect(
      signInErrorText(StateError('boom')),
      'Could not sign in. Try again.',
    );
  });
}
