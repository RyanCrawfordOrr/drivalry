import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart' show mpsToKmh, mpsToMph;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/crash/crash_monitor.dart';
import '../../tracking/tracking_models.dart';
import 'cue_settings.dart';
import 'cue_speaker.dart';
import 'live_limit.dart';

/// The cue rules (docs/01 §4.2, docs/04 "without the entitlement"). Pure and
/// clock-free: every decision uses the timestamps carried by the states and
/// events, so the same sequence always yields the same cues.
///
/// Phone handling is deliberately not a cue: roasts wait until the trip ends.
class CueRules {
  CueRules({
    this.overThresholdMps = 5 * 0.44704,
    this.overHoldMs = 8000,
    this.overRepeatMs = 60000,
    this.limitDebounceMs = 20000,
    this.quietStartMs = 10000,
    this.smoothAfterMs = 5 * 60000,
    this.smoothRepeatMs = 10 * 60000,
    this.harshPeakMps2 = 3.5,
  });

  /// Minimum over the limit, m/s (5 mph, the engine's minor threshold).
  final double overThresholdMps;

  /// Continuous seconds over before "Over by" is spoken.
  final int overHoldMs;

  /// Minimum gap between two "Over by" cues while still over.
  final int overRepeatMs;

  /// Minimum gap before the same limit value is announced again.
  final int limitDebounceMs;

  /// Nothing is spoken in the first seconds of a trip.
  final int quietStartMs;

  /// Clean time before "Smooth".
  final int smoothAfterMs;

  /// Minimum gap between two "Smooth" cues.
  final int smoothRepeatMs;

  /// A motion peak at or above this counts as harsh.
  final double harshPeakMps2;

  int? _tripStartT;
  int? _lastPosted;
  final Map<int, int> _limitSpokenAt = {};
  int? _overSinceT;
  int? _lastOverSpokenT;
  int _cleanSinceT = 0;
  int? _lastSmoothT;

  bool get inTrip => _tripStartT != null;

  void startTrip(int t) {
    _tripStartT = t;
    _lastPosted = null;
    _limitSpokenAt.clear();
    _overSinceT = null;
    _lastOverSpokenT = null;
    _cleanSinceT = t;
    _lastSmoothT = null;
  }

  void endTrip() {
    _tripStartT = null;
  }

  /// A harsh brake, acceleration or corner resets the clean window.
  void onMotionPeak(int t, double peakMps2) {
    if (!inTrip || peakMps2 < harshPeakMps2) return;
    _cleanSinceT = t;
  }

  /// Evaluates one live state and returns the cues to speak, in order.
  List<String> onState(LiveLimitState s, CueSettings cfg) {
    final start = _tripStartT;
    if (start == null) return const [];
    final t = s.updatedAt;
    final out = <String>[];
    final hasLimit = s.hasLimit;
    final afterQuiet = t - start >= quietStartMs;

    // Limit changes.
    final posted = s.posted;
    if (hasLimit && posted != null) {
      if (posted != _lastPosted) {
        _lastPosted = posted;
        final last = _limitSpokenAt[posted];
        if (cfg.limit &&
            afterQuiet &&
            (last == null || t - last >= limitDebounceMs)) {
          _limitSpokenAt[posted] = t;
          out.add("Limit's $posted");
        }
      }
    } else {
      _lastPosted = null;
    }

    // Over the limit.
    final over = s.overByMps;
    if (over != null && over >= overThresholdMps) {
      _overSinceT ??= t;
      _cleanSinceT = t;
      final since = _overSinceT!;
      final lastSpoken = _lastOverSpokenT;
      if (cfg.over &&
          afterQuiet &&
          t - since >= overHoldMs &&
          (lastSpoken == null || t - lastSpoken >= overRepeatMs)) {
        _lastOverSpokenT = t;
        out.add('Over by ${_display(over, s.unitLabel)}');
      }
    } else {
      _overSinceT = null;
    }

    // Smooth.
    final lastSmooth = _lastSmoothT;
    if (cfg.smooth &&
        t - _cleanSinceT >= smoothAfterMs &&
        (lastSmooth == null || t - lastSmooth >= smoothRepeatMs)) {
      _lastSmoothT = t;
      out.add('Smooth');
    }
    return out;
  }

  static int _display(double mps, String unitLabel) =>
      (unitLabel == 'mph' ? mpsToMph(mps) : mpsToKmh(mps)).round();
}

/// Wires the rules to the live limit stream and the tracking events, and
/// speaks the result unless disabled or a crash countdown is running.
class SpokenCuesRunner {
  SpokenCuesRunner({
    required this.speaker,
    required this.settings,
    required this.blocked,
    CueRules? rules,
  }) : rules = rules ?? CueRules();

  final CueSpeaker speaker;

  /// Current settings, read at speak time so toggles apply at once.
  final CueSettings Function() settings;

  /// True while nothing must be spoken (crash countdown).
  final bool Function() blocked;
  final CueRules rules;

  StreamSubscription<LiveLimitState>? _stateSub;
  StreamSubscription<TrackingEvent>? _eventSub;
  final List<String> spokenLog = [];

  void attach(Stream<LiveLimitState> states, Stream<TrackingEvent> events) {
    _stateSub?.cancel();
    _eventSub?.cancel();
    _stateSub = states.listen(onState);
    _eventSub = events.listen(onEvent);
  }

  void onEvent(TrackingEvent e) {
    switch (e) {
      case PhaseEvent(phase: TripPhaseSignal.active):
        rules.startTrip(e.startedAt ?? e.t);
      case PhaseEvent(phase: TripPhaseSignal.ended):
      case PhaseEvent(phase: TripPhaseSignal.discarded):
        rules.endTrip();
        speaker.stop();
      case MotionPeaksEvent():
        for (final p in e.peaks) {
          rules.onMotionPeak(p.t, p.peak);
        }
      case FixesEvent():
        // Fixes for a trip we never saw start: adopt it quietly.
        if (!rules.inTrip && e.fixes.isNotEmpty) {
          rules.startTrip(e.fixes.first.t);
        }
      default:
        break;
    }
  }

  Future<void> onState(LiveLimitState s) async {
    if (s.tripId == null) return;
    if (!rules.inTrip) rules.startTrip(s.updatedAt);
    final cfg = settings();
    final cues = rules.onState(s, cfg);
    if (cues.isEmpty || !cfg.enabled || blocked()) return;
    await speaker.setRate(cfg.rate);
    for (final c in cues) {
      spokenLog.add(c);
      await speaker.speak(c);
    }
  }

  void dispose() {
    _stateSub?.cancel();
    _eventSub?.cancel();
  }
}

/// Runs the spoken cues while the master switch is on. Cheap: when off it
/// is null and the live tracker is not even kept alive by this provider.
final spokenCuesProvider = Provider<SpokenCuesRunner?>((ref) {
  final enabled = ref.watch(
    cueSettingsProvider.select((s) => s.value?.enabled ?? false),
  );
  if (!enabled) return null;
  final tracker = ref.watch(liveLimitTrackerProvider);
  final runner = SpokenCuesRunner(
    speaker: ref.watch(cueSpeakerProvider),
    settings: () => ref.read(cueSettingsProvider).value ?? const CueSettings(),
    blocked: () {
      try {
        return ref.read(crashMonitorProvider).countingDown;
      } catch (e) {
        debugPrint('cues: crash state unavailable: $e');
        return false;
      }
    },
  );
  runner.attach(tracker.states, ref.watch(liveLimitEventsProvider));
  ref.onDispose(runner.dispose);
  return runner;
});
