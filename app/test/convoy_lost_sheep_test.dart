import 'package:drivalry/data/convoy/lost_sheep.dart';
import 'package:drivalry/features/convoy/positions/peer_positions.dart';
import 'package:flutter_test/flutter_test.dart';

PeerPosition _p(
  String id,
  int t,
  double lat,
  double lon, {
  double speed = 25,
}) => PeerPosition(
  userId: id,
  t: t,
  lat: lat,
  lon: lon,
  speed: speed,
  source: PositionSource.mesh,
);

void main() {
  const t0 = 1000000;
  // ~0.01° lat ≈ 1.11 km. At 25 m/s, 1 min ≈ 1.5 km ≈ 0.0135°.
  group('LostSheepDetector', () {
    test('a car far behind the leader is lost; one event per episode', () {
      final d = LostSheepDetector();
      final members = {'lead', 'm1'};
      // 6 min behind: 25 m/s * 360 s = 9 km ≈ 0.081°.
      var started = d.evaluate(
        leaderId: 'lead',
        positions: {
          'lead': _p('lead', t0, 40.0, -100.0),
          'm1': _p('m1', t0, 40.0 - 0.081, -100.0),
        },
        members: members,
        nowMs: t0,
      );
      expect(started, [const LostSheep(userId: 'm1', reason: 'behind')]);
      expect(d.current.keys, ['m1']);

      // Still behind: no new event.
      started = d.evaluate(
        leaderId: 'lead',
        positions: {
          'lead': _p('lead', t0 + 1000, 40.0, -100.0),
          'm1': _p('m1', t0 + 1000, 40.0 - 0.081, -100.0),
        },
        members: members,
        nowMs: t0 + 1000,
      );
      expect(started, isEmpty);
      expect(d.current.keys, ['m1']);
    });

    test('hysteresis: lost at 5 min, recovered only below 4 min', () {
      final d = LostSheepDetector();
      final members = {'lead', 'm1'};
      Map<String, PeerPosition> at(double gapDeg) => {
        'lead': _p('lead', t0, 40.0, -100.0),
        'm1': _p('m1', t0, 40.0 - gapDeg, -100.0),
      };
      // 4.5 min ≈ 6.75 km ≈ 0.0608°: not lost yet.
      expect(
        d.evaluate(
          leaderId: 'lead',
          positions: at(0.0608),
          members: members,
          nowMs: t0,
        ),
        isEmpty,
      );
      // 5.2 min ≈ 7.8 km ≈ 0.0703°: lost.
      expect(
        d.evaluate(
          leaderId: 'lead',
          positions: at(0.0703),
          members: members,
          nowMs: t0,
        ),
        hasLength(1),
      );
      // Back to 4.5 min: still lost (above the 4 min exit threshold).
      d.evaluate(
        leaderId: 'lead',
        positions: at(0.0608),
        members: members,
        nowMs: t0,
      );
      expect(d.current, contains('m1'));
      // 3.5 min ≈ 5.25 km ≈ 0.0473°: recovered.
      d.evaluate(
        leaderId: 'lead',
        positions: at(0.0473),
        members: members,
        nowMs: t0,
      );
      expect(d.current, isEmpty);
    });

    test('silent car while others move', () {
      final d = LostSheepDetector();
      final members = {'lead', 'm1', 'm2'};
      final now = t0 + 10 * 60 * 1000;
      final started = d.evaluate(
        leaderId: 'lead',
        positions: {
          'lead': _p('lead', now, 40.0, -100.0),
          'm1': _p('m1', now, 40.0, -100.001),
          'm2': _p('m2', t0, 40.0, -100.002), // 10 min old
        },
        members: members,
        nowMs: now,
      );
      expect(started, [const LostSheep(userId: 'm2', reason: 'silent')]);
    });

    test('silence while everyone is parked is not an alert', () {
      final d = LostSheepDetector();
      final started = d.evaluate(
        leaderId: 'lead',
        positions: {
          'lead': _p('lead', t0, 40.0, -100.0, speed: 0),
          'm1': _p('m1', t0 - 10 * 60 * 1000, 40.0, -100.001, speed: 0),
        },
        members: {'lead', 'm1'},
        nowMs: t0,
      );
      expect(started, isEmpty);
    });

    test('a member who left is dropped from current', () {
      final d = LostSheepDetector();
      d.evaluate(
        leaderId: 'lead',
        positions: {
          'lead': _p('lead', t0, 40.0, -100.0),
          'm1': _p('m1', t0, 40.0 - 0.1, -100.0),
        },
        members: {'lead', 'm1'},
        nowMs: t0,
      );
      expect(d.current, contains('m1'));
      d.evaluate(
        leaderId: 'lead',
        positions: {'lead': _p('lead', t0, 40.0, -100.0)},
        members: {'lead'},
        nowMs: t0,
      );
      expect(d.current, isEmpty);
    });
  });

  test('gapMinutes floors the leader speed at 20 m/s', () {
    final lead = _p('lead', t0, 40.0, -100.0, speed: 0);
    final m = _p('m', t0, 40.0 - 0.0108, -100.0); // ≈ 1.2 km
    expect(gapMinutes(lead, m), closeTo(1.0, 0.05));
  });
}
