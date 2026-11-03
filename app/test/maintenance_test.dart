import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/garage/maintenance.dart';
import 'package:flutter_test/flutter_test.dart';

const day = Duration.millisecondsPerDay;

MaintenanceItem item({
  double? intervalKm,
  int? intervalDays,
  double? lastDoneKm,
  int? lastDoneAt,
  int createdAt = 0,
}) => MaintenanceItem(
  id: 'm',
  vehicleId: 'v',
  title: 'Oil',
  intervalKm: intervalKm,
  intervalDays: intervalDays,
  lastDoneKm: lastDoneKm,
  lastDoneAt: lastDoneAt,
  createdAt: createdAt,
);

void main() {
  group('dueStatus', () {
    test('by distance', () {
      final due = dueStatus(
        item(intervalKm: 8000, lastDoneKm: 10000),
        nowMs: 0,
        odometerKm: 17600,
      );
      expect(due.kmRemaining, 400);
      expect(due.daysRemaining, isNull);
      expect(due.isDue, isFalse);
      expect(due.isSoon, isTrue);
      expect(due.describe(useMiles: false), 'in 400 km');
      expect(due.describe(useMiles: true), 'in 249 mi');
    });

    test('distance overdue', () {
      final due = dueStatus(
        item(intervalKm: 8000, lastDoneKm: 10000),
        nowMs: 0,
        odometerKm: 18100,
      );
      expect(due.isDue, isTrue);
      expect(due.describe(useMiles: false), 'Due now');
    });

    test('distance interval without an odometer estimate is unknown', () {
      final due = dueStatus(item(intervalKm: 8000, lastDoneKm: 100), nowMs: 0);
      expect(due.unknown, isTrue);
      expect(due.describe(useMiles: false), 'No odometer yet');
    });

    test('by time, from last done', () {
      final due = dueStatus(
        item(intervalDays: 180, lastDoneAt: 0),
        nowMs: 170 * day,
      );
      expect(due.daysRemaining, 10);
      expect(due.isSoon, isTrue);
      expect(due.isDue, isFalse);
    });

    test('by time, falls back to creation', () {
      final due = dueStatus(
        item(intervalDays: 30, createdAt: 10 * day),
        nowMs: 41 * day,
      );
      expect(due.daysRemaining, -1);
      expect(due.isDue, isTrue);
    });

    test('both dimensions: whichever comes first', () {
      final due = dueStatus(
        item(intervalKm: 5000, intervalDays: 365, lastDoneKm: 0, lastDoneAt: 0),
        nowMs: 100 * day,
        odometerKm: 4900,
      );
      expect(due.kmRemaining, 100);
      expect(due.daysRemaining, 265);
      expect(due.isSoon, isTrue);
      expect(due.describe(useMiles: false), 'in 100 km · 265 days');
    });
  });

  test('estimateOdometerKm', () {
    expect(
      estimateOdometerKm(lastReadingKm: 1000, kmDrivenSinceReading: 12.5),
      1012.5,
    );
    expect(
      estimateOdometerKm(lastReadingKm: null, kmDrivenSinceReading: 12.5),
      isNull,
    );
  });
}
