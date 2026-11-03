import 'dart:async';

import 'package:drivalry_scoring/drivalry_scoring.dart' show haversine;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_models.dart';
import '../db/database.dart';
import '../repos/circles_repo.dart';
import '../repos/circles_sync.dart';
import '../repos/places_repo.dart';

/// Posts "I got home" on the owner's behalf when a trip has just ended and
/// the phone is inside a Home-kind place (docs/01 §4.5). Once per trip. Pure
/// state machine; the provider below wires the sources.
class AutoCheckinEngine {
  AutoCheckinEngine({this.window = const Duration(minutes: 10)});

  /// How long after a trip ends an arrival still counts.
  final Duration window;

  String? _endedTripId;
  int? _endedAtMs;
  String? _checkedInTripId;

  void onTripEnded(String tripId, int atMs) {
    _endedTripId = tripId;
    _endedAtMs = atMs;
  }

  /// The Home place to check in at for this position, or null. Marks the trip
  /// as done so the same arrival never posts twice.
  Place? onPosition({
    required double lat,
    required double lon,
    required int atMs,
    required List<Place> places,
  }) {
    final tripId = _endedTripId;
    final endedAt = _endedAtMs;
    if (tripId == null || endedAt == null) return null;
    if (_checkedInTripId == tripId) return null;
    if (atMs - endedAt > window.inMilliseconds || atMs < endedAt - 60_000) {
      return null;
    }
    for (final p in places) {
      if (PlaceKind.fromWire(p.kind) != PlaceKind.home) continue;
      if (haversine(p.lat, p.lon, lat, lon) < p.radiusM) {
        _checkedInTripId = tripId;
        return p;
      }
    }
    return null;
  }
}

/// Feeds tracking events into [AutoCheckinEngine] and posts through the
/// circles repo when the `auto_checkin_home` setting is on.
class AutoCheckinRunner {
  AutoCheckinRunner({
    required this.engine,
    required this.places,
    required this.enabled,
    required this.checkIn,
  });

  final AutoCheckinEngine engine;
  final Future<List<Place>> Function() places;
  final Future<bool> Function() enabled;
  final Future<void> Function(String label) checkIn;

  Fix? _lastFix;

  /// Labels posted so far, for tests.
  final List<String> posted = [];

  Future<void> onEvent(TrackingEvent e) async {
    switch (e) {
      case FixesEvent():
        if (e.fixes.isNotEmpty) _lastFix = e.fixes.last;
      case PhaseEvent(phase: TripPhaseSignal.ended):
        engine.onTripEnded(e.tripId ?? '', e.t);
        final f = _lastFix;
        if (f != null) await _check(f.lat, f.lon, e.t);
      case ParkedFixEvent():
        await _check(e.lat, e.lon, e.t);
      default:
        break;
    }
  }

  Future<void> _check(double lat, double lon, int atMs) async {
    if (!await enabled()) return;
    final place = engine.onPosition(
      lat: lat,
      lon: lon,
      atMs: atMs,
      places: await places(),
    );
    if (place == null) return;
    posted.add(place.label);
    try {
      await checkIn(place.label);
    } catch (err) {
      debugPrint('auto check-in failed: $err');
    }
  }
}

/// `Settings` key for the auto check-in switch (`'true'` enables).
const String autoCheckinSettingKey = 'auto_checkin_home';

final autoCheckinEnabledProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(autoCheckinSettingKey)
      .map((v) => v == 'true'),
);

/// Keeps auto check-in running while watched.
final autoCheckinProvider = Provider<AutoCheckinRunner>((ref) {
  final db = ref.watch(databaseProvider);
  final placesRepo = ref.watch(placesRepoProvider);
  final circles = ref.watch(circlesRepoProvider);
  final runner = AutoCheckinRunner(
    engine: AutoCheckinEngine(),
    places: placesRepo.places,
    enabled: () async => await db.getSetting(autoCheckinSettingKey) == 'true',
    checkIn: (label) => circles.checkIn(label),
  );
  final sub = ref
      .read(trackingControllerProvider.notifier)
      .handledEvents
      .listen((e) => unawaited(runner.onEvent(e)));
  ref.onDispose(sub.cancel);
  return runner;
});

/// Re-exported for screens that only need the label of a check-in.
typedef CheckinRepo = CirclesRepo;
