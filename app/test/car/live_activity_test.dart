import 'package:drivalry/car/car_bridge.dart'
    show carClockProvider, carSnapshotProvider;
import 'package:drivalry/car/car_snapshot.dart';
import 'package:drivalry/car/live_activity.dart';
import 'package:drivalry/tracking/tracking_models.dart' show TrackingPhase;
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls instead of touching the channel.
class _FakeBridge extends LiveActivityBridge {
  _FakeBridge({this.supported = true});

  final bool supported;
  final calls = <String>[];
  final frames = <LiveActivityContent?>[];
  int? startedAt;

  @override
  Future<bool> isSupported() async {
    calls.add('isSupported');
    return supported;
  }

  @override
  Future<void> start(LiveActivityContent content, {int? startedAt}) async {
    calls.add('start');
    frames.add(content);
    this.startedAt = startedAt;
    activityId = 'A1';
  }

  @override
  Future<void> update(LiveActivityContent content) async {
    calls.add('update');
    frames.add(content);
  }

  @override
  Future<void> end([LiveActivityContent? finalContent]) async {
    calls.add('end');
    frames.add(finalContent);
    activityId = null;
  }
}

class _Snap extends Notifier<CarSnapshot> {
  @override
  CarSnapshot build() => CarSnapshot.idle;
  void set(CarSnapshot s) => state = s;
}

final _snapProvider = NotifierProvider<_Snap, CarSnapshot>(_Snap.new);

LiveActivityContent _frame({
  int speed = 50,
  int minutes = 10,
  int? tripStartedAt,
}) => LiveActivityContent(
  limitPosted: 45,
  limitUnit: 'mph',
  speedPosted: speed,
  cleanSoFar: true,
  tripMinutes: minutes,
  updatedAt: 0,
  tripStartedAt: tripStartedAt,
);

// 45 mph = 20.1168 m/s; 50 mph = 22.352 m/s; 5 mph = 2.2352 m/s.
const _recording = CarDrive(
  phase: TrackingPhase.active,
  tripId: 't1',
  startedAt: 0,
  elapsedS: 605,
  speedMps: 22.352,
  limitMps: 20.1168,
  posted: 45,
  limitUnit: 'mph',
  road: 'Main St',
  overMps: 2.2352,
);

const _convoy = CarConvoy(
  id: 'c1',
  name: 'Road trip',
  status: 'active',
  leaderId: 'L',
  members: [
    CarMember(
      id: 'L',
      name: 'Ryan',
      initials: 'R',
      isLeader: true,
      speedMps: 30,
      distanceM: 3600,
      etaS: 1000,
    ),
    CarMember(id: 'me', name: 'Sam', initials: 'S', isMe: true, etaS: 61),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(liveActivityChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('LiveActivityContent.fromSnapshot', () {
    test('over the limit: speed in the limit unit, over-by, road, minutes', () {
      final c = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: _recording, units: SpeedUnits.kmh),
        nowMs: 605000,
      );
      expect(c.limitPosted, 45);
      expect(c.limitUnit, 'mph', reason: 'limit unit wins over the setting');
      expect(c.speedPosted, 50);
      expect(c.overBy, 5);
      expect(c.cleanSoFar, isFalse);
      expect(c.roadName, 'Main St');
      expect(c.tripMinutes, 10);
      expect(c.convoyName, isNull);
      expect(c.toMap(), {
        'limitPosted': 45,
        'limitUnit': 'mph',
        'speedPosted': 50,
        'cleanSoFar': false,
        'overBy': 5,
        'roadName': 'Main St',
        'tripMinutes': 10,
        'convoyName': null,
        'gapMinutes': null,
        'etaMinutes': null,
        'talking': null,
        'recording': true,
        'updatedAt': 605000,
      });
    });

    test('under the limit is clean with no over-by', () {
      const d = CarDrive(
        phase: TrackingPhase.active,
        tripId: 't1',
        startedAt: 0,
        speedMps: 15,
        limitMps: 20.1168,
        posted: 45,
        limitUnit: 'mph',
        road: 'Main St',
        overMps: 0,
      );
      final c = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: d),
        nowMs: 605000,
      );
      expect(c.speedPosted, 34);
      expect(c.overBy, isNull);
      expect(c.cleanSoFar, isTrue);
      expect(c.tripMinutes, 10, reason: 'falls back to startedAt');
    });

    test('inside the tolerance there is no over-by either', () {
      const d = CarDrive(
        phase: TrackingPhase.active,
        tripId: 't1',
        speedMps: 21,
        limitMps: 20.1168,
        posted: 45,
        limitUnit: 'mph',
        overMps: 0.8832,
      );
      final c = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: d),
        nowMs: 0,
      );
      expect(c.overBy, isNull);
      expect(c.cleanSoFar, isTrue);
    });

    test('earlier speeding this trip ends clean-so-far', () {
      const d = CarDrive(
        phase: TrackingPhase.active,
        tripId: 't1',
        speedMps: 15,
        limitMps: 20.1168,
        posted: 45,
        overMps: 0,
        speedingS: 12,
      );
      final c = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: d),
        nowMs: 0,
      );
      expect(c.cleanSoFar, isFalse);
      expect(c.overBy, isNull);
    });

    test('without a limit it uses the setting unit and hides the road', () {
      const d = CarDrive(
        phase: TrackingPhase.active,
        tripId: 't1',
        speedMps: 27.78,
        road: 'Somewhere',
      );
      final c = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: d, units: SpeedUnits.kmh),
        nowMs: 0,
      );
      expect(c.limitPosted, isNull);
      expect(c.limitUnit, 'km/h');
      expect(c.speedPosted, 100);
      expect(c.overBy, isNull);
      expect(c.roadName, isNull);
      expect(c.cleanSoFar, isTrue, reason: 'no limit data is not a fault');
      expect(c.tripMinutes, 0);
    });

    test('a passenger trip is not clean-so-far', () {
      const d = CarDrive(
        phase: TrackingPhase.active,
        tripId: 't1',
        passenger: true,
      );
      final c = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: d),
        nowMs: 0,
      );
      expect(c.cleanSoFar, isFalse);
    });

    test(
      'convoy line: name, gap behind the leader, eta rounded up, talker',
      () {
        final c = LiveActivityContent.fromSnapshot(
          const CarSnapshot(
            drive: _recording,
            convoy: _convoy,
            talk: CarTalk(available: true, on: true, talking: ['Jo']),
            me: 'me',
          ),
          nowMs: 0,
        );
        expect(c.convoyName, 'Road trip');
        expect(c.gapMinutes, 2, reason: '3600 m at 30 m/s');
        expect(c.etaMinutes, 2, reason: '61 s rounds up');
        expect(c.talking, 'Jo');
      },
    );

    test('holding push-to-talk shows You; a stopped leader uses the floor', () {
      const convoy = CarConvoy(
        id: 'c1',
        name: 'Road trip',
        status: 'active',
        members: [
          CarMember(
            id: 'L',
            name: 'Ryan',
            initials: 'R',
            isLeader: true,
            speedMps: 0,
            distanceM: 2400,
          ),
          CarMember(id: 'me', name: 'Sam', initials: 'S', isMe: true),
        ],
      );
      final c = LiveActivityContent.fromSnapshot(
        const CarSnapshot(
          drive: CarDrive.idle,
          convoy: convoy,
          talk: CarTalk(available: true, on: true, holding: true),
        ),
        nowMs: 0,
      );
      expect(c.talking, 'You');
      expect(c.gapMinutes, 2, reason: '2400 m at the 20 m/s floor');
      expect(c.etaMinutes, isNull);
      expect(c.tripMinutes, 0, reason: 'convoy without a recording trip');
    });

    test('the leader has a zero gap; a planning convoy shows nothing', () {
      const leading = CarConvoy(
        id: 'c1',
        name: 'Road trip',
        status: 'active',
        members: [
          CarMember(
            id: 'me',
            name: 'Ryan',
            initials: 'R',
            isMe: true,
            isLeader: true,
          ),
        ],
      );
      final c = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: _recording, convoy: leading),
        nowMs: 0,
      );
      expect(c.gapMinutes, 0);
      const planning = CarConvoy(
        id: 'c1',
        name: 'Road trip',
        status: 'planning',
      );
      final p = LiveActivityContent.fromSnapshot(
        const CarSnapshot(
          drive: _recording,
          convoy: planning,
          talk: CarTalk(talking: ['Jo']),
        ),
        nowMs: 0,
      );
      expect(p.convoyName, isNull);
      expect(p.gapMinutes, isNull);
      expect(p.talking, isNull);
    });

    test('carries the trip start; a convoy that is not driving has none', () {
      final driving = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: _recording, convoy: _convoy),
        nowMs: 605000,
      );
      expect(driving.tripStartedAt, 0, reason: '_recording.startedAt');
      expect(driving.toMap()['recording'], isTrue);
      final parked = LiveActivityContent.fromSnapshot(
        const CarSnapshot(drive: CarDrive.idle, convoy: _convoy),
        nowMs: 605000,
      );
      expect(parked.tripStartedAt, isNull);
      expect(parked.toMap()['recording'], isFalse);
      expect(parked.tripMinutes, 0);
    });

    test('displayEquals ignores updatedAt only', () {
      final a = _frame();
      expect(a.displayEquals(_frame()), isTrue);
      expect(
        a.displayEquals(
          const LiveActivityContent(
            limitPosted: 45,
            limitUnit: 'mph',
            speedPosted: 50,
            cleanSoFar: true,
            tripMinutes: 10,
            updatedAt: 99,
          ),
        ),
        isTrue,
      );
      expect(a.displayEquals(_frame(speed: 51)), isFalse);
      expect(a.displayEquals(null), isFalse);
    });
  });

  group('liveActivityContentProvider', () {
    test(
      'is null when idle or tentative, a frame when recording or convoying',
      () {
        final container = ProviderContainer(
          overrides: [
            carSnapshotProvider.overrideWith((ref) => ref.watch(_snapProvider)),
            carClockProvider.overrideWithValue(() => 605000),
          ],
        );
        addTearDown(container.dispose);
        expect(container.read(liveActivityContentProvider), isNull);
        container
            .read(_snapProvider.notifier)
            .set(
              const CarSnapshot(
                drive: CarDrive(phase: TrackingPhase.tentative, tripId: 't0'),
              ),
            );
        expect(container.read(liveActivityContentProvider), isNull);
        container
            .read(_snapProvider.notifier)
            .set(const CarSnapshot(drive: _recording));
        final frame = container.read(liveActivityContentProvider)!;
        expect(frame.limitPosted, 45);
        expect(frame.updatedAt, 605000);
        container
            .read(_snapProvider.notifier)
            .set(
              const CarSnapshot(
                drive: CarDrive.idle,
                convoy: _convoy,
                me: 'me',
              ),
            );
        expect(
          container.read(liveActivityContentProvider)!.convoyName,
          'Road trip',
        );
        container.read(_snapProvider.notifier).set(CarSnapshot.idle);
        expect(container.read(liveActivityContentProvider), isNull);
      },
    );
  });

  group('LiveActivityBridge', () {
    test('start without a trip omits startedAt', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'start' ? 'ACT-2' : null;
      });
      final b = LiveActivityBridge();
      await b.start(_frame());
      expect((calls.single.arguments as Map).containsKey('startedAt'), isFalse);
      await b.start(_frame(tripStartedAt: 99), startedAt: 99);
      expect((calls.last.arguments as Map)['startedAt'], 99);
    });

    test(
      'start, update and end carry the state map and record the id',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'isSupported'
              ? true
              : call.method == 'start'
              ? 'ACT-1'
              : null;
        });
        final b = LiveActivityBridge();
        expect(await b.isSupported(), isTrue);
        await b.start(_frame(), startedAt: 123);
        expect(b.activityId, 'ACT-1');
        await b.update(_frame(speed: 51));
        await b.end(_frame(speed: 0));
        expect(b.activityId, isNull);
        await b.endAll();
        expect(calls.map((c) => c.method), [
          'isSupported',
          'start',
          'update',
          'end',
          'endAll',
        ]);
        final start = calls[1].arguments as Map;
        expect(start['startedAt'], 123);
        expect((start['state'] as Map)['speedPosted'], 50);
        expect(
          ((calls[2].arguments as Map)['state'] as Map)['speedPosted'],
          51,
        );
        expect(((calls[3].arguments as Map)['state'] as Map)['speedPosted'], 0);
        expect(calls[4].arguments, isEmpty);
      },
    );

    test(
      'a missing native side is unsupported and otherwise ignored',
      () async {
        final b = LiveActivityBridge();
        expect(await b.isSupported(), isFalse);
        await b.start(_frame(), startedAt: 0);
        expect(b.activityId, isNull);
        await b.update(_frame());
        await b.end();
      },
    );

    test('platform errors are swallowed', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'activity', message: 'denied');
      });
      final b = LiveActivityBridge();
      expect(await b.isSupported(), isFalse);
      await b.start(_frame(), startedAt: 0);
      await b.end();
    });
  });

  group('LiveActivityDriver', () {
    test('a trip gets its own activity: its start is the fixed attribute', () {
      fakeAsync((async) {
        const base = 1000000;
        final bridge = _FakeBridge();
        final d = LiveActivityDriver(
          bridge,
          now: () => base + async.elapsed.inMilliseconds,
        );
        // Convoy first, not driving: an activity with no trip start.
        d.push(_frame(minutes: 0));
        async.flushMicrotasks();
        expect(bridge.calls, ['isSupported', 'start']);
        expect(bridge.startedAt, isNull);

        // The drive begins: a fresh activity carrying the trip start.
        d.push(_frame(minutes: 0, tripStartedAt: base + 1000));
        async.flushMicrotasks();
        expect(bridge.calls, ['isSupported', 'start', 'end', 'start']);
        expect(bridge.startedAt, base + 1000);

        // Same trip, a second later in elapsed terms: just an update.
        async.elapse(const Duration(seconds: 6));
        d.push(_frame(minutes: 1, speed: 51, tripStartedAt: base + 2000));
        async.flushMicrotasks();
        expect(bridge.calls.last, 'update');

        // The next leg, an hour on: again a fresh activity.
        async.elapse(const Duration(seconds: 6));
        d.push(_frame(minutes: 0, tripStartedAt: base + 3600000));
        async.flushMicrotasks();
        expect(bridge.calls.sublist(bridge.calls.length - 2), ['end', 'start']);
        expect(bridge.startedAt, base + 3600000);
        d.push(null);
        async.flushMicrotasks();
      });
    });

    test('starts on the first frame, throttles updates, ends on null', () {
      fakeAsync((async) {
        const base = 1000000;
        final bridge = _FakeBridge();
        final d = LiveActivityDriver(
          bridge,
          now: () => base + async.elapsed.inMilliseconds,
        );
        d.push(_frame(minutes: 10));
        async.flushMicrotasks();
        expect(d.running, isTrue);
        expect(bridge.calls, ['isSupported', 'start']);
        expect(bridge.startedAt, isNull, reason: 'no trip start in the frame');

        // Two changes inside five seconds collapse into one update with the
        // newest frame, sent when the window closes.
        async.elapse(const Duration(seconds: 1));
        d.push(_frame(speed: 51));
        d.push(_frame(speed: 52));
        async.elapse(const Duration(seconds: 3));
        expect(bridge.calls.length, 2);
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(bridge.calls, ['isSupported', 'start', 'update']);
        expect(bridge.frames.last!.speedPosted, 52);

        // Same display again: nothing sent even after the window.
        async.elapse(const Duration(seconds: 6));
        d.push(_frame(speed: 52));
        async.flushMicrotasks();
        expect(bridge.calls.length, 3);

        // A change after the window goes straight out.
        d.push(_frame(speed: 40));
        async.flushMicrotasks();
        expect(bridge.calls.last, 'update');
        expect(bridge.frames.last!.speedPosted, 40);

        // Pending change then the trip ends: the pending frame is dropped and
        // the activity ends with the last frame that was shown.
        d.push(_frame(speed: 41));
        d.push(null);
        async.flushMicrotasks();
        expect(d.running, isFalse);
        expect(bridge.calls.last, 'end');
        expect(bridge.frames.last!.speedPosted, 40);
        async.elapse(const Duration(seconds: 10));
        expect(bridge.calls.where((c) => c == 'update').length, 2);

        // A second drive starts a fresh activity; dispose ends it and later
        // frames are ignored.
        d.push(_frame(speed: 20));
        async.flushMicrotasks();
        expect(bridge.calls.last, 'start');
        d.dispose();
        async.flushMicrotasks();
        expect(bridge.calls.last, 'end');
        final n = bridge.calls.length;
        d.push(_frame());
        async.flushMicrotasks();
        expect(bridge.calls.length, n);
      });
    });

    test('an unsupported device gets one isSupported and nothing else', () {
      fakeAsync((async) {
        final bridge = _FakeBridge(supported: false);
        final d = LiveActivityDriver(
          bridge,
          now: () => async.elapsed.inMilliseconds,
        );
        d.push(_frame());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 6));
        d.push(_frame(speed: 60));
        d.push(null);
        async.flushMicrotasks();
        expect(bridge.calls, ['isSupported']);
        expect(d.running, isFalse);
      });
    });
  });

  group('liveActivityProvider', () {
    test('is null off iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(liveActivityEnabledProvider), isFalse);
      expect(container.read(liveActivityProvider), isNull);
    });

    test('is on for iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(liveActivityEnabledProvider), isTrue);
    });

    test(
      'pushes snapshot changes into the driver and ends on dispose',
      () async {
        final bridge = _FakeBridge();
        final container = ProviderContainer(
          overrides: [
            liveActivityEnabledProvider.overrideWithValue(true),
            liveActivityBridgeProvider.overrideWithValue(bridge),
            carSnapshotProvider.overrideWith((ref) => ref.watch(_snapProvider)),
            carClockProvider.overrideWithValue(() => 605000),
          ],
        );
        // Riverpod 3 pauses a provider nobody listens to; in the app the
        // bootstrap provider watches it, here a plain listener stands in.
        final sub = container.listen(liveActivityProvider, (_, _) {});
        final driver = sub.read()!;
        expect(driver.running, isFalse);
        container
            .read(_snapProvider.notifier)
            .set(const CarSnapshot(drive: _recording));
        await Future<void>.delayed(Duration.zero);
        await driver.idle;
        expect(driver.running, isTrue);
        expect(bridge.calls, ['isSupported', 'start']);
        expect(bridge.frames.single!.limitPosted, 45);
        container.read(_snapProvider.notifier).set(CarSnapshot.idle);
        await Future<void>.delayed(Duration.zero);
        await driver.idle;
        expect(driver.running, isFalse);
        expect(bridge.calls.last, 'end');
        container
            .read(_snapProvider.notifier)
            .set(
              const CarSnapshot(
                drive: CarDrive.idle,
                convoy: _convoy,
                me: 'me',
              ),
            );
        await Future<void>.delayed(Duration.zero);
        await driver.idle;
        expect(bridge.calls.last, 'start');
        expect(bridge.frames.last!.convoyName, 'Road trip');
        container.dispose();
        await driver.idle;
        expect(bridge.calls.last, 'end');
      },
    );
  });
}
