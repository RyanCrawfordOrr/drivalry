import 'dart:async';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/channel/convoy_channel.dart';
import 'package:drivalry/features/convoy/radio/convoy_radio_screen.dart';
import 'package:drivalry/features/convoy/radio/data_bus.dart';
import 'package:drivalry/features/convoy/radio/mesh_data_bus.dart';
import 'package:drivalry/features/convoy/radio/peer_link.dart';
import 'package:drivalry/features/convoy/radio/radio_controller.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/radio_fakes.dart';
import 'support/sqlite_support.dart';

/// The native audio session: counts start/stop and can report that the
/// platform ended the session (Stop on the Android notification).
class _FakeHook implements ConvoyAudioSessionHook {
  int starts = 0;
  int stops = 0;
  final _stopped = StreamController<void>.broadcast();
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async => stops++;
  @override
  Stream<void> get stopped => _stopped.stream;
  void emitStopped() => _stopped.add(null);
}

void main() {
  final skip = skipWithoutSqlite();
  late AppDatabase db;
  late FakeConvoyChannel channel;
  late FakePeerLinkFactory factory;
  late FakeLocalAudio audio;
  late MicPermission permission;
  late ProviderContainer container;

  ProviderContainer makeContainer({ConvoyAudioSessionHook? hook}) =>
      ProviderContainer(
        overrides: [
          if (hook != null)
            convoyAudioSessionHookProvider.overrideWithValue(hook),
          databaseProvider.overrideWithValue(db),
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response('', 500)),
          ),
          currentUserIdProvider.overrideWithValue('me'),
          convoyChannelProvider.overrideWith(
            (ref, id) => id == 'c1' ? channel : null,
          ),
          radioDepsProvider.overrideWithValue(
            RadioDeps(
              linkFactory: factory,
              newAudio: () => audio,
              requestMicrophone: () async => permission,
            ),
          ),
        ],
      );

  setUp(() {
    db = memoryDatabase();
    channel = FakeConvoyChannel('c1', present: {'me', 'zed'});
    factory = FakePeerLinkFactory();
    audio = FakeLocalAudio();
    permission = MicPermission.granted;
    container = makeContainer();
  });

  tearDown(() async {
    container.dispose();
    channel.dispose();
    await db.close();
  });

  Widget app() => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: Scaffold(body: RadioBody(convoyId: 'c1')),
    ),
  );

  testWidgets(
    'start joins the mesh, registers the bus; PTT and stop work',
    (tester) async {
      await tester.pumpWidget(app());
      expect(find.text('Radio is off'), findsOneWidget);
      expect(container.read(convoyDataBusProvider('c1')), isA<NoopDataBus>());

      await tester.tap(find.byKey(const Key('radio-start')));
      await tester.pump();
      await tester.pump();
      expect(channel.joins, 1);
      expect(channel.sentTypes(), contains('hello'));
      expect(audio.acquired, isTrue);
      expect(audio.muted, isTrue, reason: 'mic stays muted until held');
      expect(container.read(convoyDataBusProvider('c1')), isA<MeshDataBus>());
      expect(find.text('Hold to talk'), findsOneWidget);
      expect(find.textContaining('No relay configured'), findsOneWidget);

      // 'zed' is present: lower id 'me' offers.
      expect(factory.links['zed']!.offerer, isTrue);
      factory.links['zed']!.emit(const LinkStateChanged(LinkState.connected));
      factory.links['zed']!.emit(const LinkDataOpen());
      // The fake link's events and the mesh's peer stream are both async, so
      // the state lands after the first pump decided no frame was due.
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Direct'), findsOneWidget);

      // Hold to talk.
      final gesture = await tester.press(find.byKey(const Key('ptt-button')));
      await tester.pump();
      expect(audio.muted, isFalse);
      expect(find.text('Transmitting'), findsOneWidget);
      expect(channel.sent.last.type, 'ptt');
      await gesture.up();
      await tester.pump();
      expect(audio.muted, isTrue);
      expect(find.text('Hold to talk'), findsOneWidget);

      // Someone else talks.
      channel.inject('ptt', 'zed', payload: {'on': true});
      await tester.pump();
      expect(find.text('Someone is talking'), findsOneWidget);

      // Mute everyone propagates to links.
      await tester.tap(find.byKey(const Key('radio-mute-incoming')));
      await tester.pump();
      expect(factory.links['zed']!.incomingMutedValue, isTrue);

      // With a peer tile shown the stop button sits below the test viewport.
      await tester.ensureVisible(find.byKey(const Key('radio-stop')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('radio-stop')));
      await tester.pump();
      await tester.pump();
      expect(channel.sentTypes(), contains('bye'));
      expect(channel.leaves, 1);
      expect(audio.releases, 1);
      expect(factory.links['zed']!.closed, isTrue);
      expect(container.read(convoyDataBusProvider('c1')), isA<NoopDataBus>());
      expect(find.text('Radio is off'), findsOneWidget);
    },
    skip: skip != null,
  );

  testWidgets('Stop on the Android notification ends the radio', (
    tester,
  ) async {
    final hook = _FakeHook();
    container.dispose();
    container = makeContainer(hook: hook);
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('radio-start')));
    await tester.pump();
    await tester.pump();
    expect(hook.starts, 1);
    expect(find.text('Hold to talk'), findsOneWidget);

    hook.emitStopped();
    await tester.pump();
    await tester.pump();
    expect(find.text('Radio is off'), findsOneWidget);
    expect(hook.stops, 1);
    expect(audio.releases, 1);
    expect(channel.sentTypes(), contains('bye'));
    expect(channel.leaves, 1);
    expect(container.read(convoyDataBusProvider('c1')), isA<NoopDataBus>());
  }, skip: skip != null);

  testWidgets('a denied microphone explains and offers a retry', (
    tester,
  ) async {
    permission = MicPermission.denied;
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const Key('radio-start')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Microphone needed'), findsOneWidget);
    expect(find.byKey(const Key('radio-retry')), findsOneWidget);
    expect(channel.joins, 0);
    expect(audio.acquired, isFalse);

    permission = MicPermission.permanentlyDenied;
    await tester.tap(find.byKey(const Key('radio-retry')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('radio-open-settings')), findsOneWidget);
  }, skip: skip != null);

  test('disposing the container while on tears the session down', () async {
    final ctl = container.read(radioControllerProvider('c1').notifier);
    await ctl.start();
    expect(container.read(radioControllerProvider('c1')).on, isTrue);
    container.dispose();
    await settle();
    expect(channel.leaves, 1);
    expect(audio.releases, 1);
    // tearDown disposes again; make that a no-op.
    container = ProviderContainer();
  }, skip: skip);
}
