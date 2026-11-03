import 'dart:async';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show GpsSample;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/db/pack_bounds.dart';
import '../../data/sync/limit_flags_sync.dart' show cachedOverrides;
import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_models.dart';

/// Minimum confidence for a limit to be spoken or shown as known
/// (docs/01 §4.2 "silent where unsure").
const double liveLimitMinConfidence = 0.7;

/// The road under the car right now, refreshed every few seconds while a
/// trip is active (docs/03 §5, live matching).
class LiveLimitState {
  const LiveLimitState({
    this.tripId,
    this.limitMps,
    this.posted,
    this.unitLabel = 'mph',
    this.roadName,
    this.confidence = 0,
    this.speedMps,
    this.sinceMs,
    this.updatedAt = 0,
  });

  static const idle = LiveLimitState();

  final String? tripId;

  /// Limit for the direction of travel, m/s, overrides applied; null when the
  /// pack has nothing or there is no pack for this area.
  final double? limitMps;

  /// Posted integer for display, in the way's unit.
  final int? posted;

  /// `mph` or `km/h`.
  final String unitLabel;
  final String? roadName;
  final double confidence;

  /// Latest GPS speed, m/s.
  final double? speedMps;

  /// When the current posted value started (epoch ms).
  final int? sinceMs;

  /// Time of the fix this state was computed from (epoch ms).
  final int updatedAt;

  /// A limit good enough to act on.
  bool get hasLimit => limitMps != null && confidence >= liveLimitMinConfidence;

  /// How far over the limit, m/s, or null without a usable limit or speed.
  double? get overByMps {
    final l = limitMps;
    final s = speedMps;
    if (!hasLimit || l == null || s == null) return null;
    final d = s - l;
    return d > 0 ? d : 0;
  }

  LiveLimitState copyWith({
    String? tripId,
    double? limitMps,
    bool clearLimit = false,
    int? posted,
    String? unitLabel,
    String? roadName,
    bool clearRoad = false,
    double? confidence,
    double? speedMps,
    int? sinceMs,
    int? updatedAt,
  }) => LiveLimitState(
    tripId: tripId ?? this.tripId,
    limitMps: clearLimit ? null : (limitMps ?? this.limitMps),
    posted: clearLimit ? null : (posted ?? this.posted),
    unitLabel: unitLabel ?? this.unitLabel,
    roadName: clearRoad ? null : (roadName ?? this.roadName),
    confidence: clearLimit ? 0 : (confidence ?? this.confidence),
    speedMps: speedMps ?? this.speedMps,
    sinceMs: clearLimit ? null : (sinceMs ?? this.sinceMs),
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Single-fix road lookup for one pack, kept open for the trip.
abstract class LiveLocator {
  String get region;
  RoadMatch? locate(GpsSample fix, {Map<int, LimitOverride> overrides});
  void close();
}

/// [LiveMatcher] over an installed `.pack` file.
class PackLiveLocator implements LiveLocator {
  PackLiveLocator(this.region, this._source) : _matcher = LiveMatcher(_source);

  @override
  final String region;
  final PackSource _source;
  final LiveMatcher _matcher;

  @override
  RoadMatch? locate(
    GpsSample fix, {
    Map<int, LimitOverride> overrides = const {},
  }) => _matcher.locate(fix, overrides: overrides);

  @override
  void close() => _source.close();
}

/// Finds and opens the pack covering a point.
abstract class LiveLocatorFactory {
  Future<LiveLocator?> openFor(double lat, double lon);
}

/// Opens the smallest installed pack whose box contains the point, on the
/// calling isolate: a single-fix match costs milliseconds (docs/03 §5).
class InstalledPackLocatorFactory implements LiveLocatorFactory {
  InstalledPackLocatorFactory(this._db);

  final AppDatabase _db;

  @override
  Future<LiveLocator?> openFor(double lat, double lon) async {
    final pack = smallestPackContaining(await _db.installedPacks(), lat, lon);
    if (pack == null) return null;
    try {
      return PackLiveLocator(pack.region, SqlitePack.open(pack.path));
    } catch (e) {
      debugPrint('live limit: could not open ${pack.region}: $e');
      return null;
    }
  }
}

/// Loads the overrides to apply on top of a pack for [region].
typedef OverridesLoader =
    Future<Map<int, LimitOverride>> Function(String region);

/// This phone's own pending "limit is wrong here" flags, at confidence 0.5, so
/// the driver is not cued on a limit they have already disputed (docs/03
/// §4.4). Mirrors the finalizer's rule.
Future<Map<int, LimitOverride>> pendingFlagOverrides(
  AppDatabase db,
  String region,
) async {
  final flags = await (db.select(
    db.limitFlags,
  )..where((f) => f.region.equals(region) | f.region.isNull())).get();
  final out = <int, LimitOverride>{};
  for (final f in flags) {
    final id = int.tryParse(f.wayId);
    if (id == null) continue;
    out[id] = LimitOverride(
      wayId: id,
      limitMps: f.suggestedMps,
      confidence: 0.5,
    );
  }
  return out;
}

/// Cloud two-flag overrides first, then this phone's pending flags on top.
Future<Map<int, LimitOverride>> liveOverridesFor(
  AppDatabase db,
  String region,
) async => {
  ...await cachedOverrides(db, region),
  ...await pendingFlagOverrides(db, region),
};

/// Turns the tracking event stream into [LiveLimitState]s: opens the pack
/// once per trip, matches the latest fix every [intervalMs] of trip time,
/// closes the pack when the trip ends. Pure except for the injected factory
/// and overrides loader, so tests script it with fakes.
class LiveLimitTracker {
  LiveLimitTracker({
    required this.factory,
    required this.overridesFor,
    this.intervalMs = 5000,
    this.openRetryMs = 60000,
  });

  final LiveLocatorFactory factory;
  final OverridesLoader overridesFor;

  /// Trip-time spacing between matches.
  final int intervalMs;

  /// How long to wait before looking for a pack again when none covered the
  /// car (it may drive into a covered region).
  final int openRetryMs;

  final _states = StreamController<LiveLimitState>.broadcast();
  LiveLimitState _state = LiveLimitState.idle;
  LiveLocator? _locator;
  Map<int, LimitOverride> _overrides = const {};
  String? _tripId;
  int? _lastLocateT;
  int? _nextOpenAttemptT;
  Future<void> _chain = Future.value();

  Stream<LiveLimitState> get states => _states.stream;
  LiveLimitState get state => _state;

  /// True while a pack is open for the current trip.
  bool get hasPack => _locator != null;

  /// Feeds one tracking event. Events are processed in order even though
  /// opening a pack is asynchronous.
  Future<void> handle(TrackingEvent e) {
    _chain = _chain.then((_) => _handle(e)).catchError((Object err) {
      debugPrint('live limit: $err');
    });
    return _chain;
  }

  Future<void> _handle(TrackingEvent e) async {
    switch (e) {
      case PhaseEvent(phase: TripPhaseSignal.active):
        _startTrip(e.tripId!, e.startedAt ?? e.t);
      case PhaseEvent(phase: TripPhaseSignal.ended):
      case PhaseEvent(phase: TripPhaseSignal.discarded):
        if (e.tripId == _tripId) _endTrip();
      case FixesEvent():
        if (_tripId != e.tripId) {
          // Fixes for a trip we never saw start (boot mid-trip): adopt it.
          if (_tripId != null) _endTrip();
          _startTrip(e.tripId!, e.fixes.isEmpty ? e.t : e.fixes.first.t);
        }
        for (final fix in e.fixes) {
          final last = _lastLocateT;
          if (last == null || fix.t - last >= intervalMs) {
            await _locate(fix);
          }
        }
      default:
        break;
    }
  }

  void _startTrip(String tripId, int startedAt) {
    _closeLocator();
    _tripId = tripId;
    _lastLocateT = null;
    _nextOpenAttemptT = null;
    _emit(LiveLimitState(tripId: tripId, updatedAt: startedAt));
  }

  void _endTrip() {
    _closeLocator();
    _tripId = null;
    _lastLocateT = null;
    _emit(LiveLimitState.idle);
  }

  void _closeLocator() {
    try {
      _locator?.close();
    } catch (_) {}
    _locator = null;
    _overrides = const {};
  }

  Future<void> _locate(Fix fix) async {
    _lastLocateT = fix.t;
    if (_locator == null) {
      final next = _nextOpenAttemptT;
      if (next == null || fix.t >= next) {
        _nextOpenAttemptT = fix.t + openRetryMs;
        final loc = await factory.openFor(fix.lat, fix.lon);
        if (loc != null) {
          _locator = loc;
          try {
            _overrides = await overridesFor(loc.region);
          } catch (e) {
            debugPrint('live limit: overrides unavailable: $e');
            _overrides = const {};
          }
        }
      }
    }
    final loc = _locator;
    if (loc == null) {
      _emit(
        _state.copyWith(
          clearLimit: true,
          clearRoad: true,
          speedMps: fix.speed,
          updatedAt: fix.t,
        ),
      );
      return;
    }
    final m = loc.locate(
      GpsSample(
        t: fix.t,
        lat: fix.lat,
        lon: fix.lon,
        speed: fix.speed ?? 0,
        accuracy: fix.accuracy,
        heading: fix.heading,
        altitude: fix.altitude,
      ),
      overrides: _overrides,
    );
    if (m == null) {
      _emit(
        _state.copyWith(
          clearLimit: true,
          clearRoad: true,
          speedMps: fix.speed,
          updatedAt: fix.t,
        ),
      );
      return;
    }
    final changed =
        m.postedLimit != _state.posted || m.limitMps != _state.limitMps;
    _emit(
      LiveLimitState(
        tripId: _tripId,
        limitMps: m.limitMps,
        posted: m.postedLimit,
        unitLabel: m.way.unitLabel,
        roadName: m.name,
        confidence: m.confidence,
        speedMps: fix.speed,
        sinceMs: changed ? fix.t : (_state.sinceMs ?? fix.t),
        updatedAt: fix.t,
      ),
    );
  }

  void _emit(LiveLimitState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  void dispose() {
    _closeLocator();
    _states.close();
  }
}

final liveLocatorFactoryProvider = Provider<LiveLocatorFactory>(
  (ref) => InstalledPackLocatorFactory(ref.watch(databaseProvider)),
);

/// The live tracking events the tracker consumes. Tests override this with a
/// scripted stream.
final liveLimitEventsProvider = Provider<Stream<TrackingEvent>>(
  (ref) => ref.watch(trackingControllerProvider.notifier).handledEvents,
);

/// One tracker for the app, fed by the live event stream.
final liveLimitTrackerProvider = Provider<LiveLimitTracker>((ref) {
  final db = ref.watch(databaseProvider);
  final tracker = LiveLimitTracker(
    factory: ref.watch(liveLocatorFactoryProvider),
    overridesFor: (region) => liveOverridesFor(db, region),
  );
  final sub = ref.watch(liveLimitEventsProvider).listen(tracker.handle);
  ref.onDispose(() {
    sub.cancel();
    tracker.dispose();
  });
  return tracker;
});

/// The limit under the car, live. The Drive tab's recording card can show
/// "Limit 35 · 2 over" from this; the spoken cues listen to it too.
final liveLimitProvider = StreamProvider<LiveLimitState>((ref) {
  final tracker = ref.watch(liveLimitTrackerProvider);
  return Stream.multi((controller) {
    controller.add(tracker.state);
    final sub = tracker.states.listen(controller.add);
    controller.onCancel = sub.cancel;
  });
});
