import 'package:drivalry/data/repos/presence_repo.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int now;
  late List<PresenceUpdate> sent;
  late bool allowed;
  late PresencePublisher publisher;

  setUp(() {
    now = 1_000_000;
    sent = [];
    allowed = true;
    publisher = PresencePublisher(
      send: (u) async => sent.add(u),
      now: () => now,
      isAllowed: () => allowed,
      battery: () async => 0.5,
    );
  });

  FixesEvent fixes(int t, double lat, {double speed = 15}) => FixesEvent(
    tripId: 't1',
    t: t,
    fixes: [Fix(t: t, lat: lat, lon: -77, accuracy: 5, speed: speed)],
  );

  test('publishes at most every 30 s while driving', () async {
    await publisher.onEvent(
      const PhaseEvent(tripId: 't1', t: 0, phase: TripPhaseSignal.active),
    );
    await publisher.onEvent(fixes(1, 38.0));
    expect(sent, hasLength(1));
    expect(sent.single.driving, isTrue);
    expect(sent.single.battery, 0.5);

    now += 15_000;
    await publisher.onEvent(fixes(2, 38.1));
    expect(sent, hasLength(1), reason: 'inside the 30 s window');

    now += 15_000;
    await publisher.onEvent(fixes(3, 38.2));
    expect(sent, hasLength(2));
    expect(sent.last.lat, 38.2);
  });

  test('trip end publishes parked at once', () async {
    await publisher.onEvent(
      const PhaseEvent(tripId: 't1', t: 0, phase: TripPhaseSignal.active),
    );
    await publisher.onEvent(fixes(1, 38.0));
    now += 1_000;
    await publisher.onEvent(
      const PhaseEvent(tripId: 't1', t: 1000, phase: TripPhaseSignal.ended),
    );
    expect(sent, hasLength(2));
    expect(sent.last.driving, isFalse);
  });

  test('parked fixes publish as not driving', () async {
    await publisher.onEvent(
      const ParkedFixEvent(t: 5, lat: 39, lon: -76, accuracy: 30),
    );
    expect(sent.single.driving, isFalse);
    expect(sent.single.lat, 39);
  });

  test('nothing is sent while hidden or signed out', () async {
    allowed = false;
    await publisher.onEvent(
      const PhaseEvent(tripId: 't1', t: 0, phase: TripPhaseSignal.active),
    );
    await publisher.onEvent(fixes(1, 38.0));
    await publisher.onEvent(
      const ParkedFixEvent(t: 5, lat: 39, lon: -76, accuracy: 30),
    );
    await publisher.onForeground(
      () async => const LastKnownLocation(t: 1, lat: 1, lon: 2, accuracy: 5),
    );
    expect(sent, isEmpty);
  });

  test(
    'foreground uses the last known location, tolerating failures',
    () async {
      await publisher.onForeground(() async => throw StateError('no plugin'));
      expect(sent, isEmpty);
      await publisher.onForeground(() async => null);
      expect(sent, isEmpty);
      await publisher.onForeground(
        () async =>
            const LastKnownLocation(t: 1, lat: 40, lon: -75, accuracy: 20),
      );
      expect(sent.single.lat, 40);
      expect(sent.single.driving, isFalse);
    },
  );

  test('a failed send does not break later publishes', () async {
    var fail = true;
    publisher = PresencePublisher(
      send: (u) async {
        if (fail) throw StateError('offline');
        sent.add(u);
      },
      now: () => now,
      isAllowed: () => true,
    );
    await publisher.onEvent(
      const ParkedFixEvent(t: 5, lat: 39, lon: -76, accuracy: 30),
    );
    expect(sent, isEmpty);
    fail = false;
    now += 30_000;
    await publisher.onEvent(
      const ParkedFixEvent(t: 6, lat: 39.5, lon: -76, accuracy: 30),
    );
    expect(sent.single.lat, 39.5);
  });
}
