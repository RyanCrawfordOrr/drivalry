import 'dart:async';

/// How a countdown ended.
enum CrashOutcome {
  /// The driver tapped "I'm OK" in time. Counted as a false positive.
  ok,

  /// Nobody answered (or "Send help now"): the alert went out.
  escalated,

  /// A test run finished; nothing was sent.
  testEnded,
}

/// The 30 s countdown after a `crashCandidate` (docs/01 §4.5), as a pure
/// state machine driven by whoever owns the clock. No timers in here, so the
/// rule is testable to the millisecond.
class CrashCountdownController {
  CrashCountdownController({
    required this.startedAt,
    required this.onEscalate,
    required this.onFinished,
    this.onSpeak,
    this.duration = const Duration(seconds: 30),
    this.testMode = false,
    this.speakEverySeconds = 10,
  });

  /// Epoch ms when the countdown began.
  final int startedAt;
  final Duration duration;

  /// Test runs look identical on screen but never escalate.
  final bool testMode;

  /// Spoken prompt cadence, in seconds left.
  final int speakEverySeconds;

  /// Runs once, when the outcome is [CrashOutcome.escalated].
  final Future<void> Function() onEscalate;

  /// Runs exactly once, for every outcome, after [onEscalate] has been kicked
  /// off.
  final void Function(CrashOutcome outcome) onFinished;
  final void Function(String text)? onSpeak;

  static const String prompt = "Possible crash detected. Tap I'm OK.";

  CrashOutcome? _outcome;
  int _lastSpokenAt = -1;

  CrashOutcome? get outcome => _outcome;
  bool get finished => _outcome != null;
  int get deadline => startedAt + duration.inMilliseconds;

  int secondsLeft(int nowMs) {
    if (_outcome != null) return 0;
    final left = ((deadline - nowMs) / 1000).ceil();
    return left.clamp(0, duration.inSeconds);
  }

  /// Advances the clock. Speaks on every [speakEverySeconds] boundary, and
  /// finishes when the deadline has passed. Returns the seconds left.
  int tick(int nowMs) {
    if (_outcome != null) return 0;
    final left = secondsLeft(nowMs);
    if (left > 0 && left % speakEverySeconds == 0 && left != _lastSpokenAt) {
      _lastSpokenAt = left;
      onSpeak?.call(prompt);
    }
    if (nowMs >= deadline) {
      _finish(testMode ? CrashOutcome.testEnded : CrashOutcome.escalated);
      return 0;
    }
    return left;
  }

  void imOk() => _finish(CrashOutcome.ok);

  void sendHelpNow() =>
      _finish(testMode ? CrashOutcome.testEnded : CrashOutcome.escalated);

  void _finish(CrashOutcome outcome) {
    if (_outcome != null) return;
    _outcome = outcome;
    if (outcome == CrashOutcome.escalated) unawaited(onEscalate());
    onFinished(outcome);
  }
}
