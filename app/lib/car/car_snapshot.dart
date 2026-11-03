import 'dart:convert';

import 'package:drivalry_scoring/drivalry_scoring.dart'
    show SpeedUnits, mpsToKmh, mpsToMph;

import '../data/convoy/eta.dart';
import '../data/convoy/lost_sheep.dart';
import '../data/crash/crash_monitor.dart';
import '../data/google/routes_client.dart' show LatLon;
import '../data/repos/convoy_models.dart';
import '../features/convoy/live/convoy_live.dart' show RegroupPin;
import '../features/convoy/positions/peer_positions.dart';
import '../features/convoy/radio/radio_controller.dart';
import '../features/cues/live_limit.dart';
import '../tracking/tracking_controller.dart';
import '../tracking/tracking_models.dart';

/// Wire version of the snapshot JSON (docs/04 §3.3). Bump when a field
/// changes meaning; adding optional fields does not need a bump.
const int carSnapshotVersion = 1;

/// Speeding tolerance before a second counts against "Clean so far"
/// (3 mph, the same slack the spoken cues use).
const double carSpeedingToleranceMps = 1.34;

/// Everything a car screen (Android Auto today, CarPlay later) needs to
/// render, as one immutable value. Built on the phone from the live Riverpod
/// state and pushed over `app.drivalry/car` as JSON; the native side never
/// reads the database or the convoy channel itself (docs/04 §4).
class CarSnapshot {
  const CarSnapshot({
    required this.drive,
    this.convoy,
    this.talk = const CarTalk(),
    this.crash = const CarCrash(),
    this.me,
    this.units = SpeedUnits.mph,
  });

  static const CarSnapshot idle = CarSnapshot(drive: CarDrive.idle);

  final CarDrive drive;
  final CarConvoy? convoy;
  final CarTalk talk;
  final CarCrash crash;

  /// My user id, so the car screen can mark my own row.
  final String? me;
  final SpeedUnits units;

  /// Whether anything is happening that deserves a car screen at all.
  bool get isLive => drive.phase != TrackingPhase.idle || convoy != null;

  Map<String, Object?> toJson({int? at}) => {
    'v': carSnapshotVersion,
    'at': ?at,
    'me': me,
    'units': units == SpeedUnits.mph ? 'mph' : 'kmh',
    'drive': drive.toJson(),
    'convoy': convoy?.toJson(),
    'talk': talk.toJson(),
    'crash': crash.toJson(),
  };

  /// The JSON without the timestamp, used to decide whether a resend is
  /// needed. Snapshots are immutable, so it is encoded once per instance and
  /// shared by equality, hashing and the bridge's send.
  String get contentJson => _jsonCache[this] ??= jsonEncode(toJson());
  static final Expando<String> _jsonCache = Expando<String>('CarSnapshot');

  static CarSnapshot fromJson(Map<String, dynamic> j) => CarSnapshot(
    drive: CarDrive.fromJson(_map(j['drive']) ?? const {}),
    convoy: _map(j['convoy'])?.let(CarConvoy.fromJson),
    talk: CarTalk.fromJson(_map(j['talk']) ?? const {}),
    crash: CarCrash.fromJson(_map(j['crash']) ?? const {}),
    me: j['me'] as String?,
    units: j['units'] == 'kmh' ? SpeedUnits.kmh : SpeedUnits.mph,
  );

  @override
  bool operator ==(Object other) =>
      other is CarSnapshot && other.contentJson == contentJson;

  @override
  int get hashCode => contentJson.hashCode;
}

/// What the recorder is doing and the road under the car.
class CarDrive {
  const CarDrive({
    this.phase = TrackingPhase.idle,
    this.tripId,
    this.startedAt,
    this.elapsedS,
    this.distanceM = 0,
    this.speedMps,
    this.limitMps,
    this.posted,
    this.limitUnit = 'mph',
    this.road,
    this.overMps,
    this.speedingS = 0,
    this.passenger = false,
  });

  static const idle = CarDrive();

  final TrackingPhase phase;
  final String? tripId;
  final int? startedAt;
  final int? elapsedS;
  final double distanceM;
  final double? speedMps;

  /// Limit for the direction of travel, m/s; null when unknown or not
  /// confident enough to act on (docs/01 §4.2).
  final double? limitMps;
  final int? posted;

  /// `mph` or `km/h`: the unit the limit is posted in.
  final String limitUnit;
  final String? road;

  /// How far over the limit right now, m/s (0 when at or under).
  final double? overMps;

  /// Seconds spent over the limit (past the tolerance) so far this trip.
  final int speedingS;

  /// The driver tapped "Passenger": the trip will not be scored.
  final bool passenger;

  bool get recording => phase == TrackingPhase.active;
  bool get hasLimit => limitMps != null;
  bool get overNow => (overMps ?? 0) > carSpeedingToleranceMps;

  /// One of `idle`, `tentative`, `passenger`, `over`, `clean`, `noLimit`,
  /// `cleanish` (was over earlier, not now).
  String get status {
    if (phase == TrackingPhase.idle) return 'idle';
    if (phase == TrackingPhase.tentative) return 'tentative';
    if (passenger) return 'passenger';
    if (overNow) return 'over';
    if (speedingS > 0) return 'cleanish';
    if (!hasLimit) return 'noLimit';
    return 'clean';
  }

  /// The short status line the notification and the Drive pane show.
  String statusText(SpeedUnits units) => switch (status) {
    'idle' => 'Not recording',
    'tentative' => 'Looks like a drive',
    'passenger' => 'Passenger · not scored',
    'over' => '${_display(overMps!, units)} over',
    'cleanish' => '${_elapsedLabel(speedingS)} over so far',
    'noLimit' => 'No limit data here',
    _ => 'Clean so far',
  };

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'tripId': tripId,
    'startedAt': startedAt,
    'elapsedS': elapsedS,
    'distanceM': _round(distanceM),
    'speedMps': speedMps?.let(_round),
    'limitMps': limitMps?.let(_round),
    'posted': posted,
    'limitUnit': limitUnit,
    'road': road,
    'overMps': overMps?.let(_round),
    'speedingS': speedingS,
    'passenger': passenger,
    'status': status,
  };

  static CarDrive fromJson(Map<String, dynamic> j) => CarDrive(
    phase: TrackingPhase.fromWire(j['phase'] as String?),
    tripId: j['tripId'] as String?,
    startedAt: (j['startedAt'] as num?)?.toInt(),
    elapsedS: (j['elapsedS'] as num?)?.toInt(),
    distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0,
    speedMps: (j['speedMps'] as num?)?.toDouble(),
    limitMps: (j['limitMps'] as num?)?.toDouble(),
    posted: (j['posted'] as num?)?.toInt(),
    limitUnit: j['limitUnit'] as String? ?? 'mph',
    road: j['road'] as String?,
    overMps: (j['overMps'] as num?)?.toDouble(),
    speedingS: (j['speedingS'] as num?)?.toInt() ?? 0,
    passenger: j['passenger'] as bool? ?? false,
  );
}

/// A point the car screen can pin.
class CarPlace {
  const CarPlace({required this.name, required this.lat, required this.lon});
  final String name;
  final double lat;
  final double lon;

  Map<String, Object?> toJson() => {'name': name, 'lat': lat, 'lon': lon};

  static CarPlace? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final lat = j['lat'];
    final lon = j['lon'];
    if (lat is! num || lon is! num) return null;
    return CarPlace(
      name: j['name'] as String? ?? '',
      lat: lat.toDouble(),
      lon: lon.toDouble(),
    );
  }
}

class CarMember {
  const CarMember({
    required this.id,
    required this.name,
    required this.initials,
    this.isMe = false,
    this.isLeader = false,
    this.lat,
    this.lon,
    this.speedMps,
    this.etaS,
    this.distanceM,
    this.lost,
    this.talking = false,
    this.atMs,
  });

  final String id;
  final String name;
  final String initials;
  final bool isMe;
  final bool isLeader;
  final double? lat;
  final double? lon;
  final double? speedMps;

  /// Their ETA to the next target, seconds, as they reported it.
  final int? etaS;

  /// Straight-line distance from me, metres.
  final double? distanceM;

  /// `behind` or `silent` when the lost-sheep detector flags them.
  final String? lost;
  final bool talking;

  /// Fix time of the position shown.
  final int? atMs;

  bool get hasPosition => lat != null && lon != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'initials': initials,
    'isMe': isMe,
    'isLeader': isLeader,
    'lat': lat,
    'lon': lon,
    'speedMps': speedMps?.let(_round),
    'etaS': etaS,
    'distanceM': distanceM?.let(_round),
    'lost': lost,
    'talking': talking,
    'atMs': atMs,
  };

  static CarMember fromJson(Map<String, dynamic> j) => CarMember(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    initials: j['initials'] as String? ?? '',
    isMe: j['isMe'] as bool? ?? false,
    isLeader: j['isLeader'] as bool? ?? false,
    lat: (j['lat'] as num?)?.toDouble(),
    lon: (j['lon'] as num?)?.toDouble(),
    speedMps: (j['speedMps'] as num?)?.toDouble(),
    etaS: (j['etaS'] as num?)?.toInt(),
    distanceM: (j['distanceM'] as num?)?.toDouble(),
    lost: j['lost'] as String?,
    talking: j['talking'] as bool? ?? false,
    atMs: (j['atMs'] as num?)?.toInt(),
  );
}

class CarStop {
  const CarStop({
    required this.id,
    required this.name,
    required this.category,
    required this.status,
    required this.lat,
    required this.lon,
    this.up = 0,
    this.down = 0,
    this.myVote = 0,
    this.distanceM,
  });

  final String id;
  final String name;

  /// `StopCategory.wire`.
  final String category;

  /// `StopStatus.wire`.
  final String status;
  final double lat;
  final double lon;
  final int up;
  final int down;
  final int myVote;
  final double? distanceM;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'status': status,
    'lat': lat,
    'lon': lon,
    'up': up,
    'down': down,
    'myVote': myVote,
    'distanceM': distanceM?.let(_round),
  };

  static CarStop fromJson(Map<String, dynamic> j) => CarStop(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    category: j['category'] as String? ?? 'food',
    status: j['status'] as String? ?? 'proposed',
    lat: (j['lat'] as num?)?.toDouble() ?? 0,
    lon: (j['lon'] as num?)?.toDouble() ?? 0,
    up: (j['up'] as num?)?.toInt() ?? 0,
    down: (j['down'] as num?)?.toInt() ?? 0,
    myVote: (j['myVote'] as num?)?.toInt() ?? 0,
    distanceM: (j['distanceM'] as num?)?.toDouble(),
  );
}

class CarConvoy {
  const CarConvoy({
    required this.id,
    required this.name,
    required this.status,
    this.leaderId,
    this.destination,
    this.regroup,
    this.members = const [],
    this.stops = const [],
  });

  final String id;
  final String name;

  /// `planning` or `active`.
  final String status;
  final String? leaderId;
  final CarPlace? destination;
  final CarPlace? regroup;

  /// Leader first, then nearest first; members without a position last.
  final List<CarMember> members;

  /// Accepted stops first, then proposals by score; rejected and done
  /// stops are left out.
  final List<CarStop> stops;

  bool get isActive => status == 'active';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'status': status,
    'leaderId': leaderId,
    'destination': destination?.toJson(),
    'regroup': regroup?.toJson(),
    'members': [for (final m in members) m.toJson()],
    'stops': [for (final s in stops) s.toJson()],
  };

  static CarConvoy fromJson(Map<String, dynamic> j) => CarConvoy(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    status: j['status'] as String? ?? 'planning',
    leaderId: j['leaderId'] as String?,
    destination: CarPlace.fromJson(_map(j['destination'])),
    regroup: CarPlace.fromJson(_map(j['regroup'])),
    members: [
      for (final m in (j['members'] as List? ?? const []))
        if (_map(m) case final mm?) CarMember.fromJson(mm),
    ],
    stops: [
      for (final s in (j['stops'] as List? ?? const []))
        if (_map(s) case final ss?) CarStop.fromJson(ss),
    ],
  );
}

/// Push-to-talk as the car sees it (docs/10 §9).
class CarTalk {
  const CarTalk({
    this.available = false,
    this.on = false,
    this.holding = false,
    this.talking = const [],
    this.peers = 0,
    this.reason,
  });

  /// There is an active convoy to talk to and the phone can run the radio.
  final bool available;

  /// The radio session is up (mesh connected or connecting).
  final bool on;
  final bool holding;

  /// Display names of the people talking right now.
  final List<String> talking;
  final int peers;

  /// Why `available` is false, or why `on` is false while available:
  /// `noConvoy`, `convoyNotActive`, `signedOut`, `off`, `starting`,
  /// `noPermission`, `error`.
  final String? reason;

  Map<String, Object?> toJson() => {
    'available': available,
    'on': on,
    'holding': holding,
    'talking': talking,
    'peers': peers,
    'reason': reason,
  };

  static CarTalk fromJson(Map<String, dynamic> j) => CarTalk(
    available: j['available'] as bool? ?? false,
    on: j['on'] as bool? ?? false,
    holding: j['holding'] as bool? ?? false,
    talking: [for (final t in (j['talking'] as List? ?? const [])) '$t'],
    peers: (j['peers'] as num?)?.toInt() ?? 0,
    reason: j['reason'] as String?,
  );
}

class CarCrash {
  const CarCrash({
    this.countingDown = false,
    this.secondsLeft = 0,
    this.unresolved = false,
  });

  final bool countingDown;
  final int secondsLeft;

  /// An alert went out and the driver has not said they are OK.
  final bool unresolved;

  Map<String, Object?> toJson() => {
    'countingDown': countingDown,
    'secondsLeft': secondsLeft,
    'unresolved': unresolved,
  };

  static CarCrash fromJson(Map<String, dynamic> j) => CarCrash(
    countingDown: j['countingDown'] as bool? ?? false,
    secondsLeft: (j['secondsLeft'] as num?)?.toInt() ?? 0,
    unresolved: j['unresolved'] as bool? ?? false,
  );
}

/// Counts seconds over the limit for the trip in progress, from the live
/// limit updates. Pure, so it is easy to test; the bridge feeds it.
class SpeedingTally {
  const SpeedingTally({this.tripId, this.seconds = 0, this.lastAt});

  static const empty = SpeedingTally();

  final String? tripId;
  final int seconds;
  final int? lastAt;

  /// Longest gap between two updates that still counts as continuous
  /// speeding; a longer gap (tunnel, app paused) is not credited.
  static const int maxGapMs = 5000;

  SpeedingTally update(LiveLimitState s) {
    if (s.tripId != tripId) {
      // New trip: start over, remembering only this update's time.
      return SpeedingTally(tripId: s.tripId, seconds: 0, lastAt: s.updatedAt);
    }
    final last = lastAt;
    final over = (s.overByMps ?? 0) > carSpeedingToleranceMps;
    if (!over || last == null) {
      return SpeedingTally(
        tripId: tripId,
        seconds: seconds,
        lastAt: s.updatedAt,
      );
    }
    final gap = s.updatedAt - last;
    final credit = gap > 0 && gap <= maxGapMs ? gap : 0;
    return SpeedingTally(
      tripId: tripId,
      seconds: seconds + credit ~/ 1000,
      lastAt: s.updatedAt,
    );
  }

  SpeedingTally reset() => SpeedingTally.empty;
}

/// Everything the builder reads. A plain bag so the builder is a pure
/// function and tests can drive it without Riverpod.
class CarSnapshotInputs {
  const CarSnapshotInputs({
    required this.tracking,
    required this.nowMs,
    this.liveLimit,
    this.tally = SpeedingTally.empty,
    this.passengerMarked = false,
    this.convoy,
    this.members = const [],
    this.stops = const [],
    this.positions = const {},
    this.etas = const {},
    this.lost = const {},
    this.regroup,
    this.radio,
    this.crash = const CrashUiState(),
    this.me,
    this.units = SpeedUnits.mph,
  });

  final TrackingUiState tracking;
  final int nowMs;
  final LiveLimitState? liveLimit;
  final SpeedingTally tally;
  final bool passengerMarked;
  final Convoy? convoy;
  final List<ConvoyMember> members;
  final List<ConvoyStop> stops;
  final Map<String, PeerPosition> positions;
  final Map<String, EtaInfo> etas;
  final Map<String, LostSheep> lost;
  final RegroupPin? regroup;
  final RadioState? radio;
  final CrashUiState crash;
  final String? me;
  final SpeedUnits units;
}

/// Assembles the snapshot. No I/O.
CarSnapshot buildCarSnapshot(CarSnapshotInputs i) {
  final plugin = i.tracking.plugin;
  final live = i.tracking.live;
  final limit = i.liveLimit;
  final limitForTrip =
      limit != null && limit.tripId != null && limit.tripId == plugin.tripId
      ? limit
      : null;
  final usable = limitForTrip != null && limitForTrip.hasLimit;

  final drive = CarDrive(
    phase: plugin.phase,
    tripId: plugin.tripId,
    startedAt: plugin.tripStartedAt ?? live?.startedAt,
    elapsedS: live?.elapsedAt(i.nowMs).inSeconds,
    distanceM: live?.distanceM ?? 0,
    speedMps: limitForTrip?.speedMps ?? live?.speedMps,
    limitMps: usable ? limitForTrip.limitMps : null,
    posted: usable ? limitForTrip.posted : null,
    limitUnit: limitForTrip?.unitLabel ?? 'mph',
    road: usable ? limitForTrip.roadName : null,
    overMps: usable ? limitForTrip.overByMps : null,
    speedingS: i.tally.tripId == plugin.tripId ? i.tally.seconds : 0,
    passenger: i.passengerMarked && plugin.phase != TrackingPhase.idle,
  );

  final myPos = _myPosition(i);
  final convoy = i.convoy?.let((c) => _buildConvoy(i, c, myPos));
  final talk = _buildTalk(i, convoy);
  final crash = CarCrash(
    countingDown: i.crash.countingDown,
    secondsLeft: i.crash.secondsLeft,
    unresolved: i.crash.unresolved != null,
  );
  return CarSnapshot(
    drive: drive,
    convoy: convoy,
    talk: talk,
    crash: crash,
    me: i.me,
    units: i.units,
  );
}

LatLon? _myPosition(CarSnapshotInputs i) {
  final live = i.tracking.live;
  if (live?.lastLat != null && live?.lastLon != null) {
    return LatLon(live!.lastLat!, live.lastLon!);
  }
  final me = i.me;
  final p = me == null ? null : i.positions[me];
  return p == null ? null : LatLon(p.lat, p.lon);
}

CarConvoy _buildConvoy(CarSnapshotInputs i, Convoy c, LatLon? myPos) {
  final names = {for (final m in i.members) m.userId: m.name};
  final members = <CarMember>[];
  for (final m in i.members) {
    if (!m.isPresent) continue;
    final p = i.positions[m.userId];
    final eta = i.etas[m.userId];
    final here = p == null ? null : LatLon(p.lat, p.lon);
    members.add(
      CarMember(
        id: m.userId,
        name: m.name,
        initials: m.initials,
        isMe: m.userId == i.me,
        isLeader: m.userId == c.createdBy,
        lat: p?.lat,
        lon: p?.lon,
        speedMps: p?.speed,
        etaS: eta?.seconds,
        distanceM: here != null && myPos != null
            ? myPos.distanceTo(here)
            : null,
        lost: i.lost[m.userId]?.reason,
        talking: i.radio?.talking.contains(m.userId) ?? false,
        atMs: p?.t,
      ),
    );
  }
  members.sort((a, b) {
    if (a.isLeader != b.isLeader) return a.isLeader ? -1 : 1;
    final da = a.distanceM;
    final db = b.distanceM;
    if (da == null && db == null) return a.name.compareTo(b.name);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });

  final stops = <CarStop>[];
  for (final s in i.stops) {
    if (s.status == StopStatus.rejected || s.status == StopStatus.done) {
      continue;
    }
    stops.add(
      CarStop(
        id: s.id,
        name: s.name,
        category: s.category.wire,
        status: s.status.wire,
        lat: s.lat,
        lon: s.lon,
        up: s.upVotes,
        down: s.downVotes,
        myVote: i.me == null ? 0 : (s.votes[i.me!] ?? 0),
        distanceM: myPos?.distanceTo(LatLon(s.lat, s.lon)),
      ),
    );
  }
  stops.sort((a, b) {
    final aa = a.status == 'accepted';
    final ba = b.status == 'accepted';
    if (aa != ba) return aa ? -1 : 1;
    final sa = a.up - a.down;
    final sb = b.up - b.down;
    if (sa != sb) return sb.compareTo(sa);
    return a.name.compareTo(b.name);
  });

  final d = c.destination;
  final r = i.regroup;
  return CarConvoy(
    id: c.id,
    name: c.name,
    status: c.isActive ? 'active' : 'planning',
    leaderId: c.createdBy,
    destination: d == null
        ? null
        : CarPlace(name: d.name, lat: d.lat, lon: d.lon),
    regroup: r == null
        ? null
        : CarPlace(
            name: r.name ?? 'Regroup · ${names[r.setBy] ?? 'leader'}',
            lat: r.lat,
            lon: r.lon,
          ),
    members: members,
    stops: stops,
  );
}

CarTalk _buildTalk(CarSnapshotInputs i, CarConvoy? convoy) {
  if (i.me == null) return const CarTalk(reason: 'signedOut');
  if (convoy == null) return const CarTalk(reason: 'noConvoy');
  if (!convoy.isActive) return const CarTalk(reason: 'convoyNotActive');
  final r = i.radio;
  final names = {for (final m in convoy.members) m.id: m.name};
  final talking = [
    for (final id in r?.talking ?? const <String>{}) names[id] ?? 'Someone',
  ]..sort();
  final reason = switch (r?.phase) {
    null || RadioPhase.off => 'off',
    RadioPhase.starting => 'starting',
    RadioPhase.noPermission => 'noPermission',
    RadioPhase.error => 'error',
    RadioPhase.on => null,
  };
  return CarTalk(
    available: true,
    on: r?.on ?? false,
    holding: r?.holding ?? false,
    talking: talking,
    peers: r?.peers.length ?? 0,
    reason: reason,
  );
}

/// "3 mph" / "5 km/h" without the unit, for "n over" labels.
int _display(double mps, SpeedUnits units) =>
    (units == SpeedUnits.mph ? mpsToMph(mps) : mpsToKmh(mps)).round();

String _elapsedLabel(int seconds) {
  if (seconds >= 60) return '${seconds ~/ 60} min';
  return '$seconds s';
}

double _round(double v) => (v * 100).roundToDouble() / 100;

Map<String, dynamic>? _map(Object? o) =>
    o is Map ? o.cast<String, dynamic>() : null;

extension<T extends Object> on T {
  R let<R>(R Function(T) f) => f(this);
}
