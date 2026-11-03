import 'dart:convert';

import 'package:drivalry/car/car_bridge.dart';
import 'package:drivalry/car/car_snapshot.dart';
import 'package:drivalry/data/convoy/eta.dart';
import 'package:drivalry/data/convoy/lost_sheep.dart';
import 'package:drivalry/data/crash/crash_monitor.dart';
import 'package:drivalry/data/google/places_client.dart';
import 'package:drivalry/data/repos/convoy_models.dart';
import 'package:drivalry/features/convoy/live/convoy_live.dart';
import 'package:drivalry/features/convoy/positions/peer_positions.dart';
import 'package:drivalry/features/convoy/radio/radio_controller.dart';
import 'package:drivalry/features/cues/live_limit.dart';
import 'package:drivalry/tracking/tracking_controller.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter_test/flutter_test.dart';

const _now = 1_762_200_000_000;

TrackingUiState _active({double speed = 13.4, double? lat, double? lon}) =>
    TrackingUiState(
      plugin: const TrackingState(
        phase: TrackingPhase.active,
        tripId: 't1',
        tripStartedAt: _now - 600_000,
      ),
      live: LiveTripStats(
        tripId: 't1',
        startedAt: _now - 600_000,
        lastFixT: _now,
        speedMps: speed,
        distanceM: 8_046.7,
        fixCount: 600,
        lastLat: lat ?? 37.0,
        lastLon: lon ?? -122.0,
      ),
      booted: true,
    );

LiveLimitState _limit({
  String tripId = 't1',
  double? limitMps = 15.65, // 35 mph
  double speedMps = 13.4, // 30 mph
  double confidence = 0.9,
}) => LiveLimitState(
  tripId: tripId,
  limitMps: limitMps,
  posted: limitMps == null ? null : 35,
  unitLabel: 'mph',
  roadName: 'Elm St',
  confidence: confidence,
  speedMps: speedMps,
  updatedAt: _now,
);

ConvoyMember _member(String id, {String role = 'member'}) => ConvoyMember(
  userId: id,
  handle: id,
  displayName: id.toUpperCase(),
  role: role,
  joinedAt: DateTime.fromMillisecondsSinceEpoch(_now - 3_600_000),
);

PeerPosition _pos(String id, double lat, double lon, {double? speed}) =>
    PeerPosition(
      userId: id,
      t: _now - 2000,
      lat: lat,
      lon: lon,
      source: PositionSource.mesh,
      speed: speed,
    );

ConvoyStop _stop(
  String id,
  String name, {
  StopStatus status = StopStatus.proposed,
  Map<String, int> votes = const {},
  double lat = 37.05,
  double lon = -122.0,
}) => ConvoyStop(
  id: id,
  convoyId: 'c1',
  proposedBy: 'me',
  category: StopCategory.food,
  name: name,
  lat: lat,
  lon: lon,
  status: status,
  createdAt: DateTime.fromMillisecondsSinceEpoch(_now - 60_000),
  votes: votes,
);

final _convoy = Convoy(
  id: 'c1',
  name: 'Lake run',
  createdBy: 'leader',
  status: ConvoyStatus.active,
  inviteCode: 'abc123',
  createdAt: DateTime.fromMillisecondsSinceEpoch(_now - 7_200_000),
  destination: const Destination(name: 'Lake', lat: 37.2, lon: -122.0),
  memberCount: 3,
);

void main() {
  group('CarDrive', () {
    test('idle app builds an idle, non-live snapshot', () {
      final s = buildCarSnapshot(
        const CarSnapshotInputs(tracking: TrackingUiState(), nowMs: _now),
      );
      expect(s.drive.phase, TrackingPhase.idle);
      expect(s.drive.status, 'idle');
      expect(s.isLive, isFalse);
      expect(s.convoy, isNull);
      expect(s.talk.available, isFalse);
      expect(s.talk.reason, 'signedOut');
    });

    test('under the limit is clean, with the limit and road attached', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(),
          nowMs: _now,
          liveLimit: _limit(),
          me: 'me',
        ),
      );
      expect(s.drive.recording, isTrue);
      expect(s.drive.posted, 35);
      expect(s.drive.road, 'Elm St');
      expect(s.drive.speedMps, 13.4);
      expect(s.drive.status, 'clean');
      expect(s.drive.statusText(SpeedUnits.mph), 'Clean so far');
      expect(s.drive.elapsedS, 600);
      expect(s.isLive, isTrue);
      expect(s.talk.reason, 'noConvoy');
    });

    test('over the limit says how far, in the posted unit', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(speed: 18.8),
          nowMs: _now,
          liveLimit: _limit(speedMps: 18.8), // 42 mph
        ),
      );
      expect(s.drive.status, 'over');
      expect(s.drive.statusText(SpeedUnits.mph), '7 over');
      expect(s.drive.statusText(SpeedUnits.kmh), '11 over');
    });

    test('earlier speeding shows as "over so far" once back under', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(),
          nowMs: _now,
          liveLimit: _limit(),
          tally: const SpeedingTally(tripId: 't1', seconds: 95),
        ),
      );
      expect(s.drive.status, 'cleanish');
      expect(s.drive.statusText(SpeedUnits.mph), '1 min over so far');
      expect(s.drive.speedingS, 95);
    });

    test('a tally from another trip does not carry over', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(),
          nowMs: _now,
          liveLimit: _limit(),
          tally: const SpeedingTally(tripId: 'old', seconds: 95),
        ),
      );
      expect(s.drive.speedingS, 0);
      expect(s.drive.status, 'clean');
    });

    test('no usable limit is said plainly, never "clean"', () {
      final noPack = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(),
          nowMs: _now,
          liveLimit: _limit(limitMps: null),
        ),
      );
      expect(noPack.drive.hasLimit, isFalse);
      expect(noPack.drive.status, 'noLimit');
      expect(noPack.drive.statusText(SpeedUnits.mph), 'No limit data here');

      final unsure = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(),
          nowMs: _now,
          liveLimit: _limit(confidence: 0.4),
        ),
      );
      expect(unsure.drive.posted, isNull, reason: 'silent where unsure');
      expect(unsure.drive.status, 'noLimit');
    });

    test('a live limit for a different trip is ignored', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(),
          nowMs: _now,
          liveLimit: _limit(tripId: 'stale'),
        ),
      );
      expect(s.drive.posted, isNull);
      expect(s.drive.speedMps, 13.4, reason: 'falls back to the recorder');
    });

    test('passenger wins over everything else while recording', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(speed: 18.8),
          nowMs: _now,
          liveLimit: _limit(speedMps: 18.8),
          passengerMarked: true,
        ),
      );
      expect(s.drive.passenger, isTrue);
      expect(s.drive.status, 'passenger');
      expect(s.drive.statusText(SpeedUnits.mph), 'Passenger · not scored');
    });

    test('tentative reads as a possible drive', () {
      final s = buildCarSnapshot(
        const CarSnapshotInputs(
          tracking: TrackingUiState(
            plugin: TrackingState(phase: TrackingPhase.tentative, tripId: 't2'),
          ),
          nowMs: _now,
          passengerMarked: true,
        ),
      );
      expect(s.drive.status, 'tentative');
      expect(s.drive.passenger, isTrue);
      expect(s.drive.statusText(SpeedUnits.mph), 'Looks like a drive');
    });
  });

  group('SpeedingTally', () {
    test('credits continuous speeding, not gaps or under-tolerance', () {
      var t = SpeedingTally.empty;
      t = t.update(_limit(speedMps: 18.8).copyWith(updatedAt: 1000));
      expect(t.seconds, 0, reason: 'first update starts the clock');
      t = t.update(_limit(speedMps: 18.8).copyWith(updatedAt: 2000));
      t = t.update(_limit(speedMps: 18.8).copyWith(updatedAt: 3000));
      expect(t.seconds, 2);
      // 1 mph over is inside the tolerance.
      t = t.update(_limit(speedMps: 16.1).copyWith(updatedAt: 4000));
      expect(t.seconds, 2);
      // A 20 s hole (tunnel) is not credited.
      t = t.update(_limit(speedMps: 18.8).copyWith(updatedAt: 24000));
      expect(t.seconds, 2);
      t = t.update(_limit(speedMps: 18.8).copyWith(updatedAt: 25000));
      expect(t.seconds, 3);
    });

    test('a new trip starts from zero', () {
      var t = const SpeedingTally(tripId: 't1', seconds: 40, lastAt: 1000);
      t = t.update(
        _limit(tripId: 't2', speedMps: 18.8).copyWith(updatedAt: 2000),
      );
      expect(t.tripId, 't2');
      expect(t.seconds, 0);
    });
  });

  group('CarConvoy', () {
    test('members sort leader first then nearest; stops filter and rank', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(lat: 37.0, lon: -122.0),
          nowMs: _now,
          me: 'me',
          convoy: _convoy,
          members: [
            _member('far'),
            _member('me'),
            _member('leader', role: 'leader'),
            _member('near'),
            ConvoyMember(
              userId: 'gone',
              handle: 'gone',
              displayName: 'Gone',
              role: 'member',
              joinedAt: DateTime.fromMillisecondsSinceEpoch(_now),
              leftAt: DateTime.fromMillisecondsSinceEpoch(_now),
            ),
          ],
          positions: {
            'far': _pos('far', 37.1, -122.0, speed: 20),
            'near': _pos('near', 37.001, -122.0),
            'leader': _pos('leader', 37.05, -122.0),
            'me': _pos('me', 37.0, -122.0),
          },
          etas: const {
            'leader': EtaInfo(
              userId: 'leader',
              seconds: 900,
              estimated: false,
              at: _now,
            ),
          },
          lost: const {'far': LostSheep(userId: 'far', reason: 'behind')},
          regroup: const RegroupPin(
            lat: 37.02,
            lon: -122.0,
            setBy: 'leader',
            at: _now,
          ),
          radio: const RadioState(phase: RadioPhase.on, talking: {'near'}),
          stops: [
            _stop('s1', 'Diner', votes: {'me': 1, 'far': -1}),
            _stop('s2', 'Gas', status: StopStatus.accepted),
            _stop('s3', 'Nope', status: StopStatus.rejected),
            _stop('s4', 'Done', status: StopStatus.done),
            _stop('s5', 'Lookout', votes: {'leader': 1, 'near': 1}),
          ],
        ),
      );
      final c = s.convoy!;
      expect(c.isActive, isTrue);
      expect(c.leaderId, 'leader');
      expect(c.destination?.name, 'Lake');
      expect(c.regroup?.name, 'Regroup · LEADER');
      expect(
        [for (final m in c.members) m.id],
        ['leader', 'me', 'near', 'far'],
      );
      final leader = c.members.first;
      expect(leader.isLeader, isTrue);
      expect(leader.etaS, 900);
      expect(leader.distanceM, closeTo(5560, 60));
      expect(c.members[1].isMe, isTrue);
      expect(c.members[2].talking, isTrue);
      expect(c.members[3].lost, 'behind');
      expect(c.members[3].speedMps, 20);

      expect([for (final st in c.stops) st.id], ['s2', 's5', 's1']);
      expect(c.stops[2].myVote, 1);
      expect(c.stops[2].up, 1);
      expect(c.stops[2].down, 1);
      expect(c.stops[0].distanceM, closeTo(5560, 60));

      expect(s.talk.available, isTrue);
      expect(s.talk.on, isTrue);
      expect(s.talk.talking, ['NEAR']);
      expect(s.talk.reason, isNull);
    });

    test('a planning convoy shows but talk is not available', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: const TrackingUiState(),
          nowMs: _now,
          me: 'me',
          convoy: Convoy(
            id: 'c2',
            name: 'Tomorrow',
            createdBy: 'me',
            status: ConvoyStatus.planning,
            inviteCode: 'zzz',
            createdAt: DateTime.fromMillisecondsSinceEpoch(_now),
          ),
          members: [_member('me', role: 'leader')],
        ),
      );
      expect(s.convoy?.status, 'planning');
      expect(s.isLive, isTrue);
      expect(s.talk.available, isFalse);
      expect(s.talk.reason, 'convoyNotActive');
    });

    test('radio off while active is available with reason off', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: const TrackingUiState(),
          nowMs: _now,
          me: 'me',
          convoy: _convoy,
          members: [
            _member('me'),
            _member('leader', role: 'leader'),
          ],
          radio: const RadioState(phase: RadioPhase.noPermission),
        ),
      );
      expect(s.talk.available, isTrue);
      expect(s.talk.on, isFalse);
      expect(s.talk.reason, 'noPermission');
    });
  });

  group('JSON', () {
    test('round-trips a full snapshot and carries the version', () {
      final s = buildCarSnapshot(
        CarSnapshotInputs(
          tracking: _active(),
          nowMs: _now,
          liveLimit: _limit(speedMps: 18.8),
          tally: const SpeedingTally(tripId: 't1', seconds: 12),
          me: 'me',
          units: SpeedUnits.kmh,
          convoy: _convoy,
          members: [
            _member('me'),
            _member('leader', role: 'leader'),
          ],
          positions: {'leader': _pos('leader', 37.05, -122.0)},
          stops: [
            _stop('s1', 'Diner', votes: {'me': 1}),
          ],
          radio: const RadioState(phase: RadioPhase.on, holding: true),
          crash: const CrashUiState(secondsLeft: 0),
        ),
      );
      final wire = jsonDecode(jsonEncode(s.toJson(at: _now)));
      expect(wire['v'], carSnapshotVersion);
      expect(wire['at'], _now);
      expect(wire['units'], 'kmh');
      expect(wire['drive']['status'], 'over');
      final back = CarSnapshot.fromJson(wire as Map<String, dynamic>);
      expect(back, s);
      expect(back.convoy!.stops.single.myVote, 1);
      expect(back.talk.holding, isTrue);
      expect(back.units, SpeedUnits.kmh);
    });

    test('contentJson is encoded once per instance and spliced on send', () {
      const s = CarSnapshot(
        drive: CarDrive(phase: TrackingPhase.active, tripId: 't1'),
      );
      expect(identical(s.contentJson, s.contentJson), isTrue);
      final wire = snapshotWire(s.contentJson, 5);
      expect(wire, startsWith('{"at":5,"v":'));
      expect(
        jsonDecode(wire),
        equals({...jsonDecode(s.contentJson) as Map, 'at': 5}),
      );
    });

    test('equality ignores the timestamp', () {
      final a = buildCarSnapshot(
        CarSnapshotInputs(tracking: _active(), nowMs: _now),
      );
      final b = buildCarSnapshot(
        CarSnapshotInputs(tracking: _active(), nowMs: _now + 500),
      );
      expect(a, b, reason: 'same elapsed second');
      expect(a.contentJson, isNot(contains('"at"')));
    });

    test('parses a minimal payload with defaults', () {
      final s = CarSnapshot.fromJson(const {'v': 1, 'drive': {}});
      expect(s.drive.phase, TrackingPhase.idle);
      expect(s.convoy, isNull);
      expect(s.talk.available, isFalse);
      expect(s.crash.countingDown, isFalse);
    });
  });
}
