import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
import '../db/database.dart';
import '../models/trip_phase.dart';
import 'local_notifications.dart';
import 'push_service.dart';

/// "Trip scored" is a local notification: the phone did the scoring, so no
/// push is involved (docs/01 §4.10). Respects quiet hours and the
/// `trip_scored` switch.
class TripScoredNotifier {
  TripScoredNotifier(this._db, this._gate, this._notifications);

  final AppDatabase _db;
  final NotificationGate _gate;
  final LocalNotifications _notifications;
  StreamSubscription<List<TripWithScore>>? _sub;
  Set<String>? _seen;

  void start() {
    _sub ??= _db.watchRecentTrips(limit: 10).listen(_onTrips);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onTrips(List<TripWithScore> rows) async {
    final scored = {
      for (final r in rows)
        if (r.trip.phase == TripPhase.scored.wire && r.score != null) r.trip.id,
    };
    final seen = _seen;
    if (seen == null) {
      // First snapshot: everything already scored is old news.
      _seen = scored;
      return;
    }
    for (final r in rows) {
      final id = r.trip.id;
      if (!scored.contains(id) || seen.contains(id)) continue;
      seen.add(id);
      await notify(r);
    }
  }

  /// Shows the notification for one scored trip (also used by tests).
  Future<bool> notify(TripWithScore r) async {
    if (!await _gate.allows(NotificationCategory.tripScored)) return false;
    final score = r.score;
    if (score == null) return false;
    final title = score.reckless
        ? 'Trip scored ${score.score}. RECKLESS.'
        : 'Trip scored ${score.score}';
    await _notifications.show(
      category: NotificationCategory.tripScored,
      title: title,
      body: score.roastText ?? 'Open the trip for the breakdown.',
      route: Routes.tripDetail(r.trip.id),
    );
    return true;
  }
}

final tripScoredNotifierProvider = Provider<TripScoredNotifier>((ref) {
  final n = TripScoredNotifier(
    ref.watch(databaseProvider),
    ref.watch(notificationGateProvider),
    ref.watch(localNotificationsProvider),
  );
  ref.onDispose(n.stop);
  return n;
});
