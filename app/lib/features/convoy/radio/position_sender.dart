import '../../../tracking/tracking_models.dart';
import 'data_bus.dart';

/// Sends my own fixes to the convoy as `pos` frames (docs/10 §5): at most
/// one every 3 s while moving (speed ≥ 1 m/s), one every 10 s when stopped.
///
/// Fixes arrive from the plugin in batches (15 s on Android, 20 s on iOS),
/// so the cadence is enforced on the fixes' own timestamps and each frame
/// carries `fixT`; peers see positions that are as old as the plugin's batch
/// interval. A low-latency plugin mode would remove that lag.
class PositionSender {
  PositionSender(
    this._bus, {
    this.movingInterval = const Duration(seconds: 3),
    this.stoppedInterval = const Duration(seconds: 10),
    this.movingSpeedMps = 1.0,
    this.battery,
  });

  final ConvoyDataBus _bus;
  final Duration movingInterval;
  final Duration stoppedInterval;
  final double movingSpeedMps;
  final double? Function()? battery;
  int? _lastSentT;

  /// Frames sent so far (for tests and diagnostics).
  int sent = 0;

  void onEvent(TrackingEvent e) {
    if (e is FixesEvent) onFixes(e.fixes);
  }

  void onFixes(List<Fix> fixes) {
    for (final f in fixes) {
      final moving = (f.speed ?? 0) >= movingSpeedMps;
      final interval = moving ? movingInterval : stoppedInterval;
      final last = _lastSentT;
      if (last != null && f.t - last < interval.inMilliseconds) continue;
      _lastSentT = f.t;
      sent++;
      _bus.send('pos', {
        'fixT': f.t,
        'lat': f.lat,
        'lon': f.lon,
        'acc': f.accuracy,
        'speed': ?f.speed,
        'heading': ?f.heading,
        'battery': ?battery?.call(),
      });
    }
  }
}
