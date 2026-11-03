import 'dart:async';
import 'dart:convert';

import 'package:drivalry/car/car_actions.dart';
import 'package:drivalry/car/car_bridge.dart';
import 'package:drivalry/car/car_snapshot.dart';
import 'package:drivalry/car/ongoing_notification.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [CarChannel] whose native side is a list of recorded calls.
class RecordingChannel extends CarChannel {
  RecordingChannel() : super(channel: const MethodChannel('test/car'));
  final List<(String, Object?)> calls = [];
  List<Object?> queued = const [];

  @override
  Future<void> sendSnapshot(CarSnapshot s, {required int at}) async {
    calls.add(('snapshot', s.toJson(at: at)));
  }

  @override
  Future<void> sendOngoingNotification(OngoingNotificationLine? line) async {
    calls.add(('ongoingNotification', line?.toWire()));
  }

  @override
  Future<List<CarAction>> drainActions() async => [
    for (final w in queued) ?CarAction.fromWire(w),
  ];
}

/// Counts JSON encodes so the bridge can be shown to encode once per flush.
class _CountingSnapshot extends CarSnapshot {
  const _CountingSnapshot()
    : super(
        drive: const CarDrive(phase: TrackingPhase.active, tripId: 't1'),
      );

  static int encodes = 0;

  @override
  Map<String, Object?> toJson({int? at}) {
    encodes++;
    return super.toJson(at: at);
  }
}

class FakeHandler implements CarActions {
  final List<CarAction> handled = [];
  final List<String> confirmed = [];
  bool result = true;

  @override
  Future<bool> handle(CarAction a) async {
    handled.add(a);
    return result;
  }

  @override
  Future<void> confirmPassengerIfMarked(String tripId) async {
    confirmed.add(tripId);
  }
}

CarSnapshot _active({double speed = 13.86, int elapsedS = 60}) => CarSnapshot(
  drive: CarDrive(
    phase: TrackingPhase.active,
    tripId: 't1',
    speedMps: speed,
    limitMps: 15.65,
    posted: 35,
    overMps: 0,
    elapsedS: elapsedS,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CarChannel', () {
    const channel = MethodChannel(carChannelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('sends the snapshot as JSON with the timestamp', () async {
      final sent = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent.add(call);
        return null;
      });
      final c = CarChannel();
      await c.sendSnapshot(_active(), at: 42);
      await c.sendOngoingNotification(
        const OngoingNotificationLine(title: 'Drivalry', text: 'x'),
      );
      await c.sendOngoingNotification(null);
      expect(sent.map((m) => m.method), [
        'snapshot',
        'ongoingNotification',
        'ongoingNotification',
      ]);
      final json =
          jsonDecode((sent[0].arguments as Map)['json'] as String) as Map;
      expect(json['v'], carSnapshotVersion);
      expect(json['at'], 42);
      expect(json['drive']['posted'], 35);
      expect((sent[1].arguments as Map)['text'], 'x');
      expect(sent[2].arguments, isNull);
      c.dispose();
    });

    test('drains queued actions and drops junk', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'drainActions');
        return [
          {
            'name': 'markPassenger',
            'args': {'tripId': 't1'},
          },
          {'name': 'nope'},
          'garbage',
        ];
      });
      final c = CarChannel();
      final actions = await c.drainActions();
      expect(actions.length, 1);
      expect(actions.single.name, CarActionNames.markPassenger);
      expect(actions.single.string('tripId'), 't1');
      c.dispose();
    });

    test('a missing native side is not an error', () async {
      final c = CarChannel();
      await c.sendSnapshot(_active(), at: 1);
      await c.sendOngoingNotification(null);
      expect(await c.drainActions(), isEmpty);
      c.dispose();
    });

    test('a platform error is swallowed', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'car', message: 'boom');
      });
      final c = CarChannel();
      await c.sendSnapshot(_active(), at: 1);
      expect(await c.drainActions(), isEmpty);
      c.dispose();
    });

    test('actions from the car reach the handler and report back', () async {
      final c = CarChannel();
      final seen = <CarAction>[];
      c.onAction = (a) async {
        seen.add(a);
        return a.name == CarActionNames.endTrip;
      };
      final stream = c.actions.take(2).toList();

      Future<Object?> send(Map<String, Object?> payload) async {
        Object? reply;
        await messenger.handlePlatformMessage(
          carChannelName,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('action', payload),
          ),
          (data) => reply = data == null
              ? null
              : const StandardMethodCodec().decodeEnvelope(data),
        );
        return reply;
      }

      expect(await send({'name': 'endTrip'}), isTrue);
      expect(await send({'name': 'crashOk', 'args': {}}), isFalse);
      expect(await send({'name': 'bogus'}), isFalse);
      expect((await stream).map((a) => a.name), ['endTrip', 'crashOk']);
      expect(seen.length, 2);
      c.dispose();
    });

    test(
      'a snapshot is encoded once per flush; the wire carries the time',
      () async {
        _CountingSnapshot.encodes = 0;
        const snap = _CountingSnapshot();
        String? wire;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'snapshot') {
            wire = (call.arguments as Map)['json'] as String;
          }
          return null;
        });
        final c = CarChannel(channel: channel);
        final bridge = CarBridge(
          channel: c,
          handler: FakeHandler(),
          now: () => 7,
        );
        bridge.update(snap);
        await pumpEventQueue();
        expect(_CountingSnapshot.encodes, 1);
        final sent = jsonDecode(wire!) as Map;
        expect(sent['at'], 7);
        expect(sent['v'], carSnapshotVersion);
        expect(sent['drive'], isA<Map>());
        // Equality and hashing reuse the cached string.
        expect(snap == const _CountingSnapshot(), isTrue);
        expect(snap.hashCode, const _CountingSnapshot().hashCode);
        expect(_CountingSnapshot.encodes, 1);
        bridge.dispose();
        c.dispose();
      },
    );
  });

  group('CarBridge', () {
    test('sends at most once per second and skips identical content', () {
      fakeAsync((async) {
        var now = 1_000_000;
        final ch = RecordingChannel();
        final bridge = CarBridge(
          channel: ch,
          handler: FakeHandler(),
          now: () => now,
        );
        bridge.update(_active());
        expect(ch.calls.map((c) => c.$1), ['snapshot', 'ongoingNotification']);
        expect(ch.calls[0].$2, containsPair('at', 1_000_000));

        // Rapid updates coalesce into one send a second later.
        now += 200;
        bridge.update(_active(speed: 14));
        now += 200;
        bridge.update(_active(speed: 15));
        expect(ch.calls.length, 2);
        // The timer was armed 800 ms before the second's end; 700 ms is too soon.
        async.elapse(const Duration(milliseconds: 700));
        expect(ch.calls.length, 2);
        now += 800;
        async.elapse(const Duration(milliseconds: 100));
        expect(ch.calls.length, 4, reason: 'the latest snapshot and its line');
        final sent = ch.calls[2].$2 as Map;
        expect(sent['drive']['speedMps'], 15);
        expect(
          (ch.calls[3].$2 as Map)['text'],
          'Recording · Limit 35 · 34 mph · Clean so far',
        );

        // Same content again: nothing goes out.
        now += 2000;
        bridge.update(_active(speed: 15));
        expect(ch.calls.length, 4);

        // Only the elapsed time changes: a snapshot, but the same line.
        now += 2000;
        bridge.update(_active(speed: 15, elapsedS: 61));
        expect(ch.calls.length, 5);
        expect(ch.calls.last.$1, 'snapshot');

        // A new speed changes the line too.
        now += 2000;
        bridge.update(_active(speed: 20, elapsedS: 61));
        expect(ch.calls.length, 7);
        expect(ch.calls.last.$1, 'ongoingNotification');
        expect(
          (ch.calls.last.$2 as Map)['text'],
          'Recording · Limit 35 · 45 mph · Clean so far',
        );

        // Idle clears the line once.
        now += 2000;
        bridge.update(CarSnapshot.idle);
        expect(ch.calls.last, ('ongoingNotification', null));
        bridge.dispose();
      });
    });

    test('queued actions wait until the app is ready', () async {
      final ch = RecordingChannel()
        ..queued = [
          {
            'name': 'markPassenger',
            'args': {'tripId': 't1'},
          },
        ];
      final handler = FakeHandler();
      final ready = Completer<void>();
      final bridge = CarBridge(
        channel: ch,
        handler: handler,
        now: () => 0,
        ready: () => ready.future,
      );
      final drained = bridge.drainQueued();
      await pumpEventQueue();
      expect(handler.handled, isEmpty, reason: 'boot has not finished');
      ready.complete();
      await drained;
      expect(handler.handled.single.name, 'markPassenger');
      bridge.dispose();
    });

    test('drains queued native actions through the handler', () async {
      final ch = RecordingChannel()
        ..queued = [
          {
            'name': 'markPassenger',
            'args': {'tripId': 't1'},
          },
          {'name': 'endTrip'},
        ];
      final handler = FakeHandler();
      final bridge = CarBridge(channel: ch, handler: handler, now: () => 0);
      await bridge.drainQueued();
      expect(handler.handled.map((a) => a.name), ['markPassenger', 'endTrip']);
      bridge.dispose();
    });

    test('after dispose nothing is sent', () {
      fakeAsync((async) {
        final ch = RecordingChannel();
        final bridge = CarBridge(
          channel: ch,
          handler: FakeHandler(),
          now: () => 0,
        );
        bridge.update(_active());
        bridge.update(_active(speed: 1));
        bridge.dispose();
        async.elapse(const Duration(seconds: 2));
        expect(ch.calls.length, 2);
      });
    });
  });
}
