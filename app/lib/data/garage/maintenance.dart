import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../push/local_notifications.dart';
import 'fuel_math.dart';

/// How far a maintenance item is from being due, in whichever dimensions the
/// item tracks. `null` means that dimension is not tracked or cannot be
/// computed (no odometer estimate yet).
class MaintenanceDue {
  const MaintenanceDue({this.kmRemaining, this.daysRemaining});

  final double? kmRemaining;
  final int? daysRemaining;

  static const double soonKm = 500;
  static const int soonDays = 14;

  bool get isDue =>
      (kmRemaining != null && kmRemaining! <= 0) ||
      (daysRemaining != null && daysRemaining! <= 0);

  bool get isSoon =>
      !isDue &&
      ((kmRemaining != null && kmRemaining! <= soonKm) ||
          (daysRemaining != null && daysRemaining! <= soonDays));

  bool get unknown => kmRemaining == null && daysRemaining == null;

  /// "Due now", "in 320 km", "in 12 days", "in 200 mi · 30 days".
  String describe({required bool useMiles}) {
    if (unknown) return 'No odometer yet';
    if (isDue) return 'Due now';
    final parts = <String>[];
    if (kmRemaining != null) {
      parts.add(
        useMiles
            ? '${kmToMiles(kmRemaining!).round()} mi'
            : '${kmRemaining!.round()} km',
      );
    }
    if (daysRemaining != null) parts.add('$daysRemaining days');
    return 'in ${parts.join(' · ')}';
  }
}

/// Distance and time left before [item] is due.
///
/// The distance baseline is `lastDoneKm` (or nothing: an item with a km
/// interval but no "last done" odometer cannot be placed). The time baseline is
/// `lastDoneAt`, falling back to when the item was created.
MaintenanceDue dueStatus(
  MaintenanceItem item, {
  required int nowMs,
  double? odometerKm,
}) {
  double? km;
  if (item.intervalKm != null &&
      item.lastDoneKm != null &&
      odometerKm != null) {
    km = item.lastDoneKm! + item.intervalKm! - odometerKm;
  }
  int? days;
  if (item.intervalDays != null) {
    final base = item.lastDoneAt ?? item.createdAt;
    final dueAt = base + item.intervalDays! * Duration.millisecondsPerDay;
    days = ((dueAt - nowMs) / Duration.millisecondsPerDay).ceil();
  }
  return MaintenanceDue(kmRemaining: km, daysRemaining: days);
}

/// Best guess of a vehicle's odometer: the newest fuel entry with a reading
/// plus the distance recorded in trips since then. Null without any reading.
double? estimateOdometerKm({
  required double? lastReadingKm,
  required double kmDrivenSinceReading,
}) => lastReadingKm == null ? null : lastReadingKm + kmDrivenSinceReading;

/// Once-a-day check that posts a local notification for every due item. Uses
/// the "Trip scored" channel: the notification channel list is an exhaustive
/// enum owned by the settings screen, so no garage channel was added.
class MaintenanceReminders {
  MaintenanceReminders({
    required this.db,
    required this.notifications,
    required this.odometerFor,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;
  final LocalNotifications notifications;

  /// Odometer estimate per vehicle id, or null.
  final Future<double?> Function(String vehicleId) odometerFor;
  final int Function() _now;

  static const settingKey = 'maintenance_checked_on';

  /// Runs at most once per local day. Returns how many reminders were posted.
  Future<int> checkDaily({bool force = false}) async {
    final today = _dayKey(_now());
    if (!force && await db.getSetting(settingKey) == today) return 0;
    await db.setSetting(settingKey, today);
    var posted = 0;
    try {
      final vehicles = await db.activeVehicles();
      final items = await db.allMaintenanceItems();
      for (final v in vehicles) {
        final odo = await odometerFor(v.id);
        for (final item in items.where((i) => i.vehicleId == v.id)) {
          final due = dueStatus(item, nowMs: _now(), odometerKm: odo);
          if (!due.isDue) continue;
          await notifications.show(
            category: NotificationCategory.tripScored,
            title: '${v.name}: ${item.title} is due',
            body: 'Open the Garage to log it or snooze it.',
            route: '/garage/vehicle/${v.id}',
            id: 7000 + item.id.hashCode.abs() % 1000,
          );
          posted++;
        }
      }
    } catch (e) {
      debugPrint('maintenance check failed: $e');
    }
    return posted;
  }

  static String _dayKey(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
