import 'dart:async';
import 'dart:math' as math;

import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:uuid/uuid.dart';

import 'tracking_models.dart';
import 'tracking_port.dart';

/// A [TrackingPort] that replays a [TripInput] as the native plugin would
/// report it: `tentative` → `active` → `fixes` batches → `ended`
/// (docs/08 §7). Used by the Drive screen's "Simulate a drive" and by tests,
/// so the whole recorder → finalizer → UI path runs without a car.
class SimulatedTracking implements TrackingPort {
  SimulatedTracking({
    this.speedUp = 60,
    this.batchSize = 15,
    this.trigger = 'simulated',
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// Wall-clock acceleration. `0` or `infinity` plays back with no delays.
  final double speedUp;

  /// Fixes per `fixes` event.
  final int batchSize;
  final String trigger;
  final int Function() _now;

  // Synchronous so that when [play] returns every listener has seen every
  // event, in order, exactly as the plugin's live stream delivers them.
  final _events = StreamController<TrackingEvent>.broadcast(sync: true);
  final List<TrackingEvent> _spool = [];
  TrackingState _state = const TrackingState();
  bool _spoolAll = false;

  @override
  Stream<TrackingEvent> get events => _events.stream;

  /// When true every emitted event is also kept for [drainSpool] (to test
  /// replay). Default false: live only.
  set spoolEvents(bool v) => _spoolAll = v;

  void _emit(TrackingEvent e) {
    if (_spoolAll) _spool.add(e);
    _events.add(e);
  }

  /// Replays [input]. Returns the trip id when the `ended` event has been
  /// emitted. [rebaseToNow] shifts timestamps so the trip ends now.
  Future<String> play(
    TripInput input, {
    bool rebaseToNow = false,
    List<PhoneEvent>? phoneEvents,
  }) async {
    var samples = input.samples;
    var phone = phoneEvents ?? input.phoneEvents ?? const <PhoneEvent>[];
    if (samples.isEmpty) throw ArgumentError('trip has no samples');
    if (rebaseToNow) {
      final shift = _now() - samples.last.t;
      samples = [
        for (final s in samples)
          GpsSample(
            t: s.t + shift,
            lat: s.lat,
            lon: s.lon,
            speed: s.speed,
            accuracy: s.accuracy,
            heading: s.heading,
            altitude: s.altitude,
          ),
      ];
      phone = [for (final p in phone) PhoneEvent(t: p.t + shift, kind: p.kind)];
    }

    final tripId = const Uuid().v4();
    final start = samples.first.t;
    _state = TrackingState(
      phase: TrackingPhase.tentative,
      tripId: tripId,
      enabled: true,
      permissions: const TrackingPermissions(
        location: LocationPermission.always,
        preciseLocation: true,
        motion: SimplePermission.granted,
        notifications: SimplePermission.granted,
        bluetooth: SimplePermission.granted,
      ),
    );
    _emit(
      PhaseEvent(
        tripId: tripId,
        t: start - 20000,
        phase: TripPhaseSignal.tentative,
        reason: trigger,
      ),
    );
    await _wait(20000);
    _state = _state.copyWith(
      phase: TrackingPhase.active,
      tripId: tripId,
      tripStartedAt: start,
    );
    _emit(
      PhaseEvent(
        tripId: tripId,
        t: start,
        phase: TripPhaseSignal.active,
        reason: trigger,
        startedAt: start,
      ),
    );

    var phoneIdx = 0;
    for (var i = 0; i < samples.length; i += batchSize) {
      final end = math.min(i + batchSize, samples.length);
      final batch = samples.sublist(i, end);
      final batchT = batch.last.t;
      await _wait(batchT - (i == 0 ? start : samples[i - 1].t));
      // Phone events up to this batch, in order, before the batch lands.
      while (phoneIdx < phone.length && phone[phoneIdx].t <= batchT) {
        final p = phone[phoneIdx++];
        _emit(PhoneEventRaw(tripId: tripId, t: p.t, kind: _signalFor(p.kind)));
      }
      _emit(
        FixesEvent(
          tripId: tripId,
          t: batchT,
          fixes: [
            for (final s in batch)
              Fix(
                t: s.t,
                lat: s.lat,
                lon: s.lon,
                accuracy: s.accuracy,
                speed: s.speed,
                heading: s.heading,
                altitude: s.altitude,
              ),
          ],
        ),
      );
    }
    final endT = samples.last.t + 1000;
    _state = const TrackingState(
      enabled: true,
      permissions: TrackingPermissions(
        location: LocationPermission.always,
        preciseLocation: true,
        motion: SimplePermission.granted,
        notifications: SimplePermission.granted,
        bluetooth: SimplePermission.granted,
      ),
    );
    _emit(
      PhaseEvent(
        tripId: tripId,
        t: endT,
        phase: TripPhaseSignal.ended,
        reason: 'stationary',
      ),
    );
    return tripId;
  }

  static PhoneSignal _signalFor(PhoneEventKind k) => switch (k) {
    PhoneEventKind.unlock => PhoneSignal.unlock,
    PhoneEventKind.interaction => PhoneSignal.interaction,
    PhoneEventKind.callHandheld => PhoneSignal.callStart,
  };

  Future<void> _wait(int tripMs) async {
    if (speedUp <= 0 || speedUp.isInfinite || tripMs <= 0) return;
    final ms = (tripMs / speedUp).round();
    if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms));
  }

  void dispose() {
    _events.close();
  }

  // ------------------------------------------------------------ TrackingPort --

  @override
  Future<TrackingState> getState() async => _state;

  @override
  Future<TrackingState> setEnabled(bool enabled) async =>
      _state = _state.copyWith(enabled: enabled);

  @override
  Future<TrackingState> pauseUntil(int untilMs) async =>
      _state = _state.copyWith(pausedUntil: untilMs);

  @override
  Future<TrackingPermissions> requestPermissions() async => _state.permissions;

  @override
  Future<void> openSettings() async {}

  @override
  Future<TrackingState> forceStartTrip() async => _state;

  @override
  Future<TrackingState> forceEndTrip() async => _state;

  @override
  Future<List<TrackingEvent>> drainSpool() async {
    final out = List<TrackingEvent>.of(_spool);
    _spool.clear();
    return out;
  }

  @override
  Future<void> setMapsApiKey(String key) async {}

  @override
  Future<TrackingDiagnostics> getDiagnostics() async =>
      const TrackingDiagnostics(lastTriggerKind: 'simulated');
}

/// Builds a plausible trip from an installed pack: walks connected ways
/// from a start point, drives at the posted limit (plus a chosen amount of
/// speeding on some stretches) and drops a couple of phone unlocks.
///
/// The output has no segments: the matcher produces them, which is the point.
class RouteSynthesizer {
  RouteSynthesizer(
    this.pack, {
    math.Random? random,
    this.defaultSpeedMps = 13.4,
  }) : _rng = random ?? math.Random(7);

  final PackSource pack;
  final math.Random _rng;

  /// Cruise speed where the pack has no limit (about 30 mph).
  final double defaultSpeedMps;

  /// Returns null when no way is within 300 m of the start.
  TripInput? build({
    required double lat,
    required double lon,
    int durationS = 600,
    double speedingFraction = 0.25,
    double overBy = 6 * mph,
    int startT = defaultSyntheticStartT,
    String? id,
  }) {
    final cache = TileCache(pack);
    final startWay = _nearestWay(cache, lat, lon, 300);
    if (startWay == null) return null;

    final path = <({PackWay way, bool forward})>[];
    final visited = <int>{startWay.id};
    var way = startWay;
    var forward = _rng.nextBool() || way.oneway == 1;
    if (way.oneway == 2) forward = false;
    var length = 0.0;
    final targetM = durationS * defaultSpeedMps * 1.2;
    while (length < targetM && path.length < 60) {
      path.add((way: way, forward: forward));
      length += _wayLength(way);
      final next = _nextWay(cache, way, forward, visited);
      if (next == null) break;
      way = next.way;
      forward = next.forward;
      visited.add(way.id);
    }

    // Lay 1 Hz samples along the path.
    final samples = <GpsSample>[];
    var t = startT;
    var v = 0.0;
    final speeding = <bool>[];
    for (var i = 0; i < path.length; i++) {
      speeding.add(_rng.nextDouble() < speedingFraction);
    }
    double? prevLat, prevLon;
    for (var i = 0; i < path.length; i++) {
      final w = path[i].way;
      final fwd = path[i].forward;
      final limit = w.limitMps(forward: fwd);
      final target = (limit ?? defaultSpeedMps) + (speeding[i] ? overBy : -0.5);
      final pts = _orderedPoints(w, fwd);
      for (var k = 1; k < pts.length; k++) {
        final a = pts[k - 1];
        final b = pts[k];
        final segLen = haversine(a.$1, a.$2, b.$1, b.$2);
        if (segLen < 0.5) continue;
        final brg = bearing(a.$1, a.$2, b.$1, b.$2);
        var covered = 0.0;
        while (covered < segLen) {
          v = math.max(0.5, v + (target - v).clamp(-1.5, 1.5));
          covered += v;
          final f = math.min(1.0, covered / segLen);
          final la = a.$1 + (b.$1 - a.$1) * f;
          final lo = a.$2 + (b.$2 - a.$2) * f;
          if (prevLat != null && la == prevLat && lo == prevLon) continue;
          samples.add(
            GpsSample(
              t: t,
              lat: la,
              lon: lo,
              speed: v,
              accuracy: 5 + _rng.nextDouble() * 3,
              heading: brg,
            ),
          );
          prevLat = la;
          prevLon = lo;
          t += 1000;
          if (samples.length >= durationS) break;
        }
        if (samples.length >= durationS) break;
      }
      if (samples.length >= durationS) break;
    }
    if (samples.length < 30) return null;

    final n = samples.length;
    final phone = <PhoneEvent>[
      PhoneEvent(t: samples[n ~/ 3].t, kind: PhoneEventKind.unlock),
      PhoneEvent(t: samples[n ~/ 3].t + 8000, kind: PhoneEventKind.interaction),
    ];
    return TripInput(
      id: id ?? 'route-$startT',
      samples: samples,
      segments: const [],
      phoneEvents: phone,
    );
  }

  PackWay? _nearestWay(
    TileCache cache,
    double lat,
    double lon,
    double radiusM,
  ) {
    PackWay? best;
    var bestD = radiusM;
    for (final w in cache.waysNear(lat, lon)) {
      final d = _distanceToWay(w, lat, lon);
      if (d < bestD) {
        bestD = d;
        best = w;
      }
    }
    return best;
  }

  static double _distanceToWay(PackWay w, double lat, double lon) {
    var best = double.infinity;
    for (var i = 0; i < w.pointCount; i++) {
      final d = haversine(lat, lon, w.lats[i], w.lons[i]);
      if (d < best) best = d;
    }
    return best;
  }

  static double _wayLength(PackWay w) {
    var len = 0.0;
    for (var i = 1; i < w.pointCount; i++) {
      len += haversine(w.lats[i - 1], w.lons[i - 1], w.lats[i], w.lons[i]);
    }
    return len;
  }

  static List<(double, double)> _orderedPoints(PackWay w, bool forward) {
    final pts = [for (var i = 0; i < w.pointCount; i++) (w.lats[i], w.lons[i])];
    return forward ? pts : pts.reversed.toList();
  }

  ({PackWay way, bool forward})? _nextWay(
    TileCache cache,
    PackWay current,
    bool forward,
    Set<int> visited,
  ) {
    final endIdx = forward ? current.pointCount - 1 : 0;
    final endLat = current.lats[endIdx];
    final endLon = current.lons[endIdx];
    final candidates = <({PackWay way, bool forward})>[];
    for (final w in cache.waysNear(endLat, endLon)) {
      if (visited.contains(w.id) || w.roadClass == RoadClass.service) continue;
      final dStart = haversine(endLat, endLon, w.lats.first, w.lons.first);
      final dEnd = haversine(endLat, endLon, w.lats.last, w.lons.last);
      if (dStart < 3 && w.allows(forward: true)) {
        candidates.add((way: w, forward: true));
      } else if (dEnd < 3 && w.allows(forward: false)) {
        candidates.add((way: w, forward: false));
      }
    }
    if (candidates.isEmpty) return null;
    // Prefer staying on the same road name, then the same class, then random.
    candidates.sort((a, b) {
      int rank(({PackWay way, bool forward}) c) {
        var r = 0;
        if (current.name != null && c.way.name == current.name) r -= 2;
        if (c.way.roadClass == current.roadClass) r -= 1;
        return r;
      }

      return rank(a).compareTo(rank(b));
    });
    final top = candidates.first;
    final ties = candidates.where((c) => c.way.name == top.way.name).toList();
    return ties[_rng.nextInt(ties.length)];
  }
}
