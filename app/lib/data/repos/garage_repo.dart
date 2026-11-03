import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/trip_phase.dart';
import '../db/database.dart';
import '../garage/documents.dart';
import '../garage/fuel_math.dart';
import '../garage/maintenance.dart';
import '../garage/vehicle_matcher.dart';
import '../../tracking/providers.dart';
import '../push/push_service.dart';

/// Per-vehicle numbers for the Garage list and the Stats tab. Score averages
/// use scored driver trips only; nothing here rewards distance.
class VehicleStats {
  const VehicleStats({
    this.trips = 0,
    this.scoredTrips = 0,
    this.distanceM = 0,
    this.averageScore,
    this.averageScore30d,
    this.lastTripAt,
  });

  final int trips;
  final int scoredTrips;
  final double distanceM;
  final double? averageScore;
  final double? averageScore30d;
  final int? lastTripAt;
}

/// Everything the Garage tab does to the local database. Nothing in here
/// touches the network: vehicles, fuel, maintenance and documents stay on the
/// phone (docs/01 §4.7).
class GarageRepo {
  GarageRepo(
    this.db,
    this.vault,
    this.documentsDir, {
    int Function()? now,
    this.refinalize,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;
  final DocumentVault vault;
  final Future<Directory> Function() documentsDir;
  final int Function() _now;

  /// Re-scores a trip as a driver trip after the user claims the car
  /// (`TripFinalizer.finalize(id, isPassenger: false)` in the app).
  final Future<void> Function(String tripId)? refinalize;
  static const _uuid = Uuid();

  // ------------------------------------------------------------- vehicles --

  Future<Vehicle> createVehicle({
    required String name,
    String? make,
    String? model,
    int? year,
    double? tankLitres,
    List<String> bluetoothNames = const [],
    bool neverTrack = false,
  }) async {
    final id = _uuid.v4();
    await db.upsertVehicle(
      VehiclesCompanion.insert(
        id: id,
        name: name.trim(),
        make: Value(_blankToNull(make)),
        model: Value(_blankToNull(model)),
        year: Value(year),
        bluetoothNames: Value(VehicleMatcher.encodeNames(bluetoothNames)),
        neverTrack: Value(neverTrack),
        tankLitres: Value(tankLitres),
        createdAt: _now(),
      ),
    );
    return (await db.vehicleById(id))!;
  }

  Future<void> updateVehicle(Vehicle v) =>
      db.upsertVehicle(v.toCompanion(true));

  Future<void> archiveVehicle(String id) async {
    final v = await db.vehicleById(id);
    if (v == null) return;
    await db.upsertVehicle(
      v.copyWith(archivedAt: Value(_now())).toCompanion(true),
    );
  }

  Future<void> addBluetoothName(String vehicleId, String name) async {
    final v = await db.vehicleById(vehicleId);
    if (v == null) return;
    final names = VehicleMatcher.decodeNames(v.bluetoothNames);
    if (names
        .map(VehicleMatcher.normalize)
        .contains(VehicleMatcher.normalize(name))) {
      return;
    }
    await db.upsertVehicle(
      v
          .copyWith(
            bluetoothNames: VehicleMatcher.encodeNames([...names, name.trim()]),
          )
          .toCompanion(true),
    );
  }

  Future<VehicleStats> vehicleStats(String vehicleId) async {
    final rows = await db.tripsForVehicle(vehicleId);
    if (rows.isEmpty) return const VehicleStats();
    final cutoff = _now() - const Duration(days: 30).inMilliseconds;
    var distance = 0.0;
    var scored = 0;
    var scoreSum = 0.0;
    var recent = 0;
    var recentSum = 0.0;
    for (final r in rows) {
      final t = r.trip;
      distance += t.distanceM;
      final s = r.score;
      if (t.phase == TripPhase.scored.wire &&
          t.isPassenger != true &&
          s != null &&
          s.score != null) {
        scored++;
        scoreSum += s.score!;
        if (t.startedAt >= cutoff) {
          recent++;
          recentSum += s.score!;
        }
      }
    }
    return VehicleStats(
      trips: rows.length,
      scoredTrips: scored,
      distanceM: distance,
      averageScore: scored == 0 ? null : scoreSum / scored,
      averageScore30d: recent == 0 ? null : recentSum / recent,
      lastTripAt: rows.first.trip.startedAt,
    );
  }

  /// Odometer estimate: the newest fuel entry with a reading plus the trip
  /// distance recorded since then. Null until a reading exists.
  Future<double?> estimatedOdometerKm(String vehicleId) async {
    final entries = await db.fuelEntriesFor(vehicleId);
    FuelEntry? reading;
    for (final e in entries.reversed) {
      if (e.odometerKm != null) {
        reading = e;
        break;
      }
    }
    if (reading == null) return null;
    final trips = await db.tripsForVehicle(vehicleId);
    var since = 0.0;
    for (final t in trips) {
      if (t.trip.startedAt > reading.at) since += t.trip.distanceM / 1000;
    }
    return estimateOdometerKm(
      lastReadingKm: reading.odometerKm,
      kmDrivenSinceReading: since,
    );
  }

  // ----------------------------------------------------------------- fuel --

  Future<void> addFuelEntry({
    required String vehicleId,
    required double litres,
    double? odometerKm,
    int? costCents,
    String currency = 'USD',
    bool fullTank = true,
    int? at,
  }) => db.upsertFuelEntry(
    FuelEntriesCompanion.insert(
      id: _uuid.v4(),
      vehicleId: vehicleId,
      at: at ?? _now(),
      odometerKm: Value(odometerKm),
      litres: litres,
      costCents: Value(costCents),
      currency: Value(currency),
      fullTank: Value(fullTank),
    ),
  );

  Future<void> deleteFuelEntry(String id) => db.deleteFuelEntry(id);

  // ---------------------------------------------------------- maintenance --

  Future<void> addMaintenance({
    required String vehicleId,
    required String title,
    double? intervalKm,
    int? intervalDays,
    double? lastDoneKm,
    int? lastDoneAt,
  }) => db.upsertMaintenance(
    MaintenanceItemsCompanion.insert(
      id: _uuid.v4(),
      vehicleId: vehicleId,
      title: title.trim(),
      intervalKm: Value(intervalKm),
      intervalDays: Value(intervalDays),
      lastDoneKm: Value(lastDoneKm),
      lastDoneAt: Value(lastDoneAt),
      createdAt: _now(),
    ),
  );

  Future<void> markMaintenanceDone(String id, {double? odometerKm}) async {
    final items = await db.allMaintenanceItems();
    final item = items.where((i) => i.id == id).firstOrNull;
    if (item == null) return;
    await db.upsertMaintenance(
      item
          .copyWith(
            lastDoneAt: Value(_now()),
            lastDoneKm: Value(odometerKm ?? item.lastDoneKm),
          )
          .toCompanion(true),
    );
  }

  Future<void> deleteMaintenance(String id) => db.deleteMaintenance(id);

  // ------------------------------------------------------------ documents --

  Future<void> addDocument({
    required String vehicleId,
    required String title,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final id = _uuid.v4();
    final dir = await documentsDir();
    final path = await vault.store(bytes, dir, id);
    await db.insertDocument(
      VehicleDocumentsCompanion.insert(
        id: id,
        vehicleId: vehicleId,
        title: title.trim(),
        path: path,
        mimeType: mimeType,
        createdAt: _now(),
      ),
    );
  }

  Future<Uint8List?> readDocument(String id) async {
    final doc = await db.documentById(id);
    if (doc == null) return null;
    return vault.read(doc.path);
  }

  Future<void> deleteDocument(String id) async {
    final doc = await db.documentById(id);
    if (doc == null) return;
    await vault.delete(doc.path);
    await db.deleteDocument(id);
  }

  // ------------------------------------------------- "add this car?" prompt --

  /// Creates (or links) a vehicle for the prompted name and clears the prompt.
  Future<Vehicle> acceptPrompt(
    VehiclePrompt prompt, {
    String? vehicleId,
  }) async {
    Vehicle vehicle;
    if (vehicleId != null) {
      await addBluetoothName(vehicleId, prompt.name);
      vehicle = (await db.vehicleById(vehicleId))!;
    } else {
      vehicle = await createVehicle(
        name: prompt.name,
        bluetoothNames: [prompt.name],
      );
    }
    await db.setTripVehicle(prompt.tripId, vehicle.id, vehicle.name);
    await db.setPassengerHint(prompt.tripId, false);
    await db.setSetting(VehiclePrompt.settingKey, '');
    // The trip was finalised as a passenger ride from the hint; it is the
    // user's car after all, so score it for them.
    await db.updateTrip(
      prompt.tripId,
      const TripsCompanion(isPassenger: Value(false)),
    );
    await refinalize?.call(prompt.tripId);
    return vehicle;
  }

  /// Remembers the name as not mine and clears the prompt.
  Future<void> dismissPrompt(VehiclePrompt prompt) async {
    final ignored = VehicleMatcher.decodeNames(
      await db.getSetting(VehicleMatcher.ignoredNamesKey) ?? '[]',
    );
    await db.setSetting(
      VehicleMatcher.ignoredNamesKey,
      VehicleMatcher.encodeNames([...ignored, prompt.name]),
    );
    await db.setSetting(VehiclePrompt.settingKey, '');
  }

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return t == null || t.isEmpty ? null : t;
  }
}

/// JSON-decoded Bluetooth names of a vehicle, for display.
extension VehicleNames on Vehicle {
  List<String> get bluetoothNameList =>
      VehicleMatcher.decodeNames(bluetoothNames);
}

final documentVaultProvider = Provider<DocumentVault>(
  (ref) => DocumentVault(SecureVaultKeyStore()),
);

/// `<app support>/documents`, created on first use.
final documentsDirProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'documents'));
  },
);

final garageRepoProvider = Provider<GarageRepo>(
  (ref) => GarageRepo(
    ref.watch(databaseProvider),
    ref.watch(documentVaultProvider),
    ref.watch(documentsDirProvider),
    refinalize: (tripId) async {
      await ref
          .read(tripFinalizerProvider)
          .finalize(tripId, isPassenger: false);
    },
  ),
);

final vehiclesProvider = StreamProvider<List<Vehicle>>(
  (ref) => ref.watch(databaseProvider).watchVehicles(),
);

final vehicleProvider = StreamProvider.family<Vehicle?, String>(
  (ref, id) => ref.watch(databaseProvider).watchVehicle(id),
);

/// Recomputed whenever vehicles or trips change.
final vehicleStatsProvider = FutureProvider.family<VehicleStats, String>((
  ref,
  id,
) {
  ref.watch(vehiclesProvider);
  ref.watch(recentTripsProvider);
  return ref.watch(garageRepoProvider).vehicleStats(id);
});

final fuelEntriesProvider = StreamProvider.family<List<FuelEntry>, String>(
  (ref, id) => ref.watch(databaseProvider).watchFuelEntries(id),
);

final fuelStatsProvider = Provider.family<FuelStats, String>((ref, id) {
  final entries = ref.watch(fuelEntriesProvider(id)).value ?? const [];
  return computeFuelStats(entries);
});

final maintenanceItemsProvider =
    StreamProvider.family<List<MaintenanceItem>, String>(
      (ref, id) => ref.watch(databaseProvider).watchMaintenance(id),
    );

final odometerEstimateProvider = FutureProvider.family<double?, String>((
  ref,
  id,
) {
  ref.watch(fuelEntriesProvider(id));
  ref.watch(recentTripsProvider);
  return ref.watch(garageRepoProvider).estimatedOdometerKm(id);
});

final documentsProvider = StreamProvider.family<List<VehicleDocument>, String>(
  (ref, id) => ref.watch(databaseProvider).watchDocuments(id),
);

/// Posts due-maintenance reminders once a day; kept alive by the Garage tab.
final maintenanceRemindersProvider = Provider<MaintenanceReminders>((ref) {
  final repo = ref.watch(garageRepoProvider);
  final reminders = MaintenanceReminders(
    db: ref.watch(databaseProvider),
    notifications: ref.watch(localNotificationsProvider),
    odometerFor: repo.estimatedOdometerKm,
  );
  Future<void>.microtask(reminders.checkDaily);
  return reminders;
});

/// Vehicles the user may pick for a trip or a prompt, by id.
final vehicleNamesProvider = Provider<Map<String, String>>((ref) {
  final list = ref.watch(vehiclesProvider).value ?? const [];
  return {for (final v in list) v.id: v.name};
});

/// Decodes the `ignored_bt_names` setting for the Garage's "ignored" list.
final ignoredBluetoothNamesProvider = StreamProvider<List<String>>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(VehicleMatcher.ignoredNamesKey)
      .map((raw) => VehicleMatcher.decodeNames(raw ?? '[]')),
);

/// Convenience for tests and screens that build names by hand.
String encodeBluetoothNames(List<String> names) => jsonEncode(names);
