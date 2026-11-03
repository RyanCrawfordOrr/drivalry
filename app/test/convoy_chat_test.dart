import 'dart:convert';
import 'dart:typed_data';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/audio/convoy_audio_session.dart';
import 'package:drivalry/features/convoy/channel/convoy_channel.dart';
import 'package:drivalry/features/convoy/chat/chat_controller.dart';
import 'package:drivalry/features/convoy/chat/convoy_chat_screen.dart';
import 'package:drivalry/features/convoy/chat/voice_notes.dart';
import 'package:drivalry/features/convoy/radio/data_bus.dart';
import 'package:drivalry/features/convoy/radio/mesh_data_bus.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_tracking_port.dart';
import 'support/radio_fakes.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

class FakeRecorder implements VoiceRecorder {
  bool permission = true;
  Uint8List? result = Uint8List.fromList(List.filled(3000, 7));
  final calls = <String>[];

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<Uint8List?> stop() async {
    calls.add('stop');
    return result;
  }

  @override
  Future<void> dispose() async {}
}

class FakePlayer implements VoicePlayer {
  final played = <int>[];

  @override
  Future<void> play(Uint8List bytes, String mimeType) async =>
      played.add(bytes.length);
}

void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeTrackingPort port;
  late FakeConvoyChannel channel;
  late LoopbackDataBus bus;
  late RecordingSpeaker speaker;
  late FakePlayer player;
  late FakeRecorder recorder;

  Widget harness() => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      currentUserIdProvider.overrideWithValue('me'),
      convoyChannelProvider.overrideWith((ref, id) => channel),
      convoyDataBusProvider.overrideWith((ref, id) => bus),
      speakerProvider.overrideWithValue(speaker),
      voicePlayerProvider.overrideWithValue(player),
      voiceRecorderProvider.overrideWithValue(recorder),
    ],
    child: const MaterialApp(home: ConvoyChatScreen(convoyId: 'c1')),
  );

  setUp(() {
    db = memoryDatabase();
    channel = FakeConvoyChannel('c1');
    bus = LoopbackDataBus('me');
    speaker = RecordingSpeaker();
    player = FakePlayer();
    recorder = FakeRecorder();
  });
  tearDown(() async {
    await port.dispose();
    channel.dispose();
    bus.dispose();
    await db.close();
  });

  testWidgets('drivers get the banner, hear text and auto-play notes', (
    tester,
  ) async {
    port = FakeTrackingPort(
      state: const TrackingState(phase: TrackingPhase.active, tripId: 'live'),
    );
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('driver-banner')), findsOneWidget);
    expect(find.text('Passengers type; drivers listen.'), findsOneWidget);
    expect(find.byKey(const Key('chat-input')), findsNothing);
    expect(find.byKey(const Key('record-voice')), findsNothing);

    channel.inject('chat', 'sam', payload: {'text': 'hello there'}, t: 5);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('hello there'), findsOneWidget);
    // Nothing cached about 'sam': never read an id aloud.
    expect(speaker.spoken, ['Message from Someone: hello there']);

    final data = Uint8List.fromList(List.filled(20 * 1024, 1));
    final chunks = const VoiceNoteChunker().split(
      id: 'v1',
      bytes: data,
      mimeType: 'audio/aac',
      durationMs: 3000,
    );
    expect(chunks.length, greaterThan(1));
    for (final c in chunks) {
      bus.inject('sam', 'voice', c.cast<String, dynamic>());
    }
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.textContaining('Voice note'), findsOneWidget);
    expect(player.played, [data.length]);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('read-aloud uses the cached member name', (tester) async {
    await db.cachePut(
      ConvoyRepo.membersKey('c1'),
      jsonEncode([
        ConvoyMember(
          userId: 'sam',
          handle: 'sam',
          displayName: 'Sam Lee',
          role: 'member',
          joinedAt: DateTime.utc(2026, 11, 3),
        ).toJson(),
      ]),
      1,
    );
    port = FakeTrackingPort(
      state: const TrackingState(phase: TrackingPhase.active, tripId: 'live'),
    );
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    channel.inject('chat', 'sam', payload: {'text': 'left lane'}, t: 5);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(speaker.spoken, ['Message from Sam Lee: left lane']);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('the chat follows the data bus without losing history', (
    tester,
  ) async {
    port = FakeTrackingPort(state: const TrackingState());
    // No bus override: the real provider swaps Noop for the mesh bus when the
    // radio registers one.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          trackingPortProvider.overrideWithValue(port),
          currentUserIdProvider.overrideWithValue('me'),
          convoyChannelProvider.overrideWith((ref, id) => channel),
          speakerProvider.overrideWithValue(speaker),
          voicePlayerProvider.overrideWithValue(player),
          voiceRecorderProvider.overrideWithValue(recorder),
        ],
        child: const MaterialApp(home: ConvoyChatScreen(convoyId: 'c1')),
      ),
    );
    await pumpFor(tester, const Duration(seconds: 1));
    channel.inject('chat', 'sam', payload: {'text': 'before radio'});
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('before radio'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConvoyChatScreen)),
    );
    final ctl = container.read(chatControllerProvider('c1').notifier);
    container.read(radioBusRegistryProvider.notifier).register('c1', bus);
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(
      identical(container.read(chatControllerProvider('c1').notifier), ctl),
      isTrue,
      reason: 'the controller follows the bus instead of rebuilding',
    );
    expect(find.text('before radio'), findsOneWidget);

    // A voice note over the newly registered bus arrives.
    final data = Uint8List.fromList(List.filled(1024, 1));
    for (final c in const VoiceNoteChunker().split(
      id: 'v9',
      bytes: data,
      mimeType: 'audio/aac',
      durationMs: 900,
    )) {
      bus.inject('sam', 'voice', c.cast<String, dynamic>());
    }
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.textContaining('Voice note'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('passengers type, send over the channel, and keep history', (
    tester,
  ) async {
    port = FakeTrackingPort(state: const TrackingState());
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byKey(const Key('driver-banner')), findsNothing);

    await tester.enterText(find.byKey(const Key('chat-input')), 'hi convoy');
    await tester.tap(find.byKey(const Key('send-text')));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(channel.sent.single.type, 'chat');
    expect(channel.sent.single.payload, {'text': 'hi convoy'});
    expect(find.text('hi convoy'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    // Not driving: nothing is read aloud, but the line still shows.
    channel.inject('chat', 'sam', payload: {'text': 'yo'});
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('yo'), findsOneWidget);
    expect(speaker.spoken, isEmpty);

    // Blank sends are dropped.
    await tester.enterText(find.byKey(const Key('chat-input')), '   ');
    await tester.tap(find.byKey(const Key('send-text')));
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(channel.sent, hasLength(1));
    await unmountAndSettle(tester);

    // Reopening restores the last lines from the local cache.
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('hi convoy'), findsOneWidget);
    expect(find.text('yo'), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('a voice note is recorded, chunked and sent', (tester) async {
    port = FakeTrackingPort(state: const TrackingState());
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('record-voice')));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byKey(const Key('recording-label')), findsOneWidget);
    expect(recorder.calls, ['start']);

    await tester.tap(find.byKey(const Key('send-voice')));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(recorder.calls, ['start', 'stop']);
    final voice = bus.sent.where((m) => m.type == 'voice').toList();
    expect(voice, hasLength(1));
    expect(voice.single.payload['seq'], 0);
    expect(voice.single.payload['last'], isTrue);
    expect(voice.single.payload['mime'], 'audio/aac');
    expect(find.textContaining('Voice note'), findsOneWidget);
    expect(find.byKey(const Key('chat-input')), findsOneWidget);
    // My own echoed chunks are not played back to me.
    expect(player.played, isEmpty);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('without microphone permission recording explains itself', (
    tester,
  ) async {
    port = FakeTrackingPort(state: const TrackingState());
    recorder.permission = false;
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('record-voice')));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(
      find.text('Microphone permission is needed for voice notes.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recording-label')), findsNothing);
    expect(recorder.calls, isEmpty);
    await unmountAndSettle(tester);
  }, skip: skip);

  testWidgets('the read-aloud toggle persists across opens', (tester) async {
    port = FakeTrackingPort(state: const TrackingState());
    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byIcon(Icons.record_voice_over), findsOneWidget);
    await tester.tap(find.byIcon(Icons.record_voice_over));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.voice_over_off), findsOneWidget);
    await unmountAndSettle(tester);

    await tester.pumpWidget(harness());
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byIcon(Icons.voice_over_off), findsOneWidget);
    await unmountAndSettle(tester);
  }, skip: skip);
}
