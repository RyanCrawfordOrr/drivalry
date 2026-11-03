import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/places/nominatim.dart';
import '../../../tracking/providers.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../tracking/tracking_models.dart';

/// Remembers where each trip ended (docs/01 §4.7, "parking memory"). The
/// spot is the trip's last GPS fix; it never leaves the phone.
class ParkingMemory {
  ParkingMemory(this.db);

  final AppDatabase db;

  Future<void> handle(TrackingEvent e) async {
    if (e is PhaseEvent && e.phase == TripPhaseSignal.ended) {
      await recordSpot(e.tripId!);
    }
  }

  /// Stores the trip's last sample as its parking spot. Returns false when the
  /// trip has no samples or already has a spot.
  Future<bool> recordSpot(String tripId) async {
    if (await db.parkingSpotFor(tripId) != null) return false;
    final trip = await db.tripById(tripId);
    // Soft-deleted trips (never-track vehicles, user deletes) leave no spot.
    if (trip == null || trip.deletedAt != null) return false;
    if (await db.getSetting(forgottenKey) == tripId) return false;
    final samples = await db.samplesFor(tripId);
    if (samples.isEmpty) return false;
    final last = samples.last;
    await db.insertParkingSpot(
      ParkingSpotsCompanion.insert(
        tripId: tripId,
        lat: last.lat,
        lon: last.lon,
        accuracy: last.accuracy,
        parkedAt: last.t,
      ),
    );
    return true;
  }

  /// Boot-time catch-up for a trip that ended while the app was dead.
  Future<void> catchUp() async {
    try {
      final trip = await db.latestEndedTripWithoutSpot();
      if (trip != null) await recordSpot(trip.id);
    } catch (e) {
      debugPrint('parking catch-up failed: $e');
    }
  }

  Future<void> setPhoto(String tripId, String? path) => db.updateParkingSpot(
    tripId,
    ParkingSpotsCompanion(photoPath: Value(path)),
  );

  Future<void> setNote(String tripId, String? note) => db.updateParkingSpot(
    tripId,
    ParkingSpotsCompanion(
      note: Value(note == null || note.isEmpty ? null : note),
    ),
  );

  /// `Settings` key holding the trip id whose spot the user forgot, so the
  /// boot-time catch-up does not quietly bring it back.
  static const forgottenKey = 'parking_forgotten_trip';

  Future<void> forget(String tripId) async {
    await db.setSetting(forgottenKey, tripId);
    await db.deleteParkingSpot(tripId);
  }

  /// The road the trip ended on, from its own matched segments.
  Future<String?> roadFromSegments(String tripId) async {
    final segments = await db.segmentsFor(tripId);
    for (final s in segments.reversed) {
      final n = s.name;
      if (n != null && n.isNotEmpty) return n;
    }
    return null;
  }
}

/// Alive while the Drive tab is; records spots as trips end.
final parkingMemoryProvider = Provider<ParkingMemory>((ref) {
  final memory = ParkingMemory(ref.watch(databaseProvider));
  final controller = ref.watch(trackingControllerProvider.notifier);
  final sub = controller.handledEvents.listen(
    (e) => memory
        .handle(e)
        .catchError((Object err) => debugPrint('parking memory: $err')),
  );
  ref.onDispose(sub.cancel);
  unawaited(memory.catchUp());
  return memory;
});

/// The newest parking spot, or null.
final latestParkingSpotProvider = StreamProvider<ParkingSpot?>(
  (ref) => ref.watch(databaseProvider).watchLatestParkingSpot(),
);

final nominatimProvider = Provider<Nominatim>(
  (ref) =>
      Nominatim(ref.watch(httpClientProvider), ref.watch(databaseProvider)),
);

/// "Elm St" for a spot: the trip's own road name first, Nominatim second,
/// null when neither knows. Cached per trip for the life of the provider.
final parkingRoadNameProvider = FutureProvider.family<String?, String>((
  ref,
  tripId,
) async {
  final memory = ref.watch(parkingMemoryProvider);
  final own = await memory.roadFromSegments(tripId);
  if (own != null) return own;
  final spot = await ref.watch(databaseProvider).parkingSpotFor(tripId);
  if (spot == null) return null;
  return ref.read(nominatimProvider).roadNameNear(spot.lat, spot.lon);
});
