import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// What a saved place is for. Home drives auto check-ins (docs/01 §4.5).
enum PlaceKind {
  home('home', 'Home', Icons.home_outlined),
  work('work', 'Work', Icons.work_outline),
  school('school', 'School', Icons.school_outlined),
  other('other', 'Place', Icons.place_outlined);

  const PlaceKind(this.wire, this.label, this.icon);
  final String wire;
  final String label;
  final IconData icon;

  static PlaceKind fromWire(String? wire) => switch (wire) {
    'home' => home,
    'work' => work,
    'school' => school,
    _ => other,
  };
}

/// Saved places and per-member arrive/leave alerts. Everything stays in the
/// phone's database; nothing here is ever uploaded.
class PlacesRepo {
  PlacesRepo(this.db, {int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;
  final int Function() _now;
  static const _uuid = Uuid();

  static const double minRadiusM = 50;
  static const double maxRadiusM = 500;

  // --------------------------------------------------------------- places --

  Future<List<Place>> places() => (db.select(
    db.places,
  )..orderBy([(p) => OrderingTerm.asc(p.createdAt)])).get();

  Stream<List<Place>> watchPlaces() => (db.select(
    db.places,
  )..orderBy([(p) => OrderingTerm.asc(p.createdAt)])).watch();

  Future<Place?> place(String id) =>
      (db.select(db.places)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<Place?> watchPlace(String id) =>
      (db.select(db.places)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Future<String> addPlace({
    required String label,
    required PlaceKind kind,
    required double lat,
    required double lon,
    double radiusM = 150,
  }) async {
    final id = _uuid.v4();
    await db
        .into(db.places)
        .insert(
          PlacesCompanion.insert(
            id: id,
            label: label.trim(),
            kind: Value(kind.wire),
            lat: lat,
            lon: lon,
            radiusM: Value(radiusM.clamp(minRadiusM, maxRadiusM)),
            createdAt: _now(),
          ),
        );
    return id;
  }

  Future<void> updatePlace(
    String id, {
    String? label,
    PlaceKind? kind,
    double? radiusM,
    double? lat,
    double? lon,
  }) => (db.update(db.places)..where((p) => p.id.equals(id))).write(
    PlacesCompanion(
      label: label == null ? const Value.absent() : Value(label.trim()),
      kind: kind == null ? const Value.absent() : Value(kind.wire),
      radiusM: radiusM == null
          ? const Value.absent()
          : Value(radiusM.clamp(minRadiusM, maxRadiusM)),
      lat: lat == null ? const Value.absent() : Value(lat),
      lon: lon == null ? const Value.absent() : Value(lon),
    ),
  );

  Future<void> deletePlace(String id) => db.transaction(() async {
    await (db.delete(db.placeAlerts)..where((a) => a.placeId.equals(id))).go();
    await (db.delete(db.places)..where((p) => p.id.equals(id))).go();
  });

  // --------------------------------------------------------------- alerts --

  Future<List<PlaceAlert>> allAlerts() => db.select(db.placeAlerts).get();

  Stream<List<PlaceAlert>> watchAllAlerts() =>
      db.select(db.placeAlerts).watch();

  Stream<List<PlaceAlert>> watchAlertsFor(String placeId) => (db.select(
    db.placeAlerts,
  )..where((a) => a.placeId.equals(placeId))).watch();

  /// Turns alerts on for a member at a place; both off removes the row.
  Future<void> setAlert(
    String placeId,
    String memberUserId, {
    required bool onArrive,
    required bool onLeave,
  }) async {
    if (!onArrive && !onLeave) {
      await removeAlert(placeId, memberUserId);
      return;
    }
    final existing =
        await (db.select(db.placeAlerts)..where(
              (a) =>
                  a.placeId.equals(placeId) &
                  a.memberUserId.equals(memberUserId),
            ))
            .getSingleOrNull();
    await db
        .into(db.placeAlerts)
        .insertOnConflictUpdate(
          PlaceAlertsCompanion(
            placeId: Value(placeId),
            memberUserId: Value(memberUserId),
            onArrive: Value(onArrive),
            onLeave: Value(onLeave),
            inside: Value(existing?.inside),
            lastChangedAt: Value(existing?.lastChangedAt),
          ),
        );
  }

  Future<void> removeAlert(String placeId, String memberUserId) =>
      (db.delete(db.placeAlerts)..where(
            (a) =>
                a.placeId.equals(placeId) & a.memberUserId.equals(memberUserId),
          ))
          .go();

  /// Persists the engine's inside/outside decision for one rule.
  Future<void> recordInside(
    String placeId,
    String memberUserId,
    bool inside,
    int atMs,
  ) =>
      (db.update(db.placeAlerts)..where(
            (a) =>
                a.placeId.equals(placeId) & a.memberUserId.equals(memberUserId),
          ))
          .write(
            PlaceAlertsCompanion(
              inside: Value(inside),
              lastChangedAt: Value(atMs),
            ),
          );
}

final placesRepoProvider = Provider<PlacesRepo>(
  (ref) => PlacesRepo(ref.watch(databaseProvider)),
);

final placesProvider = StreamProvider<List<Place>>(
  (ref) => ref.watch(placesRepoProvider).watchPlaces(),
);

final placeProvider = StreamProvider.family<Place?, String>(
  (ref, id) => ref.watch(placesRepoProvider).watchPlace(id),
);

final placeAlertsForProvider = StreamProvider.family<List<PlaceAlert>, String>(
  (ref, placeId) => ref.watch(placesRepoProvider).watchAlertsFor(placeId),
);

final allPlaceAlertsProvider = StreamProvider<List<PlaceAlert>>(
  (ref) => ref.watch(placesRepoProvider).watchAllAlerts(),
);
