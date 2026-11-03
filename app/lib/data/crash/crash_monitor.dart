import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../features/profile/profile_repo.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_models.dart';
import '../db/database.dart';
import '../push/local_notifications.dart';
import '../push/push_service.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'crash_countdown.dart';
import 'crash_escalator.dart';
import 'crash_speaker.dart';

/// `Settings` keys the crash feature owns.
abstract final class CrashKeys {
  /// `'false'` turns detection off (default on).
  static const enabled = 'crash_detection';
  static const falsePositives = 'crash_false_positives';
  static const lastCandidateAt = 'crash_last_candidate_at';

  /// JSON [CrashAlertRecord] of an alert the driver has not resolved yet.
  static const unresolved = 'crash_unresolved';
}

/// Knobs the monitor needs from the outside world; tests substitute all of
/// them.
class CrashMonitorConfig {
  const CrashMonitorConfig({
    this.now,
    this.lifecycle,
    this.navigate,
    this.countdown = const Duration(seconds: 30),
    this.staleAfter = const Duration(minutes: 10),
    this.haptics = true,
  });

  final int Function()? now;

  /// Whether the app is on screen. Null means "unknown, assume on screen".
  final AppLifecycleState? Function()? lifecycle;

  /// Opens the countdown screen. Null uses the app router.
  final void Function(String route)? navigate;
  final Duration countdown;

  /// Candidates older than this (spool replay after the app was dead) flag
  /// the trip but start no countdown.
  final Duration staleAfter;
  final bool haptics;
}

final crashMonitorConfigProvider = Provider<CrashMonitorConfig>(
  (ref) => const CrashMonitorConfig(),
);

final crashEscalatorProvider = Provider<CrashEscalator>((ref) {
  return CrashEscalator(
    ref.watch(databaseProvider),
    clientOf: () => ref.read(supabaseProvider),
    userIdOf: () => ref.read(currentUserIdProvider),
    outboxWorker: ref.watch(outboxWorkerProvider),
    nameOf: () {
      final p = ref.read(myProfileProvider).value;
      return p == null || p.displayName.isEmpty
          ? 'A Drivalry user'
          : p.displayName;
    },
  );
});

class CrashUiState {
  const CrashUiState({
    this.candidate,
    this.secondsLeft = 0,
    this.testMode = false,
    this.unresolved,
    this.enabled = true,
    this.loaded = false,
    this.lastOutcome,
  });

  /// The candidate being counted down, or null.
  final CrashCandidateEvent? candidate;
  final int secondsLeft;
  final bool testMode;

  /// An alert that went out and has not been resolved by the driver.
  final CrashAlertRecord? unresolved;
  final bool enabled;
  final bool loaded;
  final CrashOutcome? lastOutcome;

  bool get countingDown => candidate != null;

  CrashUiState copyWith({
    CrashCandidateEvent? candidate,
    bool clearCandidate = false,
    int? secondsLeft,
    bool? testMode,
    CrashAlertRecord? unresolved,
    bool clearUnresolved = false,
    bool? enabled,
    bool? loaded,
    CrashOutcome? lastOutcome,
  }) => CrashUiState(
    candidate: clearCandidate ? null : (candidate ?? this.candidate),
    secondsLeft: secondsLeft ?? this.secondsLeft,
    testMode: testMode ?? this.testMode,
    unresolved: clearUnresolved ? null : (unresolved ?? this.unresolved),
    enabled: enabled ?? this.enabled,
    loaded: loaded ?? this.loaded,
    lastOutcome: lastOutcome ?? this.lastOutcome,
  );
}

/// Owns the crash countdown (docs/01 §4.5): starts it on a candidate, puts
/// the full-screen prompt up (or a full-screen notification when the app is
/// in the background), speaks every 10 s, and on silence hands over to the
/// [CrashEscalator]. "I'm OK" clears the trip's flag so it gets scored and
/// counts a false positive for Diagnostics.
class CrashMonitor extends Notifier<CrashUiState> {
  Timer? _timer;
  CrashCountdownController? _countdown;
  CrashCandidateEvent? _active;

  CrashMonitorConfig get _config => ref.read(crashMonitorConfigProvider);
  AppDatabase get _db => ref.read(databaseProvider);
  int _now() => _config.now?.call() ?? DateTime.now().millisecondsSinceEpoch;

  @override
  CrashUiState build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    ref.read(crashEscalatorProvider).registerHandlers();
    Future.microtask(_load);
    return const CrashUiState();
  }

  Future<void> _load() async {
    try {
      final enabled = await _db.getSetting(CrashKeys.enabled) != 'false';
      final unresolved = CrashAlertRecord.tryParse(
        await _db.getSetting(CrashKeys.unresolved),
      );
      state = state.copyWith(
        enabled: enabled,
        unresolved: unresolved,
        loaded: true,
      );
    } catch (e) {
      debugPrint('CrashMonitor load failed: $e');
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await _db.setSetting(CrashKeys.enabled, enabled ? 'true' : 'false');
    state = state.copyWith(enabled: enabled);
  }

  /// A `crashCandidate` from the recorder (the trip row is already flagged).
  Future<void> onCandidate(CrashCandidateEvent e) async {
    final now = _now();
    await _db.setSetting(CrashKeys.lastCandidateAt, '${e.t}');
    if (!state.loaded) await _load();
    if (!state.enabled) return;
    if (state.countingDown) return;
    if (now - e.t > _config.staleAfter.inMilliseconds) {
      // Replayed long after the fact: the flag keeps the trip unscored and
      // the Drive card asks about it, but a countdown now would be theatre.
      return;
    }
    _start(e, testMode: false);
  }

  /// Runs the countdown screen with a fake candidate. Nothing is ever sent.
  void startTest() {
    if (state.countingDown) return;
    _start(
      CrashCandidateEvent(
        tripId: 'test',
        t: _now(),
        peakMps2: 45,
        speedBeforeMps: 15,
        lat: 0,
        lon: 0,
        accuracy: 10,
      ),
      testMode: true,
    );
  }

  void _start(CrashCandidateEvent e, {required bool testMode}) {
    _active = e;
    final now = _now();
    final controller = CrashCountdownController(
      startedAt: now,
      duration: _config.countdown,
      testMode: testMode,
      onEscalate: () => _escalate(e),
      onFinished: (outcome) => unawaited(_finished(outcome)),
      onSpeak: (text) => unawaited(ref.read(crashSpeakerProvider).speak(text)),
    );
    _countdown = controller;
    state = state.copyWith(
      candidate: e,
      testMode: testMode,
      secondsLeft: controller.secondsLeft(now),
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _present();
    _tick();
  }

  void _tick() {
    final c = _countdown;
    if (c == null) return;
    final left = c.tick(_now());
    if (!c.finished) {
      state = state.copyWith(secondsLeft: left);
      if (_config.haptics) unawaited(_haptic());
    }
  }

  Future<void> _haptic() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Full-screen prompt when the app is on screen; otherwise a full-screen
  /// notification that opens it. The route is pushed in both cases so the
  /// prompt is already there when the user comes back.
  void _present() {
    final lifecycle = _config.lifecycle?.call() ?? _bindingLifecycle();
    final onScreen =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (!onScreen) {
      unawaited(
        ref
            .read(localNotificationsProvider)
            .show(
              category: NotificationCategory.crash,
              title: 'Possible crash detected',
              body:
                  "Tap I'm OK if you are fine. Help is requested in "
                  '${_config.countdown.inSeconds} seconds otherwise.',
              route: Routes.crash,
              fullScreen: true,
            ),
      );
    }
    try {
      final navigate = _config.navigate;
      if (navigate != null) {
        navigate(Routes.crash);
      } else {
        ref.read(routerProvider).push(Routes.crash);
      }
    } catch (e) {
      debugPrint('crash screen navigation failed: $e');
    }
  }

  static AppLifecycleState? _bindingLifecycle() {
    try {
      return WidgetsBinding.instance.lifecycleState;
    } catch (_) {
      return null;
    }
  }

  Future<void> imOk() async {
    _countdown?.imOk();
  }

  Future<void> sendHelpNow() async {
    _countdown?.sendHelpNow();
  }

  Future<void> _escalate(CrashCandidateEvent e) async {
    try {
      final record = await ref.read(crashEscalatorProvider).escalate(e);
      await _db.setSetting(CrashKeys.unresolved, jsonEncode(record.toJson()));
      state = state.copyWith(unresolved: record);
    } catch (err, s) {
      debugPrint('crash escalation failed: $err\n$s');
    }
  }

  Future<void> _finished(CrashOutcome outcome) async {
    _timer?.cancel();
    _timer = null;
    final e = _active;
    final wasTest = state.testMode;
    _active = null;
    _countdown = null;
    unawaited(ref.read(crashSpeakerProvider).stop());
    state = state.copyWith(
      clearCandidate: true,
      secondsLeft: 0,
      testMode: false,
      lastOutcome: outcome,
    );
    if (e == null || wasTest) return; // a test run is not a false positive
    switch (outcome) {
      case CrashOutcome.ok:
        await _db.incrementSetting(CrashKeys.falsePositives);
        await clearFlag(e.tripId!);
      case CrashOutcome.escalated:
        // The flag stays: the finalizer parks the trip as unscored until the
        // driver resolves the alert.
        break;
      case CrashOutcome.testEnded:
        break;
    }
  }

  /// The driver says they were fine: un-flag the trip and score it if it has
  /// already ended (otherwise the normal end-of-trip path scores it).
  Future<void> clearFlag(String tripId) async {
    if (tripId == 'test') return;
    await _db.setCrashCandidate(tripId, false);
    final trip = await _db.tripById(tripId);
    if (trip != null && trip.endedAt != null) {
      try {
        await ref.read(tripFinalizerProvider).finalize(tripId);
      } catch (e) {
        debugPrint('re-scoring after crash clear failed: $e');
      }
    }
  }

  /// "I'm OK" after an alert went out: tells the cloud, clears the flag,
  /// scores the trip.
  Future<void> resolveUnresolved() async {
    final r = state.unresolved;
    if (r == null) return;
    try {
      await ref.read(crashEscalatorProvider).resolve(r);
    } catch (e) {
      debugPrint('crash resolve failed: $e');
    }
    await _db.deleteSetting(CrashKeys.unresolved);
    state = state.copyWith(clearUnresolved: true);
    await clearFlag(r.tripId);
  }
}

final crashMonitorProvider = NotifierProvider<CrashMonitor, CrashUiState>(
  CrashMonitor.new,
);

/// Trips still flagged as a possible crash (no countdown running for them).
final crashFlaggedTripsProvider = StreamProvider<List<Trip>>(
  (ref) => ref.watch(databaseProvider).watchCrashFlaggedTrips(),
);

/// False-positive count for Diagnostics and the settings screen.
final crashFalsePositivesProvider = StreamProvider<int>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(CrashKeys.falsePositives)
      .map((v) => int.tryParse(v ?? '') ?? 0),
);
