import 'tracking_models.dart';

/// What the app needs from a tracking source. The native plugin implements it
/// through [TrackingChannel]; tests and the desk simulator substitute their
/// own (docs/08 §3).
abstract class TrackingPort {
  Future<TrackingState> getState();
  Future<TrackingState> setEnabled(bool enabled);

  /// Epoch ms; 0 clears the pause.
  Future<TrackingState> pauseUntil(int untilMs);
  Future<TrackingPermissions> requestPermissions();
  Future<void> openSettings();
  Future<TrackingState> forceStartTrip();
  Future<TrackingState> forceEndTrip();

  /// Events recorded while nobody was listening, oldest first. Empties the
  /// spool.
  Future<List<TrackingEvent>> drainSpool();
  Future<void> setMapsApiKey(String key);
  Future<TrackingDiagnostics> getDiagnostics();

  /// Live events. A broadcast stream; late subscribers miss nothing important
  /// because the spool keeps the history.
  Stream<TrackingEvent> get events;
}
