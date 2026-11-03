/// iOS Live Activity / Dynamic Island during a drive (docs/04 §2).
///
/// Dart owns the content: [liveActivityContentProvider] turns the shared
/// [CarSnapshot] into one [LiveActivityContent] frame; [LiveActivityDriver]
/// pushes frames over the `app.drivalry/live_activity` method channel at most
/// every five seconds and ends the activity when the drive is over. Nothing
/// here runs on Android, whose equivalent is the ongoing notification fed by
/// `car_bridge.dart`.
library;

import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart' show mpsToKmh, mpsToMph;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/units.dart' show unitLabel;
import 'car_bridge.dart' show carClockProvider, carSnapshotProvider;
import 'car_snapshot.dart';

/// Method channel shared with `ios/Runner/Tracking/LiveActivityPlugin.swift`.
const String liveActivityChannelName = 'app.drivalry/live_activity';

/// Least time between two `update` calls while driving. ActivityKit budgets
/// updates; five seconds keeps the speed readable without burning it.
const Duration liveActivityMinInterval = Duration(seconds: 5);

/// Floor for the leader's speed in the gap estimate, m/s, so a stopped leader
/// does not put everyone infinitely behind (same as `gapMinutes` in
/// `lost_sheep.dart`).
const double _gapFloorMps = 20;

/// One frame of the Live Activity. Mirrors
/// `DriveActivityAttributes.ContentState` on the Swift side field for field.
@immutable
class LiveActivityContent {
  const LiveActivityContent({
    required this.limitUnit,
    required this.cleanSoFar,
    required this.tripMinutes,
    required this.updatedAt,
    this.limitPosted,
    this.speedPosted,
    this.overBy,
    this.roadName,
    this.convoyName,
    this.gapMinutes,
    this.etaMinutes,
    this.talking,
    this.tripStartedAt,
  });

  /// Maps the car snapshot to a frame. `nowMs` is epoch milliseconds.
  ///
  /// The speed is converted into the *limit's* unit so one frame never mixes
  /// mph and km/h; without a usable limit the Settings unit applies and the
  /// road name is withheld (docs/01 §4.2 "silent where unsure").
  factory LiveActivityContent.fromSnapshot(
    CarSnapshot s, {
    required int nowMs,
  }) {
    final d = s.drive;
    final hasLimit = d.hasLimit && d.posted != null;
    final unit = hasLimit ? d.limitUnit : unitLabel(s.units);
    double toUnit(double mps) => unit == 'mph' ? mpsToMph(mps) : mpsToKmh(mps);

    final overMps = d.overMps;
    final over = hasLimit && d.overNow && overMps != null
        ? toUnit(overMps).round()
        : 0;
    final startedAt = d.startedAt;
    final elapsedS =
        d.elapsedS ?? (startedAt == null ? 0 : (nowMs - startedAt) ~/ 1000);
    final speed = d.speedMps;

    final c = s.convoy;
    final inConvoy = c != null && c.isActive;
    String? talking;
    double? gap;
    int? etaS;
    if (inConvoy) {
      if (s.talk.holding) {
        talking = 'You';
      } else if (s.talk.talking.isNotEmpty) {
        talking = s.talk.talking.first;
      }
      CarMember? me;
      CarMember? leader;
      for (final m in c.members) {
        if (m.isMe) me = m;
        if (m.isLeader) leader = m;
      }
      etaS = me?.etaS;
      final leaderDistance = leader?.distanceM;
      if (me != null && me.isLeader) {
        gap = 0;
      } else if (leader != null && leaderDistance != null) {
        final v = leader.speedMps ?? 0;
        gap = leaderDistance / (v < _gapFloorMps ? _gapFloorMps : v) / 60;
      }
    }

    return LiveActivityContent(
      limitPosted: hasLimit ? d.posted : null,
      limitUnit: unit,
      speedPosted: speed == null ? null : toUnit(speed).round(),
      cleanSoFar: d.status == 'clean' || d.status == 'noLimit',
      overBy: over > 0 ? over : null,
      roadName: hasLimit ? d.road : null,
      tripMinutes: d.recording ? (elapsedS ~/ 60).clamp(0, 1 << 20) : 0,
      convoyName: inConvoy ? c.name : null,
      gapMinutes: gap?.round(),
      etaMinutes: etaS == null ? null : (etaS / 60).ceil(),
      talking: talking,
      updatedAt: nowMs,
      tripStartedAt: d.recording
          ? (startedAt ?? nowMs - elapsedS * 1000)
          : null,
    );
  }

  /// Posted limit in [limitUnit]; null when the pack has nothing usable here.
  final int? limitPosted;

  /// `mph` or `km/h`.
  final String limitUnit;
  final int? speedPosted;

  /// No second over the limit so far this trip (and not a passenger).
  final bool cleanSoFar;

  /// Whole units over the limit right now, null when not over.
  final int? overBy;
  final String? roadName;
  final int tripMinutes;

  /// Null when not in an active convoy.
  final String? convoyName;

  /// Minutes behind the convoy leader; 0 when leading.
  final int? gapMinutes;
  final int? etaMinutes;

  /// Display name of whoever holds push-to-talk; "You" while holding.
  final String? talking;

  /// Epoch milliseconds when this frame was built.
  final int updatedAt;

  /// Epoch milliseconds the recording trip began; null when the frame is for
  /// a convoy that is not driving yet. It becomes the activity's fixed
  /// `startedAt`, so a new trip gets a new activity (see the driver).
  final int? tripStartedAt;

  Map<String, Object?> toMap() => {
    'limitPosted': limitPosted,
    'limitUnit': limitUnit,
    'speedPosted': speedPosted,
    'cleanSoFar': cleanSoFar,
    'overBy': overBy,
    'roadName': roadName,
    'tripMinutes': tripMinutes,
    'convoyName': convoyName,
    'gapMinutes': gapMinutes,
    'etaMinutes': etaMinutes,
    'talking': talking,
    'recording': tripStartedAt != null,
    'updatedAt': updatedAt,
  };

  /// True when nothing the widget shows differs; [updatedAt] is ignored so a
  /// steady drive does not produce an update every rebuild.
  bool displayEquals(LiveActivityContent? o) =>
      o != null &&
      o.limitPosted == limitPosted &&
      o.limitUnit == limitUnit &&
      o.speedPosted == speedPosted &&
      o.cleanSoFar == cleanSoFar &&
      o.overBy == overBy &&
      o.roadName == roadName &&
      o.tripMinutes == tripMinutes &&
      o.convoyName == convoyName &&
      o.gapMinutes == gapMinutes &&
      o.etaMinutes == etaMinutes &&
      o.talking == talking;

  @override
  String toString() => 'LiveActivityContent(${toMap()})';
}

/// Thin wrapper over the method channel. Every failure is logged and
/// swallowed: a missing native side (Android, a simulator without ActivityKit,
/// tests) must never break a drive.
class LiveActivityBridge {
  LiveActivityBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(liveActivityChannelName);

  final MethodChannel _channel;

  /// Id of the running activity, null when none.
  String? activityId;

  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('live activity isSupported failed: ${e.message}');
      return false;
    }
  }

  /// `startedAt` is the trip start in epoch ms, fixed for the activity's
  /// life; null when there is no trip yet (a convoy that has not started
  /// driving), in which case the widget shows the minutes the state carries.
  Future<void> start(LiveActivityContent content, {int? startedAt}) async {
    final id = await _call<String>('start', {
      'state': content.toMap(),
      'startedAt': ?startedAt,
    });
    if (id != null) activityId = id;
  }

  Future<void> update(LiveActivityContent content) =>
      _call<void>('update', {'state': content.toMap()});

  Future<void> end([LiveActivityContent? finalContent]) async {
    await _call<void>('end', {
      if (finalContent != null) 'state': finalContent.toMap(),
    });
    activityId = null;
  }

  Future<void> endAll() async {
    await _call<void>('endAll', const {});
    activityId = null;
  }

  Future<T?> _call<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('live activity $method failed: ${e.message}');
      return null;
    }
  }
}

/// Turns a stream of frames into start / throttled update / end calls.
///
/// The first non-null frame starts the activity; later frames that change
/// what the widget shows are sent at most once per [minInterval], with the
/// newest frame winning; a null frame ends it. Native calls run one at a time.
/// Two trip starts closer than this are the same trip (a start derived from
/// elapsed seconds can wander by a second or two between frames).
const int _newTripToleranceMs = 5 * 60 * 1000;

class LiveActivityDriver {
  LiveActivityDriver(
    this.bridge, {
    this.minInterval = liveActivityMinInterval,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final LiveActivityBridge bridge;
  final Duration minInterval;
  final int Function() _now;

  bool? _supported;
  bool _running = false;
  bool _disposed = false;
  int _lastSentAt = 0;
  int? _startedAtSent;
  LiveActivityContent? _lastSent;
  LiveActivityContent? _pending;
  Timer? _timer;
  Future<void> _chain = Future<void>.value();

  /// True between the first frame and the end of the drive, whether or not the
  /// device supports Live Activities.
  bool get running => _running;

  /// Completes when every queued native call has finished (tests).
  Future<void> get idle => _chain;

  /// Hands over the latest frame; null means the drive is over.
  void push(LiveActivityContent? content) {
    if (_disposed) return;
    if (content == null) {
      _end();
      return;
    }
    if (!_running) {
      _start(content);
      return;
    }
    // The trip start is an attribute, fixed for the activity's life. A trip
    // beginning under a convoy activity, or the next leg after one ended,
    // gets its own activity so the widget never counts from an older start.
    // The tolerance absorbs a start derived from elapsed seconds.
    final ts = content.tripStartedAt;
    if (ts != null &&
        (_startedAtSent == null ||
            (ts - _startedAtSent!).abs() > _newTripToleranceMs)) {
      _end();
      _start(content);
      return;
    }
    if (content.displayEquals(_pending ?? _lastSent)) return;
    final wait = minInterval.inMilliseconds - (_now() - _lastSentAt);
    if (wait <= 0) {
      _send(content);
      return;
    }
    _pending = content;
    _timer ??= Timer(Duration(milliseconds: wait), _flush);
  }

  /// Ends the activity, if any, and stops accepting frames.
  Future<void> dispose() {
    _end();
    _disposed = true;
    return _chain;
  }

  void _flush() {
    _timer = null;
    final p = _pending;
    _pending = null;
    if (p != null && _running) _send(p);
  }

  void _start(LiveActivityContent content) {
    _running = true;
    _lastSent = content;
    _lastSentAt = _now();
    final startedAt = content.tripStartedAt;
    _startedAtSent = startedAt;
    _enqueue(() async {
      _supported ??= await bridge.isSupported();
      if (_supported != true) return;
      await bridge.start(content, startedAt: startedAt);
    });
  }

  void _send(LiveActivityContent content) {
    _lastSent = content;
    _lastSentAt = _now();
    _enqueue(() async {
      if (_supported != true) return;
      await bridge.update(content);
    });
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
    if (!_running) return;
    _running = false;
    final last = _lastSent;
    _enqueue(() async {
      if (_supported != true) return;
      await bridge.end(last);
    });
  }

  void _enqueue(Future<void> Function() op) {
    _chain = _chain
        .then((_) => op())
        .catchError((Object e) => debugPrint('live activity: $e'));
  }
}

// ---------------------------------------------------------------------------
// Providers

/// The frame to show right now, or null when there is neither a recording
/// trip nor an active convoy. A tentative trip shows nothing: it may still
/// turn out to be a bus ride.
final liveActivityContentProvider = Provider<LiveActivityContent?>((ref) {
  final s = ref.watch(carSnapshotProvider);
  final convoyActive = s.convoy?.isActive ?? false;
  if (!s.drive.recording && !convoyActive) return null;
  return LiveActivityContent.fromSnapshot(
    s,
    nowMs: ref.watch(carClockProvider)(),
  );
});

/// Live Activities exist only on iOS. Overridden in tests.
final liveActivityEnabledProvider = Provider<bool>(
  (_) => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
);

final liveActivityBridgeProvider = Provider<LiveActivityBridge>(
  (_) => LiveActivityBridge(),
);

/// Owns the driver for the life of the app; `appBootstrapProvider` keeps it
/// alive with a `ref.watch`. Null on other platforms.
final liveActivityProvider = Provider<LiveActivityDriver?>((ref) {
  if (!ref.watch(liveActivityEnabledProvider)) return null;
  final driver = LiveActivityDriver(
    ref.watch(liveActivityBridgeProvider),
    now: ref.watch(carClockProvider),
  );
  ref.onDispose(() => unawaited(driver.dispose()));
  ref.listen<LiveActivityContent?>(
    liveActivityContentProvider,
    (_, next) => driver.push(next),
    fireImmediately: true,
  );
  return driver;
});
