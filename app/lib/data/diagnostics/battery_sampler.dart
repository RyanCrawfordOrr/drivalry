import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_models.dart';
import '../db/database.dart';

/// When a battery reading was taken. Wire values are stored in
/// `battery_samples.phase`.
enum BatteryPhase {
  tripStart('tripStart'),
  tripEnd('tripEnd'),
  parked('parked');

  const BatteryPhase(this.wire);
  final String wire;
}

/// Records battery levels so Diagnostics can show "% per hour driving" and
/// "% per day parked" (docs/06 M1.5): one reading at each trip start and end,
/// and one a day while parked (on a parked fix or when the app opens). The
/// level comes from the tracking plugin's diagnostics map; without a plugin
/// nothing is recorded. Pure logic with injected clock and reader.
class BatterySampler {
  BatterySampler({
    required this.db,
    required this.readLevel,
    required this.now,
    this.parkedInterval = const Duration(hours: 20),
    this.retention = const Duration(days: 30),
  });

  final AppDatabase db;

  /// 0–1, or null when the platform does not report a level.
  final Future<double?> Function() readLevel;
  final int Function() now;

  /// Minimum gap between two parked readings: "once a day" with slack for a
  /// phone opened at slightly different times.
  final Duration parkedInterval;
  final Duration retention;

  bool _driving = false;

  Future<void> onEvent(TrackingEvent e) async {
    switch (e) {
      case PhaseEvent(phase: TripPhaseSignal.active):
        _driving = true;
        await _sample(BatteryPhase.tripStart, tripId: e.tripId);
      case PhaseEvent(phase: TripPhaseSignal.ended):
        _driving = false;
        await _sample(BatteryPhase.tripEnd, tripId: e.tripId);
      case PhaseEvent(phase: TripPhaseSignal.discarded):
        _driving = false;
      case ParkedFixEvent():
        _driving = false;
        await parkedIfDue();
      default:
        break;
    }
  }

  /// App came to the foreground: one parked reading a day, never mid-trip.
  Future<void> onForeground() => parkedIfDue();

  Future<void> parkedIfDue() async {
    if (_driving) return;
    final last = await db.lastBatterySample(BatteryPhase.parked.wire);
    if (last != null && now() - last.t < parkedInterval.inMilliseconds) return;
    await _sample(BatteryPhase.parked);
  }

  Future<void> _sample(BatteryPhase phase, {String? tripId}) async {
    double? level;
    try {
      level = await readLevel();
    } catch (e) {
      debugPrint('battery read failed: $e');
    }
    if (level == null || level < 0 || level > 1) return;
    await db.insertBatterySample(
      BatterySamplesCompanion.insert(
        t: now(),
        level: level,
        phase: phase.wire,
        tripId: Value(tripId),
      ),
    );
  }

  Future<int> purge() =>
      db.purgeBatterySamplesBefore(now() - retention.inMilliseconds);
}

/// Keeps the sampler alive for the life of the app (watched from bootstrap).
final batterySamplerProvider = Provider<BatterySampler>((ref) {
  final sampler = BatterySampler(
    db: ref.watch(databaseProvider),
    readLevel: () async =>
        (await ref.read(trackingPortProvider).getDiagnostics()).batteryLevel,
    now: () => DateTime.now().millisecondsSinceEpoch,
  );
  final events = ref
      .read(trackingControllerProvider.notifier)
      .handledEvents
      .listen((e) => unawaited(sampler.onEvent(e)));
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(sampler.onForeground()),
  );
  unawaited(
    sampler.purge().then((_) => sampler.onForeground()).catchError((Object e) {
      debugPrint('battery sampler start failed: $e');
    }),
  );
  ref.onDispose(() {
    events.cancel();
    lifecycle.dispose();
  });
  return sampler;
});
