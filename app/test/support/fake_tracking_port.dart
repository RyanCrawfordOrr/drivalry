import 'dart:async';

import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/tracking_port.dart';

/// A scriptable [TrackingPort] for widget and unit tests.
class FakeTrackingPort implements TrackingPort {
  FakeTrackingPort({TrackingState? state, List<TrackingEvent>? spool})
    : state = state ?? const TrackingState(),
      spool = spool ?? [];

  TrackingState state;
  List<TrackingEvent> spool;
  TrackingPermissions permissionsOnRequest = const TrackingPermissions(
    location: LocationPermission.always,
    preciseLocation: true,
    motion: SimplePermission.granted,
    notifications: SimplePermission.granted,
    bluetooth: SimplePermission.granted,
  );
  final List<String> calls = [];
  final StreamController<TrackingEvent> controller =
      StreamController<TrackingEvent>.broadcast();

  void emit(TrackingEvent e) => controller.add(e);

  @override
  Stream<TrackingEvent> get events => controller.stream;

  @override
  Future<TrackingState> getState() async {
    calls.add('getState');
    return state;
  }

  @override
  Future<TrackingState> setEnabled(bool enabled) async {
    calls.add('setEnabled:$enabled');
    return state = state.copyWith(enabled: enabled);
  }

  @override
  Future<TrackingState> pauseUntil(int untilMs) async {
    calls.add('pauseUntil:$untilMs');
    return state = state.copyWith(pausedUntil: untilMs);
  }

  @override
  Future<TrackingPermissions> requestPermissions() async {
    calls.add('requestPermissions');
    state = state.copyWith(permissions: permissionsOnRequest);
    return permissionsOnRequest;
  }

  @override
  Future<void> openSettings() async => calls.add('openSettings');

  @override
  Future<TrackingState> forceStartTrip() async {
    calls.add('forceStartTrip');
    return state = state.copyWith(
      phase: TrackingPhase.active,
      tripId: 'forced',
    );
  }

  @override
  Future<TrackingState> forceEndTrip() async {
    calls.add('forceEndTrip');
    return state = state.copyWith(phase: TrackingPhase.idle, clearTrip: true);
  }

  @override
  Future<List<TrackingEvent>> drainSpool() async {
    calls.add('drainSpool');
    final out = List<TrackingEvent>.of(spool);
    spool.clear();
    return out;
  }

  @override
  Future<void> setMapsApiKey(String key) async => calls.add('setMapsApiKey');

  @override
  Future<TrackingDiagnostics> getDiagnostics() async =>
      const TrackingDiagnostics(confirmedTrips: 3, serviceRunning: false);

  /// What [getLastKnownLocation] answers; null by default.
  LastKnownLocation? lastKnown;

  @override
  Future<LastKnownLocation?> getLastKnownLocation({
    int maxAgeMs = 120000,
  }) async {
    calls.add('getLastKnownLocation');
    return lastKnown;
  }

  /// What [openDrivingModeSettings] answers.
  bool drivingModeSettingsOpens = true;

  @override
  Future<bool> openDrivingModeSettings() async {
    calls.add('openDrivingModeSettings');
    return drivingModeSettingsOpens;
  }

  Future<void> dispose() => controller.close();
}
