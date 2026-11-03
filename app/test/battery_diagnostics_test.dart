import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/diagnostics/battery_sampler.dart';
import 'package:drivalry/data/diagnostics/battery_stats.dart';
import 'package:drivalry/data/diagnostics/detection_counters.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/features/settings/diagnostics_screen.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

BatterySample _s(int t, double level, BatteryPhase phase, {String? tripId}) =>
    BatterySample(t: t, level: level, phase: phase.wire, tripId: tripId);

const _h = 3_600_000;

void main() {
  final skip = skipWithoutSqlite();

  group('BatteryStats.compute', () {
    test('empty and single readings give no rates, never throw', () {
      final empty = BatteryStats.compute(const []);
      expect(empty.drivingPctPerHour, isNull);
      expect(empty.parkedPctPerDay, isNull);
      final one = BatteryStats.compute([_s(0, 0.9, BatteryPhase.parked)]);
      expect(one.parkedPctPerDay, isNull);
      expect(one.parkedPairs, 0);
    });

    test('driving rate needs two trips and half an hour, then averages', () {
      final oneTrip = BatteryStats.compute([
        _s(0, 0.80, BatteryPhase.tripStart, tripId: 'a'),
        _s(_h, 0.70, BatteryPhase.tripEnd, tripId: 'a'),
      ]);
      expect(oneTrip.drivingPctPerHour, isNull, reason: 'one pair only');
      expect(oneTrip.drivingPairs, 1);

      final two = BatteryStats.compute([
        _s(0, 0.80, BatteryPhase.tripStart, tripId: 'a'),
        _s(_h, 0.70, BatteryPhase.tripEnd, tripId: 'a'), // 10 pts / 1 h
        _s(5 * _h, 0.60, BatteryPhase.tripStart, tripId: 'b'),
        _s(6 * _h, 0.55, BatteryPhase.tripEnd, tripId: 'b'), // 5 pts / 1 h
        // Charged in the car: ignored, not counted as negative drain.
        _s(8 * _h, 0.50, BatteryPhase.tripStart, tripId: 'c'),
        _s(9 * _h, 0.90, BatteryPhase.tripEnd, tripId: 'c'),
        // End without a start: ignored.
        _s(10 * _h, 0.40, BatteryPhase.tripEnd, tripId: 'd'),
      ]);
      expect(two.drivingPairs, 2);
      expect(two.drivingPctPerHour, closeTo(7.5, 1e-9));
      expect(two.drivingHours, closeTo(2, 1e-9));
    });

    test('parked rate pairs daily readings and skips gaps with a trip', () {
      final stats = BatteryStats.compute([
        _s(0, 0.90, BatteryPhase.parked),
        _s(24 * _h, 0.80, BatteryPhase.parked), // 10 pts / day
        // A trip in between: this gap says nothing about parked drain.
        _s(30 * _h, 0.78, BatteryPhase.tripStart, tripId: 'a'),
        _s(31 * _h, 0.75, BatteryPhase.tripEnd, tripId: 'a'),
        _s(48 * _h, 0.70, BatteryPhase.parked),
        // Half a day, charged in between: negative, skipped.
        _s(60 * _h, 0.95, BatteryPhase.parked),
        // Too close together (same sitting).
        _s(61 * _h, 0.94, BatteryPhase.parked),
        // 12 h, 3 pts: counts.
        _s(73 * _h, 0.91, BatteryPhase.parked),
      ]);
      expect(stats.parkedPairs, 2);
      // 10 pts over 24 h + 3 pts over 12 h = 13 pts over 1.5 days.
      expect(stats.parkedDays, closeTo(1.5, 1e-9));
      expect(stats.parkedPctPerDay, closeTo(13 / 1.5, 1e-9));
    });

    test('parked rate withheld under twelve hours of evidence', () {
      final stats = BatteryStats.compute([
        _s(0, 0.90, BatteryPhase.parked),
        _s(3 * _h, 0.88, BatteryPhase.parked),
      ]);
      expect(stats.parkedPairs, 1);
      expect(stats.parkedPctPerDay, isNull);
    });
  });

  group('BatterySampler', () {
    test(
      'samples trip start and end, parked once a day, purges after 30 days',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        var now = 100 * 24 * _h;
        var level = 0.9;
        var reads = 0;
        final sampler = BatterySampler(
          db: db,
          readLevel: () async {
            reads++;
            return level;
          },
          now: () => now,
        );

        await sampler.onEvent(
          PhaseEvent(tripId: 't1', t: now, phase: TripPhaseSignal.active),
        );
        now += _h;
        level = 0.8;
        await sampler.onEvent(
          PhaseEvent(tripId: 't1', t: now, phase: TripPhaseSignal.ended),
        );
        var rows = await db.batterySamplesSince(0);
        expect(rows.map((r) => r.phase), ['tripStart', 'tripEnd']);
        expect(rows.every((r) => r.tripId == 't1'), isTrue);

        // Parked: the first foreground samples, the next within 20 h does not.
        await sampler.onForeground();
        now += 2 * _h;
        await sampler.onForeground();
        rows = await db.batterySamplesSince(0);
        expect(rows.where((r) => r.phase == 'parked'), hasLength(1));

        // A parked fix a day later samples again.
        now += 22 * _h;
        await sampler.onEvent(
          ParkedFixEvent(t: now, lat: 38, lon: -77, accuracy: 10),
        );
        rows = await db.batterySamplesSince(0);
        expect(rows.where((r) => r.phase == 'parked'), hasLength(2));

        // Never a parked reading while a trip is active.
        await sampler.onEvent(
          PhaseEvent(tripId: 't2', t: now, phase: TripPhaseSignal.active),
        );
        now += 25 * _h;
        await sampler.onForeground();
        rows = await db.batterySamplesSince(0);
        expect(rows.where((r) => r.phase == 'parked'), hasLength(2));

        // Unknown level: nothing stored, no throw.
        final before = reads;
        level = -1;
        await sampler.onEvent(
          PhaseEvent(tripId: 't2', t: now, phase: TripPhaseSignal.ended),
        );
        expect(reads, before + 1);
        expect(
          (await db.batterySamplesSince(0)).where((r) => r.tripId == 't2'),
          hasLength(1),
          reason: 'start stored, end skipped',
        );

        now += 40 * 24 * _h;
        final purged = await sampler.purge();
        expect(purged, greaterThan(0));
        expect(await db.batterySamplesSince(0), isEmpty);
      },
      skip: skip,
    );
  });

  group('DetectionCounters.load', () {
    test('counts only what the stored rows can show', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      const now = 20 * 24 * _h;
      const day = 24 * _h;
      Future<void> trip(
        String id, {
        required int startedAt,
        int? triggeredAt,
        int? endedAt,
        String? endReason,
        String? trigger,
        int? deletedAt,
      }) => db.ensureTrip(
        TripsCompanion.insert(
          id: id,
          startedAt: startedAt,
          triggeredAt: Value(triggeredAt),
          endedAt: Value(endedAt),
          endReason: Value(endReason),
          triggerKind: Value(trigger),
          phase: TripPhase.scored.wire,
          createdAt: startedAt,
          deletedAt: Value(deletedAt),
        ),
      );

      // Old trip outside the window: ignored.
      await trip('old', startedAt: now - 20 * day, trigger: 'manual');
      // Confirmed 3 min after the trigger: a late start.
      await trip(
        'late',
        startedAt: now - 3 * day + 180_000,
        triggeredAt: now - 3 * day,
        endedAt: now - 3 * day + _h,
        endReason: 'stationary',
        trigger: 'activity',
      );
      // Trigger time unknown (pre-schema-6 row): not countable.
      await trip('legacy', startedAt: now - 2 * day, trigger: 'bluetooth');
      // Started by hand (proxy for a missed start).
      await trip(
        'manual',
        startedAt: now - day,
        triggeredAt: now - day,
        trigger: 'manual',
      );
      // Deleted by the user.
      await trip('gone', startedAt: now - day + _h, deletedAt: now);

      // Samples for the stationary trip: last moving fix 10 min before the
      // end, so the end came 7 min after the 3-min rule should have fired.
      final lateStart = now - 3 * day + 180_000;
      await db.insertFixBatch('late', lateStart, [
        for (var i = 0; i < 5; i++)
          SamplesCompanion.insert(
            tripId: 'late',
            t: lateStart + i * 60_000,
            lat: 38,
            lon: -77,
            speed: const Value(12),
            accuracy: 5,
          ),
        SamplesCompanion.insert(
          tripId: 'late',
          t: lateStart + _h - 600_000,
          lat: 38,
          lon: -77,
          speed: const Value(5),
          accuracy: 5,
        ),
        SamplesCompanion.insert(
          tripId: 'late',
          t: lateStart + _h - 60_000,
          lat: 38,
          lon: -77,
          speed: const Value(0),
          accuracy: 5,
        ),
      ]);

      final d = await DetectionCounters.load(
        db,
        const TrackingDiagnostics(discardedTentatives: 4),
        now,
      );
      expect(d.trips, 3);
      expect(d.deletedTrips, 1);
      expect(d.manualStarts, 1);
      expect(d.lateStartsCountable, 2);
      expect(d.lateStarts, 1);
      expect(d.lateEndsCountable, 1);
      expect(d.lateEnds, 1);
      expect(d.discardedTentativesSinceInstall, 4);
    }, skip: skip);
  });

  group('Diagnostics rows', () {
    test('say "not enough data" instead of a rate, and n/a with a reason', () {
      final battery = batteryRows(const BatteryStats(drivingPairs: 1));
      expect(battery[0].$2, startsWith('not enough data yet (1 trips'));
      expect(battery[1].$2, startsWith('not enough data yet'));
      final measured = batteryRows(
        const BatteryStats(
          drivingPctPerHour: 7.25,
          drivingPairs: 4,
          drivingHours: 3,
          parkedPctPerDay: 2.5,
          parkedDays: 6,
          parkedPairs: 6,
        ),
      );
      expect(measured[0].$2, '7.3%/h over 4 trips');
      expect(measured[1].$2, '2.5%/day over 6.0 days');

      final rows = detectionRows(
        const DetectionCounters(
          trips: 0,
          manualStarts: 0,
          deletedTrips: 0,
          lateStarts: 0,
          lateStartsCountable: 0,
          lateEnds: 0,
          lateEndsCountable: 0,
          discardedTentativesSinceInstall: 2,
        ),
      );
      final byKey = {for (final (k, v) in rows) k: v};
      expect(byKey['Missed starts'], startsWith('n/a'));
      expect(byKey['Late starts (14 d)'], startsWith('n/a'));
      expect(byKey['Late ends (14 d)'], startsWith('n/a'));
      expect(
        byKey['False starts'],
        startsWith('2 dropped before they became trips'),
      );
    });
  });
}
