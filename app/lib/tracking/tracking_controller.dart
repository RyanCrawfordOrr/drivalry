import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart'
    show TripInput, haversine;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/database.dart';
import '../widgets/friendly_error.dart';
import 'providers.dart';
import 'simulated_tracking.dart';
import 'tracking_models.dart';
import 'tracking_port.dart';

/// What the Drive tab shows while a trip is being recorded.
class LiveTripStats {
  const LiveTripStats({
    required this.tripId,
    required this.startedAt,
    this.lastFixT,
    this.speedMps = 0,
    this.distanceM = 0,
    this.fixCount = 0,
    this.lastLat,
    this.lastLon,
  });

  final String tripId;
  final int startedAt;
  final int? lastFixT;
  final double speedMps;
  final double distanceM;
  final int fixCount;
  final double? lastLat;
  final double? lastLon;

  Duration elapsedAt(int nowMs) => Duration(
    milliseconds: ((lastFixT ?? nowMs) - startedAt).clamp(0, 1 << 40),
  );

  LiveTripStats addFixes(List<Fix> fixes) {
    var dist = distanceM;
    var la = lastLat;
    var lo = lastLon;
    var count = fixCount;
    var lastT = lastFixT;
    var speed = speedMps;
    for (final f in fixes) {
      if (la != null && lo != null) dist += haversine(la, lo, f.lat, f.lon);
      la = f.lat;
      lo = f.lon;
      count++;
      lastT = f.t;
      speed = f.speed ?? speed;
    }
    return LiveTripStats(
      tripId: tripId,
      startedAt: startedAt,
      lastFixT: lastT,
      speedMps: speed,
      distanceM: dist,
      fixCount: count,
      lastLat: la,
      lastLon: lo,
    );
  }
}

class TrackingUiState {
  const TrackingUiState({
    this.plugin = const TrackingState(),
    this.live,
    this.booted = false,
    this.simulating = false,
    this.error,
    this.recentErrors = const [],
  });

  final TrackingState plugin;
  final LiveTripStats? live;

  /// True once the spool has been drained and the event stream is attached.
  final bool booted;
  final bool simulating;
  final String? error;

  /// The last few `error` events from the plugin, newest last (docs/08 §4).
  final List<TrackingError> recentErrors;

  /// How many plugin errors are kept for Diagnostics.
  static const int maxRecentErrors = 10;

  TrackingUiState copyWith({
    TrackingState? plugin,
    LiveTripStats? live,
    bool clearLive = false,
    bool? booted,
    bool? simulating,
    String? error,
    bool clearError = false,
    List<TrackingError>? recentErrors,
  }) => TrackingUiState(
    plugin: plugin ?? this.plugin,
    live: clearLive ? null : (live ?? this.live),
    booted: booted ?? this.booted,
    simulating: simulating ?? this.simulating,
    error: clearError ? null : (error ?? this.error),
    recentErrors: recentErrors ?? this.recentErrors,
  );
}

/// Owns the connection to the tracking source: boots it, drains the spool,
/// feeds the recorder, mirrors state for the UI, and runs desk simulations
/// through the same path (docs/08 §7).
class TrackingController extends Notifier<TrackingUiState> {
  StreamSubscription<TrackingEvent>? _sub;
  Future<void>? _bootFuture;
  final StreamController<TrackingEvent> _handled =
      StreamController<TrackingEvent>.broadcast();
  TrackingPort get _port => ref.read(trackingPortProvider);
  AppDatabase get _db => ref.read(databaseProvider);

  /// Every event this controller handled as it happened: live plugin events
  /// and desk simulations, but not spool replays (those are history). The
  /// presence publisher listens here.
  Stream<TrackingEvent> get handledEvents => _handled.stream;

  @override
  TrackingUiState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _handled.close();
    });
    Future.microtask(boot);
    return const TrackingUiState();
  }

  /// Idempotent start-up: state, live stream, spool, pending trips. Calling
  /// it twice (the provider does, and so may the UI) shares one run.
  Future<void> boot() => _bootFuture ??= _boot();

  Future<void> _boot() async {
    // The provider can be disposed (sign-out, a test container) while boot
    // is still awaiting the plugin or the database; every step checks before
    // touching state so a late completion is a no-op, not an error.
    try {
      final plugin = await _port.getState();
      if (!ref.mounted) return;
      state = state.copyWith(plugin: plugin);
      // Listen first, drain second: anything the plugin emits while the spool
      // is being read arrives live, and the recorder dedupes the overlap
      // (docs/08 §5). The other way round loses events.
      _sub ??= _port.events.listen(
        _onEvent,
        onError: (Object e) {
          if (ref.mounted) {
            state = state.copyWith(
              error: friendlyError(e, doing: 'listen for drives'),
            );
          }
        },
      );
      await _drain();
      if (!ref.mounted) return;
      await ref.read(tripFinalizerProvider).resumePending();
      if (!ref.mounted) return;
      final latest = await _port.getState();
      if (!ref.mounted) return;
      state = state.copyWith(booted: true, plugin: latest);
      if (plugin.phase == TrackingPhase.active && plugin.tripId != null) {
        await _restoreLive(plugin);
      }
    } catch (e, s) {
      debugPrint('TrackingController boot failed: $e\n$s');
      if (ref.mounted) {
        state = state.copyWith(
          booted: true,
          error: friendlyError(e, doing: 'start drive detection'),
        );
      }
    }
  }

  /// Pulls everything the plugin spooled into the recorder (docs/08 §3:
  /// at start-up and after every `ended`). Replays are idempotent.
  Future<void> _drain() async {
    final spooled = await _port.drainSpool();
    if (spooled.isEmpty) return;
    await ref.read(tripRecorderProvider).handleAll(spooled);
  }

  Future<void> _restoreLive(TrackingState plugin) async {
    final tripId = plugin.tripId!;
    final rows = await _db.samplesFor(tripId);
    var live = LiveTripStats(
      tripId: tripId,
      startedAt: plugin.tripStartedAt ?? (rows.isEmpty ? _now() : rows.first.t),
    );
    live = live.addFixes([
      for (final r in rows)
        Fix(
          t: r.t,
          lat: r.lat,
          lon: r.lon,
          accuracy: r.accuracy,
          speed: r.speed,
        ),
    ]);
    state = state.copyWith(live: live);
  }

  void _onEvent(TrackingEvent e) {
    if (!_handled.isClosed) _handled.add(e);
    ref.read(tripRecorderProvider).handle(e);
    _trackLive(e);
    if (e is PhaseEvent) {
      // The plugin's own view (phase, tripId, spool count) may have changed.
      unawaited(refresh());
      if (e.phase == TripPhaseSignal.ended) {
        // The spool holds this trip's events too; drain it now so it does
        // not grow across an app session that spans several drives.
        unawaited(
          _drain().catchError((Object err) {
            debugPrint('spool drain after trip end failed: $err');
          }),
        );
      }
    }
  }

  void _trackLive(TrackingEvent e) {
    switch (e) {
      case PhaseEvent(phase: TripPhaseSignal.active):
        state = state.copyWith(
          live: LiveTripStats(tripId: e.tripId!, startedAt: e.startedAt ?? e.t),
        );
      case PhaseEvent(phase: TripPhaseSignal.ended):
      case PhaseEvent(phase: TripPhaseSignal.discarded):
        if (state.live?.tripId == e.tripId) {
          state = state.copyWith(clearLive: true);
        }
      case TrackingError():
        final errors = [...state.recentErrors, e];
        if (errors.length > TrackingUiState.maxRecentErrors) {
          errors.removeRange(
            0,
            errors.length - TrackingUiState.maxRecentErrors,
          );
        }
        state = state.copyWith(recentErrors: errors);
      case FixesEvent():
        final live = state.live;
        if (live != null && live.tripId == e.tripId) {
          state = state.copyWith(live: live.addFixes(e.fixes));
        } else if (live == null) {
          // Fixes for a trip we never saw start (spool replay). Track anyway.
          state = state.copyWith(
            live: LiveTripStats(
              tripId: e.tripId!,
              startedAt: e.fixes.first.t,
            ).addFixes(e.fixes),
          );
        }
      default:
        break;
    }
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  /// Re-reads the plugin's state.
  Future<void> refresh() async {
    try {
      state = state.copyWith(plugin: await _port.getState(), clearError: true);
    } catch (e) {
      state = state.copyWith(
        error: friendlyError(e, doing: 'check drive detection'),
      );
    }
  }

  /// Runs a plugin call for a user action. The native side answers any
  /// failure with a [PlatformException] (and a missing plugin with a
  /// [MissingPluginException]); those become [TrackingUiState.error], one
  /// short sentence the Drive tab can show, instead of an unhandled async
  /// error. The raw detail goes to the log for Diagnostics.
  Future<T?> _guard<T>(Future<T> Function() op) async {
    try {
      final result = await op();
      state = state.copyWith(clearError: true);
      return result;
    } on PlatformException catch (e) {
      state = state.copyWith(
        error: friendlyError(e, doing: 'change drive detection'),
      );
    } on MissingPluginException {
      state = state.copyWith(
        error: 'Drive detection is not available on this device.',
      );
    } catch (e) {
      state = state.copyWith(
        error: friendlyError(e, doing: 'change drive detection'),
      );
    }
    return null;
  }

  Future<void> _applyPlugin(Future<TrackingState> Function() op) async {
    final plugin = await _guard(op);
    if (plugin != null) state = state.copyWith(plugin: plugin);
  }

  Future<void> setEnabled(bool enabled) =>
      _applyPlugin(() => _port.setEnabled(enabled));

  Future<void> pauseFor(Duration d) =>
      _applyPlugin(() => _port.pauseUntil(_now() + d.inMilliseconds));

  /// Pause until 04:00 tomorrow, local time.
  Future<void> pauseUntilTomorrow() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 4);
    return _applyPlugin(
      () => _port.pauseUntil(tomorrow.millisecondsSinceEpoch),
    );
  }

  Future<void> clearPause() => _applyPlugin(() => _port.pauseUntil(0));

  /// Returns the permissions after the OS prompts, or the last known ones
  /// when the plugin call failed (the error is in [TrackingUiState.error]).
  Future<TrackingPermissions> requestPermissions() async {
    final perms = await _guard(_port.requestPermissions);
    if (perms == null) return state.plugin.permissions;
    state = state.copyWith(plugin: state.plugin.copyWith(permissions: perms));
    await refresh();
    return perms;
  }

  Future<void> openSettings() => _guard(_port.openSettings);

  Future<void> startNow() => _applyPlugin(_port.forceStartTrip);

  Future<void> endNow() => _applyPlugin(_port.forceEndTrip);

  /// Replays [input] through the recorder and finalizer exactly as a real
  /// drive would arrive. Returns the new trip id once it has been scored.
  Future<String> simulate(TripInput input, {double speedUp = 60}) async {
    final sim = SimulatedTracking(speedUp: speedUp);
    final sub = sim.events.listen(_onEvent);
    state = state.copyWith(simulating: true, clearError: true);
    try {
      final id = await sim.play(input, rebaseToNow: true);
      // Let the recorder finish the ended event (it finalises the trip).
      await ref.read(tripRecorderProvider).flush();
      return id;
    } finally {
      await sub.cancel();
      sim.dispose();
      state = state.copyWith(simulating: false);
    }
  }

  /// Records the answer to "Were you the passenger?" and re-scores.
  Future<void> answerPassenger(String tripId, bool isPassenger) => ref
      .read(tripFinalizerProvider)
      .finalize(tripId, isPassenger: isPassenger, markAnswered: true);

  /// Matches and scores the trip again (new pack, new flags). Keeps the
  /// stored passenger answer and does not count as answering the question.
  Future<void> rescore(String tripId) =>
      ref.read(tripFinalizerProvider).finalize(tripId);

  Future<void> deleteTrip(String tripId) => _db.softDeleteTrip(tripId, _now());
}

final trackingControllerProvider =
    NotifierProvider<TrackingController, TrackingUiState>(
      TrackingController.new,
    );

/// Live and simulated tracking events as the controller handles them.
final trackingEventsProvider = StreamProvider<TrackingEvent>(
  (ref) => ref.watch(trackingControllerProvider.notifier).handledEvents,
);
