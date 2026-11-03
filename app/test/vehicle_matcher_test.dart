import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/garage/vehicle_matcher.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

Future<void> addTrip(AppDatabase db, String id) => db.ensureTrip(
  TripsCompanion.insert(
    id: id,
    startedAt: 1000,
    phase: TripPhase.recording.wire,
    createdAt: 1000,
  ),
);

Future<void> addVehicle(
  AppDatabase db,
  String id,
  String name,
  List<String> bt, {
  bool neverTrack = false,
}) => db.upsertVehicle(
  VehiclesCompanion.insert(
    id: id,
    name: name,
    bluetoothNames: Value(VehicleMatcher.encodeNames(bt)),
    neverTrack: Value(neverTrack),
    createdAt: 1,
  ),
);

HintEvent hint(String tripId, String name) =>
    HintEvent(tripId: tripId, t: 2000, kind: 'bluetooth', name: name);

void main() {
  final skip = skipWithoutSqlite();

  group('VehicleMatcher', () {
    late AppDatabase db;
    late List<String> ended;
    late List<String> notTracking;
    late VehicleMatcher matcher;

    setUp(() async {
      db = memoryDatabase();
      ended = [];
      notTracking = [];
      matcher = VehicleMatcher(
        db,
        onNeverTrack: (id) async => ended.add(id),
        onNotTracking: notTracking.add,
        now: () => 5000,
      );
    });
    tearDown(() => db.close());

    test('a known name links the trip to the vehicle', () async {
      await addVehicle(db, 'v1', 'Mazda', ['Mazda CX-5']);
      await addTrip(db, 't1');
      await matcher.handle(hint('t1', '  mazda   cx-5 '));
      final trip = (await db.tripById('t1'))!;
      expect(trip.vehicleId, 'v1');
      expect(trip.vehicleLabel, 'Mazda');
      expect(trip.passengerHint, isFalse);
      expect(ended, isEmpty);
    });

    test(
      'never-track ends the trip, hides it, and deletes it on ended',
      () async {
        await addVehicle(db, 'v2', 'Rental', [
          'Hertz Corolla',
        ], neverTrack: true);
        await addTrip(db, 't2');
        await matcher.handle(hint('t2', 'Hertz Corolla'));
        expect(ended, ['t2']);
        expect(notTracking, ['Rental']);
        expect((await db.tripById('t2'))!.deletedAt, 5000);
        await matcher.handle(
          const PhaseEvent(tripId: 't2', t: 9000, phase: TripPhaseSignal.ended),
        );
        expect(await db.tripById('t2'), isNull);
      },
    );

    test(
      'an unknown name sets the passenger hint once and queues a prompt',
      () async {
        await addTrip(db, 't3');
        await matcher.handle(hint('t3', 'Dad Camry'));
        await matcher.handle(hint('t3', 'Dad Camry'));
        final trip = (await db.tripById('t3'))!;
        expect(trip.passengerHint, isTrue);
        expect(trip.vehicleLabel, 'Dad Camry');
        final raw = await db.getSetting(VehiclePrompt.settingKey);
        expect(raw, contains('Dad Camry'));
        expect(raw, contains('t3'));
      },
    );

    test('an ignored name is silent', () async {
      await db.setSetting(
        VehicleMatcher.ignoredNamesKey,
        VehicleMatcher.encodeNames(['Dad Camry']),
      );
      await addTrip(db, 't4');
      await matcher.handle(hint('t4', 'dad camry'));
      expect((await db.tripById('t4'))!.passengerHint, isFalse);
      expect(await db.getSetting(VehiclePrompt.settingKey), isNull);
    });

    test('a hint before the trip row exists is applied on active', () async {
      await addVehicle(db, 'v1', 'Mazda', ['Mazda CX-5']);
      await matcher.handle(hint('t5', 'Mazda CX-5'));
      await addTrip(db, 't5');
      await matcher.handle(
        const PhaseEvent(tripId: 't5', t: 3000, phase: TripPhaseSignal.active),
      );
      expect((await db.tripById('t5'))!.vehicleId, 'v1');
    });

    test('hints without a name or trip are ignored', () async {
      await matcher.handle(
        const HintEvent(tripId: 't6', t: 1, kind: 'carplay'),
      );
      await matcher.handle(
        const HintEvent(tripId: 't6', t: 1, kind: 'bluetooth', name: '  '),
      );
      expect(await db.getSetting(VehiclePrompt.settingKey), isNull);
    });
  }, skip: skip);

  test('name helpers', () {
    expect(VehicleMatcher.normalize('  My   CAR '), 'my car');
    expect(VehicleMatcher.decodeNames('["a","b",1]'), ['a', 'b']);
    expect(VehicleMatcher.decodeNames('not json'), isEmpty);
    expect(VehicleMatcher.encodeNames(['a', 'a', 'b']), '["a","b"]');
    final p = VehiclePrompt.fromJson(
      VehiclePrompt(tripId: 't', name: 'n').toJson(),
    );
    expect(p.tripId, 't');
    expect(p.name, 'n');
  });
}
