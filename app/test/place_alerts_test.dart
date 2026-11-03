import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/alerts/place_alerts.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/push/local_notifications.dart';
import 'package:drivalry/data/push/push_service.dart';
import 'package:drivalry/data/push/quiet_hours.dart';
import 'package:drivalry/data/repos/places_repo.dart';
import 'package:drivalry/data/repos/presence_repo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

final _now = DateTime.utc(2026, 11, 3, 12);

Place _home({double radius = 150}) => Place(
  id: 'home',
  label: 'Home',
  kind: 'home',
  lat: 38.9000,
  lon: -77.0300,
  radiusM: radius,
  createdAt: 0,
);

PlaceAlert _rule({bool? inside, bool onArrive = true, bool onLeave = true}) =>
    PlaceAlert(
      placeId: 'home',
      memberUserId: 'sam',
      onArrive: onArrive,
      onLeave: onLeave,
      inside: inside,
      lastChangedAt: null,
    );

/// Sam at [metersNorth] of Home.
PresenceRow _sam(double metersNorth, {DateTime? updatedAt}) => PresenceRow(
  userId: 'sam',
  handle: 'sam',
  displayName: 'Sam',
  lat: 38.9000 + metersNorth / 111_320,
  lon: -77.0300,
  driving: false,
  updatedAt: updatedAt ?? _now,
);

void main() {
  const engine = PlaceAlertEngine();

  group('PlaceAlertEngine', () {
    test('first observation records the state and fires nothing', () {
      final d = engine.evaluate(
        places: [_home()],
        rules: [_rule(inside: null)],
        presence: [_sam(20)],
        now: _now,
      );
      expect(d.events, isEmpty);
      expect(d.changes.single.inside, isTrue);
    });

    test('entering the radius fires an arrival', () {
      final d = engine.evaluate(
        places: [_home()],
        rules: [_rule(inside: false)],
        presence: [_sam(100)],
        now: _now,
      );
      expect(d.events.single.arrived, isTrue);
      expect(d.events.single.title, 'Sam arrived at Home');
      expect(d.changes.single.inside, isTrue);
    });

    test('leaving needs radius plus the margin (hysteresis)', () {
      final wobble = engine.evaluate(
        places: [_home()],
        rules: [_rule(inside: true)],
        presence: [_sam(180)],
        now: _now,
      );
      expect(wobble.events, isEmpty);
      expect(wobble.changes, isEmpty);

      final gone = engine.evaluate(
        places: [_home()],
        rules: [_rule(inside: true)],
        presence: [_sam(260)],
        now: _now,
      );
      expect(gone.events.single.arrived, isFalse);
      expect(gone.events.single.title, 'Sam left Home');
      expect(gone.changes.single.inside, isFalse);
    });

    test('stale presence changes nothing', () {
      final d = engine.evaluate(
        places: [_home()],
        rules: [_rule(inside: false)],
        presence: [
          _sam(10, updatedAt: _now.subtract(const Duration(minutes: 30))),
        ],
        now: _now,
      );
      expect(d.events, isEmpty);
      expect(d.changes, isEmpty);
    });

    test('a rule with only onLeave stays silent on arrival', () {
      final d = engine.evaluate(
        places: [_home()],
        rules: [_rule(inside: false, onArrive: false)],
        presence: [_sam(10)],
        now: _now,
      );
      expect(d.events, isEmpty);
      expect(d.changes.single.inside, isTrue);
    });

    test('members and places without a rule are ignored', () {
      final d = engine.evaluate(
        places: [_home()],
        rules: [_rule(inside: false)],
        presence: [
          PresenceRow(
            userId: 'other',
            handle: 'o',
            displayName: 'Other',
            lat: 38.9,
            lon: -77.03,
            driving: true,
            updatedAt: _now,
          ),
        ],
        now: _now,
      );
      expect(d.events, isEmpty);
      expect(d.changes, isEmpty);
    });
  });

  group('PlaceAlertRunner', () {
    final skip = skipWithoutSqlite();

    test('persists states and notifies once per transition', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = PlacesRepo(db, now: () => 1);
      final id = await repo.addPlace(
        label: 'Home',
        kind: PlaceKind.home,
        lat: 38.9,
        lon: -77.03,
      );
      await repo.setAlert(id, 'sam', onArrive: true, onLeave: true);
      final fired = <String>[];
      final runner = PlaceAlertRunner(
        repo: repo,
        notify: (e) async => fired.add(e.title),
        now: () => _now,
      );

      // Far away first: records "outside", no event.
      expect(await runner.onPresence([_sam(2000)]), 0);
      expect((await repo.allAlerts()).single.inside, isFalse);
      // Arrives.
      expect(await runner.onPresence([_sam(10)]), 1);
      expect(fired, ['Sam arrived at Home']);
      // Still inside: nothing.
      expect(await runner.onPresence([_sam(30)]), 0);
      // Leaves.
      expect(await runner.onPresence([_sam(400)]), 1);
      expect(fired.last, 'Sam left Home');
      expect((await repo.allAlerts()).single.inside, isFalse);
    }, skip: skip);

    test('quiet hours block friend alerts but never crash alerts', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      await db.setSetting(
        QuietHours.settingsKey,
        const QuietHours(
          enabled: true,
          startMinutes: 22 * 60,
          endMinutes: 7 * 60,
        ).toJson(),
      );
      final quiet = NotificationGate(
        db,
        now: () => DateTime(2026, 11, 3, 23, 30),
      );
      expect(await quiet.allows(NotificationCategory.friends), isFalse);
      expect(await quiet.allows(NotificationCategory.crash), isTrue);
      final day = NotificationGate(db, now: () => DateTime(2026, 11, 3, 12));
      expect(await day.allows(NotificationCategory.friends), isTrue);
    }, skip: skip);

    test('deleting a place removes its alerts', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = PlacesRepo(db, now: () => 1);
      final id = await repo.addPlace(
        label: 'Work',
        kind: PlaceKind.work,
        lat: 1,
        lon: 2,
        radiusM: 9999,
      );
      final stored = (await repo.places()).single;
      expect(stored.radiusM, PlacesRepo.maxRadiusM);
      await repo.setAlert(id, 'sam', onArrive: true, onLeave: false);
      await repo.setAlert(id, 'sam', onArrive: false, onLeave: false);
      expect(await repo.allAlerts(), isEmpty);
      await repo.setAlert(id, 'sam', onArrive: true, onLeave: false);
      await repo.deletePlace(id);
      expect(await repo.allAlerts(), isEmpty);
      expect(await repo.places(), isEmpty);
    }, skip: skip);

    test('recordInside keeps the rule flags', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = PlacesRepo(db, now: () => 1);
      final id = await repo.addPlace(
        label: 'Home',
        kind: PlaceKind.home,
        lat: 1,
        lon: 2,
      );
      await repo.setAlert(id, 'sam', onArrive: true, onLeave: true);
      await repo.recordInside(id, 'sam', true, 5);
      final a = (await repo.allAlerts()).single;
      expect(a.inside, isTrue);
      expect(a.onArrive, isTrue);
      expect(a.lastChangedAt, 5);
      // setAlert keeps the state the engine recorded.
      await repo.setAlert(id, 'sam', onArrive: false, onLeave: true);
      expect((await repo.allAlerts()).single.inside, isTrue);
      await db
          .update(db.placeAlerts)
          .write(const PlaceAlertsCompanion(inside: Value(null)));
      expect((await repo.allAlerts()).single.inside, isNull);
    }, skip: skip);
  });
}
