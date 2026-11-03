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

  /// The OS's cached last position, refreshed when older than [maxAgeMs]
  /// (docs/08 §3). Null without location permission or without a plugin.
  Future<LastKnownLocation?> getLastKnownLocation({int maxAgeMs = 120000});

  /// Opens the OS screen where a driving mode / auto-reply lives (Android:
  /// Do Not Disturb settings). Returns false where nothing could be opened,
  /// which is always the case on iOS (no public settings URL survives
  /// review). Drivalry links to the OS feature; it never sends replies.
  Future<bool> openDrivingModeSettings() async => false;

  /// Live events. A broadcast stream; late subscribers miss nothing important
  /// because the spool keeps the history.
  Stream<TrackingEvent> get events;
}
