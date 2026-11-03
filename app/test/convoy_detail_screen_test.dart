import 'dart:convert';

import 'package:drivalry/app/theme.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/repos/convoy_sync.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/convoy_detail_screen.dart';
import 'package:drivalry/features/convoy/widgets/convoy_ui.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

/// My convoy list, so the leader checks resolve without a cloud project.
class _Convoys extends MyConvoysNotifier {
  _Convoys(this.list);
  final List<Convoy> list;
  @override
  Future<List<Convoy>> build() async => list;
}

/// The convoy map screen: a status capsule floats over the map, the sheet
/// holds Talk, the leader's actions and the cars.
void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  final created = DateTime.utc(2026, 11, 3, 9);

  setUp(() async {
    Haptics.enabled = false;
    db = memoryDatabase();
    port = FakeTrackingPort();
    await db.cachePut(
      ConvoyRepo.membersKey('c1'),
      jsonEncode([
        for (final (id, name, role) in [
          ('me', 'Alex', 'leader'),
          ('sam', 'Sam', 'member'),
        ])
          ConvoyMember(
            userId: id,
            handle: name.toLowerCase(),
            displayName: name,
            role: role,
            joinedAt: created,
          ).toJson(),
      ]),
      1,
    );
  });
  tearDown(() async {
    await port.dispose();
    await db.close();
  });

  Convoy convoy(ConvoyStatus status) => Convoy(
    id: 'c1',
    name: 'Coast run',
    createdBy: 'me',
    status: status,
    inviteCode: 'coast42',
    createdAt: created,
    memberCount: 2,
    destination: const Destination(name: 'Pinecrest Lake', lat: 38, lon: -120),
  );

  Widget app(Convoy c) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      currentUserIdProvider.overrideWithValue('me'),
      myConvoysProvider.overrideWith(() => _Convoys([c])),
    ],
    child: MaterialApp(
      theme: DrivalryTheme.dark(),
      home: Scaffold(body: ConvoyDetailBody(convoy: c)),
    ),
  );

  testWidgets('active: capsule, Talk, leader actions and the cars', (
    tester,
  ) async {
    await tester.pumpWidget(app(convoy(ConvoyStatus.active)));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(FloatingCapsule), findsOneWidget);
    expect(find.text('On the road'), findsOneWidget);
    expect(find.text('2 of 6 cars'), findsOneWidget);
    final talk = find.widgetWithText(PrimaryButton, 'Talk');
    expect(talk, findsOneWidget);
    expect(tester.getSize(talk).height, Sizes.drivingTouch);
    expect(find.text('Regroup here'), findsOneWidget);
    // Pinecrest Lake is already set, so the second action moves it.
    expect(find.text('Move destination'), findsOneWidget);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);

    // Pull the sheet up to the cars.
    await tester.drag(find.byType(SheetHandle), const Offset(0, -400));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('CARS'), findsOneWidget);
    expect(find.text('You'), findsWidgets);
    expect(find.text('Sam'), findsWidgets);
    expect(find.textContaining('No position yet'), findsWidgets);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('planning: the leader starts the trip from the sheet', (
    tester,
  ) async {
    await tester.pumpWidget(app(convoy(ConvoyStatus.planning)));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Planning'), findsOneWidget);
    expect(find.byKey(const Key('start-convoy')), findsOneWidget);
    expect(find.text('Talk'), findsNothing);
    expect(find.text('Regroup here'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);
}
