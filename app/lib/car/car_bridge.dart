import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/crash/crash_monitor.dart';
import '../data/repos/convoy_sync.dart';
import '../data/supabase/supabase_providers.dart';
import '../features/convoy/live/convoy_live.dart';
import '../features/convoy/positions/peer_positions.dart';
import '../features/convoy/radio/radio_controller.dart';
import '../features/cues/live_limit.dart';
import '../tracking/providers.dart';
import '../tracking/tracking_controller.dart';
import '../widgets/units.dart';
import 'car_actions.dart';
import 'car_snapshot.dart';
import 'ongoing_notification.dart';

/// `app.drivalry/car` (docs/04 §3.3).
///
/// Dart → native: `snapshot {json}`, `ongoingNotification {title, text,
/// subText, passengerAction, tripId}`, `drainActions` → `[{name, args}]`.
/// Native → Dart: `action {name, args}` → `true` when handled.
const String carChannelName = 'app.drivalry/car';

/// Splices the send time into an already-encoded snapshot, so each snapshot
/// is encoded once: the content string that decides whether a resend is due
/// is also what goes over the wire.
String snapshotWire(String contentJson, int at) {
  assert(contentJson.length > 2 && contentJson.startsWith('{'));
  return '{"at":$at,${contentJson.substring(1)}';
}

/// Thin wrapper over the method channel. Swallows a missing native side so
/// tests, the simulator and desktop runs keep working.
class CarChannel {
  CarChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(carChannelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final _actions = StreamController<CarAction>.broadcast();

  /// Handler the bridge installs; the result goes back to the native side.
  Future<bool> Function(CarAction)? onAction;

  /// Actions arriving from the car, after [onAction] has run.
  Stream<CarAction> get actions => _actions.stream;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method != 'action') return null;
    final a = CarAction.fromWire(call.arguments);
    if (a == null) {
      debugPrint('car: unknown action ${call.arguments}');
      return false;
    }
    final handled = await onAction?.call(a) ?? false;
    if (!_actions.isClosed) _actions.add(a);
    return handled;
  }

  Future<void> sendSnapshot(CarSnapshot s, {required int at}) =>
      _call('snapshot', {'json': snapshotWire(s.contentJson, at)});

  /// Null clears the live line (the service falls back to its static text).
  Future<void> sendOngoingNotification(OngoingNotificationLine? line) =>
      _call('ongoingNotification', line?.toWire());

  /// Actions the native side queued while no Dart isolate was listening
  /// (a tap on the notification or the car screen with the app dead).
  Future<List<CarAction>> drainActions() async {
    try {
      final r = await _channel.invokeMethod<List<Object?>>('drainActions');
      return [for (final w in r ?? const []) ?CarAction.fromWire(w)];
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      debugPrint('car drainActions failed: ${e.message}');
      return const [];
    }
  }

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native side: nothing to show.
    } on PlatformException catch (e) {
      debugPrint('car $method failed: ${e.message}');
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _actions.close();
  }
}

final carChannelProvider = Provider<CarChannel>((ref) {
  final c = CarChannel();
  ref.onDispose(c.dispose);
  return c;
});

/// Seconds over the limit this trip, from the live limit stream.
class SpeedingTallyNotifier extends Notifier<SpeedingTally> {
  @override
  SpeedingTally build() {
    ref.listen(liveLimitProvider, (_, next) {
      final s = next.value;
      if (s != null) state = state.update(s);
    });
    return SpeedingTally.empty;
  }
}

final speedingTallyProvider =
    NotifierProvider<SpeedingTallyNotifier, SpeedingTally>(
      SpeedingTallyNotifier.new,
    );

/// Injected clock for tests.
final carClockProvider = Provider<int Function()>(
  (ref) =>
      () => DateTime.now().millisecondsSinceEpoch,
);

/// The snapshot, rebuilt whenever anything it shows changes. Convoy inputs
/// are only watched while I am in a convoy, so an idle app pays nothing.
final carSnapshotProvider = Provider<CarSnapshot>((ref) {
  final tracking = ref.watch(trackingControllerProvider);
  final liveLimit = ref.watch(liveLimitProvider).value;
  final tally = ref.watch(speedingTallyProvider);
  final passenger = ref.watch(carPassengerMarkedProvider).value ?? false;
  final crash = ref.watch(crashMonitorProvider);
  final me = ref.watch(currentUserIdProvider);
  final unitsSetting =
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto;
  final convoy = ref.watch(activeConvoyProvider);

  final id = convoy?.id;
  final live = convoy != null && convoy.isActive;
  return buildCarSnapshot(
    CarSnapshotInputs(
      tracking: tracking,
      nowMs: ref.read(carClockProvider)(),
      liveLimit: liveLimit,
      tally: tally,
      passengerMarked: passenger,
      convoy: convoy,
      members: id == null
          ? const []
          : ref.watch(convoyMembersProvider(id)).value ?? const [],
      stops: id == null
          ? const []
          : ref.watch(convoyStopsProvider(id)).value ?? const [],
      positions: id == null || !live
          ? const {}
          : ref.watch(peerPositionsProvider(id)).value ?? const {},
      etas: id == null || !live
          ? const {}
          : ref.watch(convoyEtasProvider(id)).value ?? const {},
      lost: id == null || !live
          ? const {}
          : ref.watch(lostSheepProvider(id)).value ?? const {},
      regroup: id == null || !live
          ? null
          : ref.watch(regroupPinProvider(id)).value,
      radio: id == null || !live
          ? null
          : ref.watch(radioControllerProvider(id)),
      crash: crash,
      me: me,
      units: resolveUnits(
        unitsSetting,
        packRegion: liveLimit?.unitLabel == 'km/h' ? 'xx' : null,
      ),
    ),
  );
});

/// Pushes snapshots and the notification line to the native side, at most
/// once a second, and routes car actions to the handler. Alive for the app's
/// life (watched from the bootstrap provider).
class CarBridge {
  CarBridge({
    required this.channel,
    required this.handler,
    required this.now,
    this.minInterval = const Duration(seconds: 1),
    this.ready,
  }) {
    channel.onAction = handler.handle;
  }

  final CarChannel channel;
  final CarActions handler;
  final int Function() now;
  final Duration minInterval;

  /// Awaited before queued actions are replayed: the tracking controller's
  /// boot (spool import, pending trips finalised), so a "Passenger" tap made
  /// while Dart was dead lands on a trip row that exists and is settled.
  final Future<void> Function()? ready;

  CarSnapshot? _pending;
  String? _lastSentJson;
  OngoingNotificationLine? _lastLine;
  bool _lineSent = false;
  int _lastSentAt = 0;
  bool _everSent = false;
  Timer? _timer;
  bool _disposed = false;

  /// Queues a snapshot; identical content is not resent. The first update
  /// goes out at once, later ones at most every [minInterval].
  void update(CarSnapshot s) {
    if (_disposed) return;
    _pending = s;
    final due = now() - _lastSentAt;
    if (!_everSent || due >= minInterval.inMilliseconds) {
      _flush();
    } else {
      _timer ??= Timer(minInterval - Duration(milliseconds: due), _flush);
    }
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;
    final s = _pending;
    if (s == null || _disposed) return;
    _pending = null;
    _lastSentAt = now();
    _everSent = true;
    final json = s.contentJson;
    if (json != _lastSentJson) {
      _lastSentJson = json;
      unawaited(channel.sendSnapshot(s, at: _lastSentAt));
    }
    final line = ongoingNotificationFor(s);
    if (!_lineSent || line != _lastLine) {
      _lineSent = true;
      _lastLine = line;
      unawaited(channel.sendOngoingNotification(line));
    }
  }

  /// Runs actions the native side queued while Dart was away, once [ready]
  /// has completed.
  Future<void> drainQueued() async {
    try {
      await ready?.call();
    } catch (e) {
      debugPrint('car: ready failed, draining anyway: $e');
    }
    if (_disposed) return;
    for (final a in await channel.drainActions()) {
      await handler.handle(a);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    channel.onAction = null;
  }
}

final carBridgeProvider = Provider<CarBridge>((ref) {
  final bridge = CarBridge(
    channel: ref.watch(carChannelProvider),
    handler: ref.watch(carActionHandlerProvider),
    now: ref.watch(carClockProvider),
    ready: () => ref.read(trackingControllerProvider.notifier).boot(),
  );
  ref.listen(carSnapshotProvider, (_, next) => bridge.update(next));
  bridge.update(ref.read(carSnapshotProvider));

  // A passenger marked from the car is confirmed once the trip has ended.
  ref.listen(trackingControllerProvider, (prev, next) {
    final before = prev?.plugin;
    if (before != null && tripEnded(before, next.plugin)) {
      unawaited(
        Future<void>.delayed(
          const Duration(seconds: 2),
          () => bridge.handler.confirmPassengerIfMarked(before.tripId!),
        ),
      );
    }
  });

  unawaited(bridge.drainQueued());
  ref.onDispose(bridge.dispose);
  return bridge;
});
