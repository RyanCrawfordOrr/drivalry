import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart' show haversine;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../db/database.dart';
import '../push/local_notifications.dart';
import '../push/push_service.dart';
import '../repos/places_repo.dart';
import '../repos/presence_repo.dart';

/// "Sam arrived at Home" / "Sam left Work".
class PlaceAlertEvent {
  const PlaceAlertEvent({
    required this.placeId,
    required this.placeLabel,
    required this.memberUserId,
    required this.memberName,
    required this.arrived,
    required this.at,
  });

  final String placeId;
  final String placeLabel;
  final String memberUserId;
  final String memberName;
  final bool arrived;
  final DateTime at;

  String get title =>
      '$memberName ${arrived ? 'arrived at' : 'left'} $placeLabel';
}

/// A rule's new inside/outside state to persist.
class PlaceAlertStateChange {
  const PlaceAlertStateChange({
    required this.placeId,
    required this.memberUserId,
    required this.inside,
  });
  final String placeId;
  final String memberUserId;
  final bool inside;
}

class PlaceAlertDecision {
  const PlaceAlertDecision({this.events = const [], this.changes = const []});
  final List<PlaceAlertEvent> events;
  final List<PlaceAlertStateChange> changes;
}

/// Decides arrive/leave transitions from presence rows (docs/01 §4.5: alerts
/// are computed on the viewer's phone from the member's position). Pure.
///
/// Rules: enter when the distance is under the place radius; leave when it is
/// over the radius plus [leaveMarginM] (hysteresis against GPS wobble at the
/// edge); presence older than [staleAfter] changes nothing; the first
/// observation of a rule only records the state and fires nothing, so
/// installing the app or adding a place never produces a burst of alerts.
class PlaceAlertEngine {
  const PlaceAlertEngine({
    this.leaveMarginM = 50,
    this.staleAfter = const Duration(minutes: 20),
  });

  final double leaveMarginM;
  final Duration staleAfter;

  PlaceAlertDecision evaluate({
    required List<Place> places,
    required List<PlaceAlert> rules,
    required List<PresenceRow> presence,
    required DateTime now,
  }) {
    final placeById = {for (final p in places) p.id: p};
    final presenceByUser = {for (final r in presence) r.userId: r};
    final events = <PlaceAlertEvent>[];
    final changes = <PlaceAlertStateChange>[];

    for (final rule in rules) {
      final place = placeById[rule.placeId];
      final row = presenceByUser[rule.memberUserId];
      if (place == null || row == null) continue;
      if (now.difference(row.updatedAt) > staleAfter) continue;

      final d = haversine(place.lat, place.lon, row.lat, row.lon);
      final wasInside = rule.inside;
      if (wasInside == null) {
        changes.add(
          PlaceAlertStateChange(
            placeId: rule.placeId,
            memberUserId: rule.memberUserId,
            inside: d < place.radiusM,
          ),
        );
        continue;
      }
      if (!wasInside && d < place.radiusM) {
        changes.add(
          PlaceAlertStateChange(
            placeId: rule.placeId,
            memberUserId: rule.memberUserId,
            inside: true,
          ),
        );
        if (rule.onArrive) {
          events.add(
            PlaceAlertEvent(
              placeId: place.id,
              placeLabel: place.label,
              memberUserId: row.userId,
              memberName: row.name,
              arrived: true,
              at: now,
            ),
          );
        }
      } else if (wasInside && d > place.radiusM + leaveMarginM) {
        changes.add(
          PlaceAlertStateChange(
            placeId: rule.placeId,
            memberUserId: rule.memberUserId,
            inside: false,
          ),
        );
        if (rule.onLeave) {
          events.add(
            PlaceAlertEvent(
              placeId: place.id,
              placeLabel: place.label,
              memberUserId: row.userId,
              memberName: row.name,
              arrived: false,
              at: now,
            ),
          );
        }
      }
    }
    return PlaceAlertDecision(events: events, changes: changes);
  }
}

/// Runs the engine on every presence update, persists the states and hands
/// events to [notify] (which applies quiet hours and the category switch).
class PlaceAlertRunner {
  PlaceAlertRunner({
    required this.repo,
    required this.notify,
    this.engine = const PlaceAlertEngine(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PlacesRepo repo;
  final PlaceAlertEngine engine;
  final Future<void> Function(PlaceAlertEvent event) notify;
  final DateTime Function() _now;

  /// Events emitted so far, for tests and diagnostics.
  final List<PlaceAlertEvent> fired = [];

  Future<int> onPresence(List<PresenceRow> rows) async {
    final rules = await repo.allAlerts();
    if (rules.isEmpty) return 0;
    final now = _now().toUtc();
    final decision = engine.evaluate(
      places: await repo.places(),
      rules: rules,
      presence: rows,
      now: now,
    );
    for (final c in decision.changes) {
      await repo.recordInside(
        c.placeId,
        c.memberUserId,
        c.inside,
        now.millisecondsSinceEpoch,
      );
    }
    for (final e in decision.events) {
      fired.add(e);
      try {
        await notify(e);
      } catch (err) {
        debugPrint('place alert notify failed: $err');
      }
    }
    return decision.events.length;
  }
}

/// Keeps place alerts running while watched (Friends and Drive screens).
final placeAlertsProvider = Provider<PlaceAlertRunner>((ref) {
  final gate = ref.watch(notificationGateProvider);
  final notifications = ref.watch(localNotificationsProvider);
  final runner = PlaceAlertRunner(
    repo: ref.watch(placesRepoProvider),
    notify: (e) async {
      if (!await gate.allows(NotificationCategory.friends)) return;
      await notifications.show(
        category: NotificationCategory.friends,
        title: e.title,
        body: e.arrived ? 'Just now, from their live location.' : 'Just now.',
        route: Routes.friendsMap,
      );
    },
  );
  ref.listen(visiblePresenceProvider, (_, next) {
    final rows = next.value;
    if (rows != null) unawaited(runner.onPresence(rows));
  });
  return runner;
});
