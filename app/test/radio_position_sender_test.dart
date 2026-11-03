import 'package:drivalry/features/convoy/radio/data_bus.dart';
import 'package:drivalry/features/convoy/radio/position_sender.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

Fix fix(int t, {double speed = 15}) =>
    Fix(t: t, lat: 38.9, lon: -77.0, accuracy: 5, speed: speed, heading: 90);

void main() {
  test('moving fixes go out every 3 s, stopped ones every 10 s', () {
    final bus = LoopbackDataBus('me');
    final sender = PositionSender(bus, battery: () => 0.5);
    // A 15 s batch at 1 Hz while moving.
    sender.onFixes([for (var i = 0; i < 15; i++) fix(1000 * i)]);
    expect(sender.sent, 5, reason: 't = 0, 3, 6, 9, 12 s');
    final first = bus.sent.first;
    expect(first.type, 'pos');
    expect(first.payload['fixT'], 0);
    expect(first.payload['lat'], 38.9);
    expect(first.payload['speed'], 15);
    expect(first.payload['battery'], 0.5);

    // Stopped: one per 10 s.
    sender.onFixes([for (var i = 15; i < 45; i++) fix(1000 * i, speed: 0)]);
    expect(sender.sent, 5 + 3, reason: 't = 22, 32, 42 s');
    bus.dispose();
  });

  test('a fix without a speed counts as stopped and omits the key', () {
    final bus = LoopbackDataBus('me');
    final sender = PositionSender(bus);
    sender.onEvent(
      FixesEvent(
        tripId: 't',
        t: 0,
        fixes: [Fix(t: 0, lat: 1, lon: 2, accuracy: 9)],
      ),
    );
    expect(sender.sent, 1);
    expect(bus.sent.single.payload.containsKey('speed'), isFalse);
    expect(bus.sent.single.payload.containsKey('battery'), isFalse);
    sender.onEvent(
      const PhaseEvent(tripId: 't', t: 1, phase: TripPhaseSignal.ended),
    );
    expect(sender.sent, 1, reason: 'other events are ignored');
    bus.dispose();
  });
}
