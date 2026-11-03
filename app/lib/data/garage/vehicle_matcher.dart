import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_models.dart';
import '../db/database.dart';
import '../push/local_notifications.dart';
import '../push/push_service.dart';

/// A car-audio name the phone connected to during a trip that no garage
/// vehicle claims. Shown once on the Drive tab as "add it to the Garage?".
class VehiclePrompt {
  const VehiclePrompt({required this.tripId, required this.name});

  factory VehiclePrompt.fromJson(Map<String, dynamic> m) =>
      VehiclePrompt(tripId: m['tripId'] as String, name: m['name'] as String);

  final String tripId;
  final String name;

  Map<String, dynamic> toJson() => {'tripId': tripId, 'name': name};

  static const settingKey = 'pending_bt_prompt';
}

/// Turns Bluetooth / CarPlay / Android Auto hints into garage facts
/// (docs/03 §3.3, docs/01 §4.1):
///
/// * a known vehicle name links the trip to that vehicle;
/// * a vehicle marked "never track" ends the trip and removes every trace;
/// * an unknown name sets the passenger hint once and queues a one-time
///   prompt to add the car to the Garage, unless the name was dismissed.
class VehicleMatcher {
  VehicleMatcher(
    this.db, {
    required this.onNeverTrack,
    this.onNotTracking,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;

  /// Ends the running trip (the controller's `endNow`).
  final Future<void> Function(String tripId) onNeverTrack;

  /// Tells the user quietly that a vehicle is not being tracked.
  final void Function(String vehicleName)? onNotTracking;
  final int Function() _now;

  /// Trips to hard-delete once the plugin reports them ended.
  final Set<String> _pendingDelete = {};

  /// Hints that arrived before the recorder created the trip row.
  final Map<String, String> _stashed = {};

  /// Trips already matched or hinted, so a repeated hint does nothing.
  final Set<String> _done = {};

  static const ignoredNamesKey = 'ignored_bt_names';

  /// Lower-cased, trimmed, inner whitespace collapsed.
  static String normalize(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<String> decodeNames(String json) {
    try {
      final v = jsonDecode(json);
      return v is List ? v.whereType<String>().toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static String encodeNames(Iterable<String> names) =>
      jsonEncode(names.toSet().toList());

  Future<void> handle(TrackingEvent e) async {
    switch (e) {
      case HintEvent(:final tripId?, :final name?) when name.trim().isNotEmpty:
        await _onHint(tripId, name);
      case PhaseEvent(:final tripId?, :final phase):
        final stashed = _stashed.remove(tripId);
        if (stashed != null &&
            (phase == TripPhaseSignal.active ||
                phase == TripPhaseSignal.ended)) {
          await _onHint(tripId, stashed);
        }
        if ((phase == TripPhaseSignal.ended ||
                phase == TripPhaseSignal.discarded) &&
            _pendingDelete.remove(tripId)) {
          await db.deleteTripHard(tripId);
        }
      default:
        break;
    }
  }

  Future<void> _onHint(String tripId, String name) async {
    if (_done.contains(tripId)) return;
    final trip = await db.tripById(tripId);
    if (trip == null) {
      _stashed[tripId] = name;
      return;
    }
    _done.add(tripId);
    final wanted = normalize(name);
    final vehicles = await db.activeVehicles();
    Vehicle? match;
    for (final v in vehicles) {
      if (decodeNames(v.bluetoothNames).map(normalize).contains(wanted)) {
        match = v;
        break;
      }
    }
    if (match != null) {
      await db.setTripVehicle(tripId, match.id, match.name);
      if (match.neverTrack) {
        // Hide it immediately; the rest is removed once the plugin stops.
        await db.softDeleteTrip(tripId, _now());
        _pendingDelete.add(tripId);
        onNotTracking?.call(match.name);
        try {
          await onNeverTrack(tripId);
        } catch (err) {
          debugPrint('never-track end failed: $err');
        }
      }
      return;
    }
    final ignored = decodeNames(await db.getSetting(ignoredNamesKey) ?? '[]');
    if (ignored.map(normalize).contains(wanted)) return;
    // Unknown car audio: probably someone else's car (docs/03 §3.3).
    await db.setPassengerHint(tripId, true);
    await db.setTripVehicle(tripId, null, name.trim());
    final existing = await db.getSetting(VehiclePrompt.settingKey);
    if (existing == null || existing.isEmpty) {
      await db.setSetting(
        VehiclePrompt.settingKey,
        jsonEncode(VehiclePrompt(tripId: tripId, name: name.trim()).toJson()),
      );
    }
  }
}

/// Keeps the matcher subscribed to tracking events for as long as a screen
/// watches it (the Drive and Garage tabs do).
final vehicleMatcherProvider = Provider<VehicleMatcher>((ref) {
  final controller = ref.watch(trackingControllerProvider.notifier);
  final matcher = VehicleMatcher(
    ref.watch(databaseProvider),
    onNeverTrack: (_) => controller.endNow(),
    onNotTracking: (name) => ref
        .read(localNotificationsProvider)
        .show(
          category: NotificationCategory.tripScored,
          title: 'Not tracking $name',
          body: 'This vehicle is marked "never track" in your Garage.',
          route: '/garage',
          id: 7999,
        ),
  );
  final sub = controller.handledEvents.listen(
    (e) => matcher
        .handle(e)
        .catchError((Object err) => debugPrint('vehicle matcher: $err')),
  );
  ref.onDispose(sub.cancel);
  return matcher;
});

/// The pending "add this car?" prompt, if any.
final vehiclePromptProvider = StreamProvider<VehiclePrompt?>((ref) {
  return ref.watch(databaseProvider).watchSetting(VehiclePrompt.settingKey).map(
    (raw) {
      if (raw == null || raw.isEmpty) return null;
      try {
        return VehiclePrompt.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    },
  );
});
