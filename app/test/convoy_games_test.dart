import 'package:drivalry/features/convoy/radio/mesh_data_bus.dart';
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'dart:convert';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/audio/convoy_audio_session.dart';
import 'package:drivalry/features/convoy/games/convoy_games_screen.dart';
import 'package:drivalry/features/convoy/games/games_controller.dart';
import 'package:drivalry/features/convoy/positions/peer_positions.dart';
import 'package:drivalry/features/convoy/radio/data_bus.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
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
  late LoopbackDataBus bus;
  late RecordingSpeaker speaker;

  Widget harness() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      currentUserIdProvider.overrideWithValue('me'),
      convoyDataBusProvider.overrideWith((ref, id) => bus),
      speakerProvider.overrideWithValue(speaker),
    ],
    child: const MaterialApp(home: ConvoyGamesScreen(convoyId: 'c1')),
  );

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ConvoyGamesScreen)));

  setUp(() async {
    db = memoryDatabase();
    bus = LoopbackDataBus('me');
    speaker = RecordingSpeaker();
    // 'sam' is a known member: spoken results use the display name.
    await db.cachePut(
      ConvoyRepo.membersKey('c1'),
      jsonEncode([
        ConvoyMember(
          userId: 'sam',
          handle: 'sam',
          displayName: 'Sam',
          role: 'member',
          joinedAt: DateTime.utc(2026, 11, 3),
        ).toJson(),
      ]),
      1,
    );
  });
  tearDown(() async {
    await port.dispose();
    bus.dispose();
    await db.close();
  });

  testWidgets('drivers are gated out and told why', (tester) async {
    port = FakeTrackingPort(
      state: const TrackingState(phase: TrackingPhase.active, tripId: 'live'),
    );
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('driver-gate')), findsOneWidget);
    expect(
      find.text('Games are for passengers. Drivers hear the results.'),
      findsOneWidget,
    );
    expect(find.text('Plates'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('license-plate bingo marks locally and broadcasts', (
    tester,
  ) async {
    port = FakeTrackingPort(state: const TrackingState());
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Plates'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plate-AL')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(bus.sent.last.type, 'game');
    expect(bus.sent.last.payload, {
      'game': 'plates',
      'event': 'mark',
      'state': ['AL'],
    });
    expect(find.text('me: 1'), findsOneWidget);

    bus.inject('sam', 'game', {
      'game': 'plates',
      'event': 'mark',
      'state': ['CA', 'TX'],
    });
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('sam: 2'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('a trivia round ends with the result spoken for drivers', (
    tester,
  ) async {
    port = FakeTrackingPort(state: const TrackingState());
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.text('Trivia'));
    await pumpFor(tester, const Duration(seconds: 1));
    // Alone in the mesh I am the lowest id, so I host.
    expect(find.text('You are asking the questions.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('next-question')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const Key('choice-0')), findsOneWidget);
    expect(find.text('0 answered'), findsOneWidget);
    expect(bus.sent.last.payload['event'], 'question');

    await tester.tap(find.byKey(const Key('choice-0')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('1 answered'), findsOneWidget);
    expect(bus.sent.last.payload['event'], 'answer');

    final c = container(tester).read(gamesControllerProvider('c1').notifier);
    final right = c.trivia.current!.answer;
    bus.inject('sam', 'game', {
      'game': 'trivia',
      'event': 'answer',
      'index': c.trivia.currentIndex,
      'choice': right,
    });
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('2 answered'), findsOneWidget);

    await tester.tap(find.text('Reveal now'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    final answer = c.trivia.current!.choices[right];
    expect(speaker.spoken, hasLength(1));
    expect(speaker.spoken.single, endsWith('got it: $answer.'));
    expect(speaker.spoken.single, startsWith('Sam'), reason: 'name, not id');
    expect(find.byKey(const Key('last-result')), findsOneWidget);
    expect(find.text('Scores'), findsOneWidget);
    expect(find.text('sam: 1'), findsOneWidget);
    expect(bus.sent.last.payload['event'], 'reveal');
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('scavenger claims are first-come and announced', (tester) async {
    port = FakeTrackingPort(state: const TrackingState());
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.text('Spot the…'));
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('spot-Red barn')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(bus.sent.last.payload['game'], 'scavenger');
    expect(bus.sent.last.payload['item'], 'Red barn');
    expect(find.text('You spotted Red barn'), findsOneWidget);
    expect(find.text('Spotted by me'), findsOneWidget);

    bus.inject('sam', 'game', {
      'game': 'scavenger',
      'event': 'claim',
      'item': 'Horse',
      't': 1,
    });
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Sam spotted Horse'), findsOneWidget);

    // An unknown car is "Someone", never a UUID prefix.
    bus.inject('9f3c2a7e-0000-4000-8000-000000000000', 'game', {
      'game': 'scavenger',
      'event': 'claim',
      'item': 'Water tower',
      't': 2,
    });
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Someone spotted Water tower'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  test(
    'games follow the data bus when the radio starts, boards intact',
    () async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue('me'),
          speakerProvider.overrideWithValue(speaker),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(gamesControllerProvider('c1'), (_, _) {});
      addTearDown(sub.close);
      final c = container.read(gamesControllerProvider('c1').notifier);
      c.togglePlate('CA');
      expect(c.plates.mine, {'CA'});
      expect(container.read(gamesControllerProvider('c1')).peers, isEmpty);

      container.read(radioBusRegistryProvider.notifier).register('c1', bus);
      bus.connect('sam');
      await Future<void>.delayed(Duration.zero);
      expect(
        identical(container.read(gamesControllerProvider('c1').notifier), c),
        isTrue,
        reason: 'no rebuild',
      );
      expect(c.plates.mine, {'CA'}, reason: 'the board survives the swap');
      expect(container.read(gamesControllerProvider('c1')).peers, {'sam'});
      c.togglePlate('TX');
      expect(bus.sent.last.payload['game'], 'plates', reason: 'sends use it');
    },
    skip: skip,
  );

  testWidgets('smoothest leg ranks steadiness from peer positions', (
    tester,
  ) async {
    port = FakeTrackingPort(state: const TrackingState());
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));

    final hub = container(tester).read(peerPositionHubProvider('c1'));
    for (var i = 0; i < 6; i++) {
      hub.push(
        PeerPosition(
          userId: 'sam',
          t: i * 1000,
          lat: 0,
          lon: 0,
          speed: 25 + (i.isEven ? 0.1 : -0.1),
          source: PositionSource.mesh,
        ),
      );
      hub.push(
        PeerPosition(
          userId: 'eve',
          t: i * 1000,
          lat: 0,
          lon: 0,
          speed: 8 + (i.isEven ? 7.0 : -7.0),
          source: PositionSource.mesh,
        ),
      );
    }
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Smoothest'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Glassy'), findsOneWidget);
    expect(find.text('Choppy'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('sam')).dy,
      lessThan(tester.getTopLeft(find.text('eve')).dy),
    );
    // No speed figure is ever shown.
    expect(find.textContaining('25'), findsNothing);
    await unmountAndSettle(tester);
  }, skip: skip);
}
