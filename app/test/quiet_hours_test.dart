import 'package:drivalry/data/push/local_notifications.dart';
import 'package:drivalry/data/push/push_service.dart';
import 'package:drivalry/data/push/quiet_hours.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

void main() {
  group('QuietHours', () {
    DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 3, h, m);

    test('disabled is never quiet', () {
      const q = QuietHours(enabled: false, startMinutes: 0, endMinutes: 1439);
      expect(q.isQuiet(at(3)), isFalse);
    });

    test('same-day window', () {
      const q = QuietHours(
        enabled: true,
        startMinutes: 13 * 60,
        endMinutes: 15 * 60,
      );
      expect(q.isQuiet(at(12, 59)), isFalse);
      expect(q.isQuiet(at(13)), isTrue);
      expect(q.isQuiet(at(14, 30)), isTrue);
      expect(q.isQuiet(at(15)), isFalse);
    });

    test('window spanning midnight', () {
      const q = QuietHours(
        enabled: true,
        startMinutes: 22 * 60,
        endMinutes: 7 * 60,
      );
      expect(q.isQuiet(at(21, 59)), isFalse);
      expect(q.isQuiet(at(22)), isTrue);
      expect(q.isQuiet(at(23, 59)), isTrue);
      expect(q.isQuiet(at(0)), isTrue);
      expect(q.isQuiet(at(6, 59)), isTrue);
      expect(q.isQuiet(at(7)), isFalse);
      expect(q.isQuiet(at(12)), isFalse);
    });

    test('JSON round trip and defaults', () {
      const q = QuietHours(enabled: true, startMinutes: 1320, endMinutes: 420);
      final back = QuietHours.fromJson(q.toJson());
      expect(back.enabled, isTrue);
      expect(back.startMinutes, 1320);
      expect(back.endMinutes, 420);
      expect(QuietHours.fromJson(null).enabled, isFalse);
      expect(QuietHours.fromJson('garbage').startMinutes, 22 * 60);
      expect(QuietHours.formatMinutes(420), '07:00');
    });
  });

  group('NotificationGate', () {
    final skip = skipWithoutSqlite();

    test(
      'crash always passes; switches and quiet hours gate the rest',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        var now = DateTime(2026, 11, 3, 23, 30);
        final gate = NotificationGate(db, now: () => now);

        expect(await gate.allows(NotificationCategory.social), isTrue);
        await db.setSetting(
          QuietHours.settingsKey,
          const QuietHours(
            enabled: true,
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
          ).toJson(),
        );
        expect(await gate.allows(NotificationCategory.social), isFalse);
        expect(await gate.allows(NotificationCategory.crash), isTrue);

        now = DateTime(2026, 11, 3, 12);
        expect(await gate.allows(NotificationCategory.social), isTrue);
        await db.setSetting(NotificationCategory.social.settingsKey, 'false');
        expect(await gate.allows(NotificationCategory.social), isFalse);
        expect(await gate.allows(NotificationCategory.friends), isTrue);
      },
      skip: skip,
    );
  });
}
