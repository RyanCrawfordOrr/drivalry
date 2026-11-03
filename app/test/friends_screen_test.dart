import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/friends/friends_screen.dart';
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
  setUp(() {
    db = memoryDatabase();
    port = FakeTrackingPort();
  });
  tearDown(() async {
    await port.dispose();
    await db.close();
  });

  testWidgets('without a cloud project the tab explains itself', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          trackingPortProvider.overrideWithValue(port),
          deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
        ],
        child: const MaterialApp(home: FriendsScreen()),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.widgetWithText(AppBar, 'Friends'), findsOneWidget);
    // Tests build without SUPABASE_URL, so SignedInScope shows the notice
    // and there is no Add-friend button.
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    expect(find.text('Add friend'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);
}
