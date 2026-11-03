import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/crash/crash_monitor.dart';
import '../data/db/database.dart';
import '../data/google/places_client.dart' show StopCategory;
import '../data/repos/convoy_sync.dart';
import '../features/convoy/live/convoy_live.dart';
import '../features/convoy/radio/radio_controller.dart';
import '../tracking/providers.dart';
import '../tracking/tracking_controller.dart';
import '../tracking/tracking_models.dart';

/// Names of the actions a car surface can send back over `app.drivalry/car`
/// (docs/04 §3.3). Anything else is ignored with a log line.
abstract final class CarActionNames {
  static const endTrip = 'endTrip';
  static const markPassenger = 'markPassenger';
  static const voteStop = 'voteStop';
  static const proposeStop = 'proposeStop';
  static const talkStart = 'talkStart';
  static const talkStop = 'talkStop';
  static const radioOn = 'radioOn';
  static const radioOff = 'radioOff';
  static const regroupHere = 'regroupHere';
  static const crashOk = 'crashOk';
  static const crashHelp = 'crashHelp';

  static const all = {
    endTrip,
    markPassenger,
    voteStop,
    proposeStop,
    talkStart,
    talkStop,
    radioOn,
    radioOff,
    regroupHere,
    crashOk,
    crashHelp,
  };
}

/// One action from the car: `{name, args}`.
class CarAction {
  const CarAction(this.name, [this.args = const {}]);

  final String name;
  final Map<String, Object?> args;

  /// Parses the channel payload; null when it is not an action we know.
  static CarAction? fromWire(Object? wire) {
    if (wire is! Map) return null;
    final name = wire['name'];
    if (name is! String || !CarActionNames.all.contains(name)) return null;
    final raw = wire['args'];
    final args = raw is Map
        ? raw.map((k, v) => MapEntry('$k', v))
        : const <String, Object?>{};
    return CarAction(name, args);
  }

  String? string(String key) =>
      args[key] is String ? args[key] as String : null;

  int? integer(String key) => (args[key] as num?)?.toInt();

  Map<String, Object?> toWire() => {'name': name, 'args': args};

  @override
  String toString() => 'CarAction($name, $args)';
}

/// Settings key holding the trip the driver marked as a passenger ride from
/// the car or the notification. Cleared once the answer is recorded.
const String carPassengerIntentKey = 'car.passengerIntent';

/// What the bridge needs from an action executor; the real one is
/// [CarActionHandler], tests substitute a recorder.
abstract class CarActions {
  Future<bool> handle(CarAction a);
  Future<void> confirmPassengerIfMarked(String tripId);
}

/// Executes car actions against the app. Every method is best effort and
/// never throws: the car surface has already moved on by the time the
/// result would arrive.
class CarActionHandler implements CarActions {
  CarActionHandler(this._ref);

  final Ref _ref;

  /// Handles one action. Returns false when it was not understood or could
  /// not be applied, so the native side can show "Open Drivalry on your
  /// phone" instead of silently doing nothing.
  @override
  Future<bool> handle(CarAction a) async {
    try {
      switch (a.name) {
        case CarActionNames.endTrip:
          await _ref.read(trackingControllerProvider.notifier).endNow();
          return true;
        case CarActionNames.markPassenger:
          return markPassenger(a.string('tripId'));
        case CarActionNames.voteStop:
          final convoyId = a.string('convoyId') ?? _activeConvoyId();
          final stopId = a.string('stopId');
          final vote = a.integer('vote');
          if (convoyId == null || stopId == null || vote == null) return false;
          await _ref.read(convoyRepoProvider).vote(convoyId, stopId, vote);
          return true;
        case CarActionNames.proposeStop:
          return _proposeStop(a);
        case CarActionNames.talkStart:
          final id = a.string('convoyId') ?? _activeConvoyId();
          if (id == null) return false;
          final radio = _ref.read(radioControllerProvider(id).notifier);
          if (!_ref.read(radioControllerProvider(id)).on) await radio.start();
          if (!_ref.read(radioControllerProvider(id)).on) return false;
          await radio.press();
          return true;
        case CarActionNames.talkStop:
          final id = a.string('convoyId') ?? _activeConvoyId();
          if (id == null) return false;
          await _ref.read(radioControllerProvider(id).notifier).release();
          return true;
        case CarActionNames.radioOn:
          final id = a.string('convoyId') ?? _activeConvoyId();
          if (id == null) return false;
          await _ref.read(radioControllerProvider(id).notifier).start();
          return _ref.read(radioControllerProvider(id)).on;
        case CarActionNames.radioOff:
          final id = a.string('convoyId') ?? _activeConvoyId();
          if (id == null) return false;
          await _ref.read(radioControllerProvider(id).notifier).stop();
          return true;
        case CarActionNames.regroupHere:
          return _regroupHere(a);
        case CarActionNames.crashOk:
          await _ref.read(crashMonitorProvider.notifier).imOk();
          return true;
        case CarActionNames.crashHelp:
          await _ref.read(crashMonitorProvider.notifier).sendHelpNow();
          return true;
      }
    } catch (e) {
      debugPrint('car action ${a.name} failed: $e');
    }
    return false;
  }

  /// "Passenger" during a drive: the trip keeps recording (the car is still
  /// moving) but will finalise as a passenger ride. The hint makes that
  /// happen even if the app dies before the trip ends; the intent key lets
  /// the bridge confirm the answer once the trip has ended.
  Future<bool> markPassenger(String? tripId) async {
    final id = tripId ?? _ref.read(trackingControllerProvider).plugin.tripId;
    if (id == null) return false;
    final db = _ref.read(databaseProvider);
    final trip = await db.tripById(id);
    if (trip != null && trip.endedAt != null) {
      // The trip ended while Dart was away (a tap queued on the notification
      // or the car screen, replayed after boot): no live `tripEnded` will
      // fire for it, so answer now, the way Trip Detail's "I was a
      // passenger" does.
      await _ref
          .read(trackingControllerProvider.notifier)
          .answerPassenger(id, true);
      await db.setSetting(carPassengerIntentKey, '');
      return true;
    }
    await db.setPassengerHint(id, true);
    await db.setSetting(carPassengerIntentKey, id);
    return true;
  }

  /// Called by the bridge when the recorder has finished with a trip: if the
  /// driver marked it from the car, record the answer for real.
  @override
  Future<void> confirmPassengerIfMarked(String tripId) async {
    final db = _ref.read(databaseProvider);
    if (await db.getSetting(carPassengerIntentKey) != tripId) return;
    final trip = await db.tripById(tripId);
    if (trip == null || trip.endedAt == null) return;
    await _ref
        .read(trackingControllerProvider.notifier)
        .answerPassenger(tripId, true);
    await db.setSetting(carPassengerIntentKey, '');
  }

  Future<bool> _proposeStop(CarAction a) async {
    final convoyId = a.string('convoyId') ?? _activeConvoyId();
    if (convoyId == null) return false;
    final category = StopCategory.fromWire(a.string('category') ?? 'food');
    final here = await _here();
    if (here == null) return false;
    await _ref
        .read(convoyRepoProvider)
        .proposeStop(
          convoyId,
          category: category,
          name: a.string('name') ?? '${category.label} near here',
          lat: here.$1,
          lon: here.$2,
        );
    return true;
  }

  Future<bool> _regroupHere(CarAction a) async {
    final convoyId = a.string('convoyId') ?? _activeConvoyId();
    if (convoyId == null) return false;
    if (!_ref.read(amConvoyLeaderProvider(convoyId))) return false;
    final live = _ref.read(convoyLiveProvider(convoyId));
    final here = await _here();
    if (live == null || here == null) return false;
    return live.setRegroup(here.$1, here.$2, name: a.string('name'));
  }

  String? _activeConvoyId() => _ref.read(activeConvoyProvider)?.id;

  /// Where the car is: the latest recorded fix, else the platform's last
  /// known location.
  Future<(double, double)?> _here() async {
    final live = _ref.read(trackingControllerProvider).live;
    if (live?.lastLat != null && live?.lastLon != null) {
      return (live!.lastLat!, live.lastLon!);
    }
    try {
      final loc = await _ref.read(trackingPortProvider).getLastKnownLocation();
      if (loc != null) return (loc.lat, loc.lon);
    } catch (e) {
      debugPrint('car: last known location failed: $e');
    }
    return null;
  }
}

final carActionHandlerProvider = Provider<CarActionHandler>(
  CarActionHandler.new,
);

/// True while the current trip has been marked as a passenger ride from a
/// car surface. Drives the `passenger` flag in the snapshot.
final carPassengerMarkedProvider = StreamProvider<bool>((ref) {
  final tripId = ref.watch(
    trackingControllerProvider.select((s) => s.plugin.tripId),
  );
  return ref
      .watch(databaseProvider)
      .watchSetting(carPassengerIntentKey)
      .map((v) => v != null && v.isNotEmpty && v == tripId);
});

/// Which trips are no longer recording, so passenger intents can be
/// confirmed. Exposed for the bridge; tests feed it directly.
bool tripEnded(TrackingState before, TrackingState after) =>
    before.tripId != null &&
    before.phase == TrackingPhase.active &&
    (after.tripId != before.tripId || after.phase == TrackingPhase.idle);
