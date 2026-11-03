/// Pure Dart port of the native crash detectors (docs/08 §4 `crashCandidate`).
///
/// The Kotlin and Swift plugins run the same rule on the phone's sensors; this
/// copy drives the desk simulator and pins the rule in tests. Three things
/// must hold inside one window for a candidate to fire:
///
/// 1. a linear-acceleration peak of at least [peakThresholdMps2] (about 4 g),
/// 2. GPS speed of at least [speedBeforeMinMps] somewhere in the
///    [beforeWindowMs] before the peak (so a dropped phone at a standstill, or
///    a speed bump at parking speed, never counts), and
/// 3. every GPS fix in the [afterWindowMs] after the peak below
///    [speedAfterMaxMps] (a fix with no speed counts as stopped), with at least
///    two such fixes (the car is not moving and we actually saw it not moving).
///
/// It fires at most once per trip. The thresholds are first guesses to be
/// tuned against false positives on the test phones.
class CrashCandidate {
  const CrashCandidate({
    required this.t,
    required this.peakMps2,
    required this.speedBeforeMps,
  });

  /// Epoch ms of the peak.
  final int t;
  final double peakMps2;
  final double speedBeforeMps;
}

class CrashDetector {
  CrashDetector({
    this.peakThresholdMps2 = 40,
    this.speedBeforeMinMps = 8,
    this.speedAfterMaxMps = 1,
    this.beforeWindowMs = 3000,
    this.afterWindowMs = 5000,
    this.giveUpMs = 8000,
    this.historyMs = 10000,
    this.minAfterSamples = 2,
  });

  final double peakThresholdMps2;
  final double speedBeforeMinMps;
  final double speedAfterMaxMps;
  final int beforeWindowMs;
  final int afterWindowMs;
  final int giveUpMs;
  final int historyMs;
  final int minAfterSamples;

  final List<(int, double)> _speeds = [];
  _Pending? _pending;
  bool _fired = false;

  /// True once a candidate has been reported for the current trip.
  bool get fired => _fired;

  /// True while an impact is waiting for its "no movement" confirmation.
  bool get pending => _pending != null;

  /// Call at every trip start (and end).
  void reset() {
    _speeds.clear();
    _pending = null;
    _fired = false;
  }

  /// One linear-acceleration sample. Returns true when this sample opened a
  /// new candidate, which is the moment a caller may want to force the
  /// location provider to flush its batch so the confirmation arrives sooner.
  bool onAccel(int t, double magnitudeMps2) {
    if (_fired || magnitudeMps2 < peakThresholdMps2) return false;
    _trim(t);
    final before = _maxSpeedBetween(t - beforeWindowMs, t);
    if (before == null || before < speedBeforeMinMps) return false;
    final p = _pending;
    if (p != null) {
      // Still inside the open window: remember the hardest hit.
      if (magnitudeMps2 > p.peak) {
        p.peak = magnitudeMps2;
        p.t = t;
      }
      return false;
    }
    _pending = _Pending(t, magnitudeMps2, before);
    return true;
  }

  /// One GPS speed sample ([speedMps] null when the OS has no speed). Returns
  /// the confirmed candidate, or null.
  CrashCandidate? onSpeed(int t, double? speedMps) {
    if (speedMps != null) {
      _speeds.add((t, speedMps));
      _trim(t);
    }
    final p = _pending;
    if (_fired || p == null) return null;
    if (t <= p.t) return null; // a fix from before the impact, delivered late
    if (t > p.t + giveUpMs) {
      _pending = null; // never confirmed: the car kept moving, or no fixes
      return null;
    }
    // A fix with no speed at all is what the OS tends to report at a
    // standstill, so it counts as "stopped" evidence here (the before-window
    // above still only trusts fixes that carry a speed).
    final v = speedMps ?? 0.0;
    if (v >= speedAfterMaxMps) {
      _pending = null; // moving again: a pothole, not a crash
      return null;
    }
    p.afterSamples++;
    if (t >= p.t + afterWindowMs && p.afterSamples >= minAfterSamples) {
      _fired = true;
      _pending = null;
      return CrashCandidate(
        t: p.t,
        peakMps2: p.peak,
        speedBeforeMps: p.speedBefore,
      );
    }
    return null;
  }

  double? _maxSpeedBetween(int from, int to) {
    double? best;
    for (final (t, v) in _speeds) {
      if (t < from || t > to) continue;
      if (best == null || v > best) best = v;
    }
    return best;
  }

  void _trim(int now) {
    _speeds.removeWhere((s) => s.$1 < now - historyMs);
  }
}

class _Pending {
  _Pending(this.t, this.peak, this.speedBefore);
  int t;
  double peak;
  final double speedBefore;
  int afterSamples = 0;
}
