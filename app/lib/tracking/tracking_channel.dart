import 'dart:async';

import 'package:flutter/services.dart';

import 'tracking_models.dart';
import 'tracking_port.dart';

/// The platform-channel implementation of [TrackingPort] (docs/08 §1).
///
/// On a platform without the native plugin every method answers with
/// [TrackingState.unavailable] instead of throwing, so the rest of the app
/// (and widget tests) keep working.
class TrackingChannel implements TrackingPort {
  TrackingChannel({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel(methodChannelName),
      _events = events ?? const EventChannel(eventChannelName);

  static const methodChannelName = 'app.drivalry/tracking';
  static const eventChannelName = 'app.drivalry/tracking/events';

  final MethodChannel _methods;
  final EventChannel _events;
  Stream<TrackingEvent>? _eventStream;

  Future<Map<Object?, Object?>?> _call(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    try {
      final r = await _methods.invokeMethod<Object?>(method, args);
      return r is Map<Object?, Object?> ? r : null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<TrackingState> _state(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    final m = await _call(method, args);
    return m == null
        ? const TrackingState.unavailable()
        : TrackingState.fromMap(m);
  }

  @override
  Future<TrackingState> getState() => _state('getState');

  @override
  Future<TrackingState> setEnabled(bool enabled) =>
      _state('setEnabled', {'enabled': enabled});

  @override
  Future<TrackingState> pauseUntil(int untilMs) =>
      _state('pauseUntil', {'untilMs': untilMs});

  @override
  Future<TrackingPermissions> requestPermissions() async {
    final m = await _call('requestPermissions');
    return TrackingPermissions.fromMap(m);
  }

  @override
  Future<void> openSettings() => _call('openSettings');

  @override
  Future<TrackingState> forceStartTrip() => _state('forceStartTrip');

  @override
  Future<TrackingState> forceEndTrip() => _state('forceEndTrip');

  @override
  Future<List<TrackingEvent>> drainSpool() async {
    try {
      final r = await _methods.invokeMethod<List<Object?>>('drainSpool');
      return [
        for (final e in r ?? const <Object?>[])
          if (e is Map<Object?, Object?>) ?TrackingEvent.fromMap(e),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> setMapsApiKey(String key) async {
    if (key.isEmpty) return;
    await _call('setMapsApiKey', {'key': key});
  }

  @override
  Future<TrackingDiagnostics> getDiagnostics() async {
    final m = await _call('getDiagnostics');
    return m == null
        ? const TrackingDiagnostics()
        : TrackingDiagnostics.fromMap(m);
  }

  @override
  Future<LastKnownLocation?> getLastKnownLocation({
    int maxAgeMs = 120000,
  }) async {
    try {
      final m = await _call('getLastKnownLocation', {'maxAgeMs': maxAgeMs});
      if (m == null || m['lat'] == null || m['lon'] == null) return null;
      return LastKnownLocation.fromMap(m);
    } on PlatformException {
      // No permission, location services off, or an older plugin build.
      return null;
    }
  }

  @override
  Stream<TrackingEvent> get events => _eventStream ??= _events
      .receiveBroadcastStream()
      .map((e) => e is Map<Object?, Object?> ? TrackingEvent.fromMap(e) : null)
      .where((e) => e != null)
      .cast<TrackingEvent>()
      .handleError((Object error) {}, test: (e) => e is MissingPluginException)
      .asBroadcastStream();
}
