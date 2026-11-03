import 'dart:convert';

import 'package:drivalry/app/theme.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/repos/convoy_sync.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/convoy_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

/// My convoy list as a signed-in session would hold it (without a cloud
/// project the real notifier's refresh would replace the cache with nothing).
class _Convoys extends MyConvoysNotifier {
  _Convoys(this.list);
  final List<Convoy> list;
  @override
  Future<List<Convoy>> build() async => list;
}

/// The Convoy tab's three states (docs/12 §7): nothing yet, an active convoy
/// as the hero with Talk and five doors, and past trips as rows.
void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  late List<Convoy> convoys;
  final created = DateTime.utc(2026, 11, 3, 9);

  setUp(() {
    Haptics.enabled = false;
    db = memoryDatabase();
    port = FakeTrackingPort();
    convoys = const [];
  });
  tearDown(() async {
    await port.dispose();
    await db.close();
  });

  Convoy convoy(String id, String name, ConvoyStatus status) => Convoy(
    id: id,
    name: name,
    createdBy: 'leader',
    status: status,
    inviteCode: 'abc12345',
    createdAt: created,
    startedAt: status == ConvoyStatus.planning ? null : created,
    endedAt: status == ConvoyStatus.ended ? created : null,
    memberCount: 3,
    destination: const Destination(name: 'Pinecrest Lake', lat: 38, lon: -120),
  );

  ConvoyMember member(String id, String name) => ConvoyMember(
    userId: id,
    handle: name.toLowerCase(),
    displayName: name,
    role: id == 'leader' ? 'leader' : 'member',
    joinedAt: created,
  );

  Future<void> seed(List<Convoy> list) async {
    convoys = list;
    for (final c in list) {
      await db.cachePut(
        ConvoyRepo.membersKey(c.id),
        jsonEncode([
          member('me', 'Alex').toJson(),
          member('leader', 'Sam').toJson(),
          member('priya', 'Priya').toJson(),
        ]),
        1,
      );
    }
  }

  Widget app({String me = 'me'}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      currentUserIdProvider.overrideWithValue(me),
      myConvoysProvider.overrideWith(() => _Convoys(convoys)),
    ],
    child: MaterialApp(
      theme: DrivalryTheme.dark(),
      home: const Scaffold(body: ConvoyHubBody()),
    ),
  );

  testWidgets('with no convoy the hub invites you to start or join', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Road trips, together.'), findsOneWidget);
    expect(find.text('Start a convoy'), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.text('Talk'), findsNothing);
    expect(find.text('PAST TRIPS'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('an active convoy is the hero with Talk and five doors', (
    tester,
  ) async {
    await seed([convoy('c1', 'Coast run', ConvoyStatus.active)]);
    await tester.pumpWidget(app());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Coast run'), findsOneWidget);
    expect(find.textContaining('to Pinecrest Lake'), findsOneWidget);
    expect(find.text('On the road'), findsOneWidget);
    // Live state breathes.
    expect(find.byType(PulsingDot), findsOneWidget);
    expect(find.text('3 cars'), findsOneWidget);
    // The one in-car action is 64 tall and full width.
    final talk = find.widgetWithText(PrimaryButton, 'Talk');
    expect(talk, findsOneWidget);
    expect(tester.getSize(talk).height, Sizes.drivingTouch);
    for (final door in ['Map', 'Stops', 'Chat', 'Music', 'Games']) {
      expect(find.text(door), findsOneWidget, reason: door);
    }
    expect(find.text('3 of 6 cars'), findsOneWidget);
    expect(find.text('Nothing proposed yet'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Recap'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MORE'), findsOneWidget);
    expect(find.text('Album'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Road trips, together.'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('a planning convoy gives the leader Start trip', (tester) async {
    await seed([convoy('c1', 'Night run', ConvoyStatus.planning)]);
    await tester.pumpWidget(app(me: 'leader'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Planning'), findsOneWidget);
    expect(find.byKey(const Key('start-convoy')), findsOneWidget);
    expect(find.text('Talk'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('past convoys are rows under Past trips', (tester) async {
    await seed([convoy('c9', 'Desert loop', ConvoyStatus.ended)]);
    await tester.pumpWidget(app());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Road trips, together.'), findsOneWidget);
    expect(find.text('PAST TRIPS'), findsOneWidget);
    expect(find.text('Desert loop'), findsOneWidget);
    expect(find.textContaining('Ended'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);
}
