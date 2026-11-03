import 'dart:async';

import 'package:drivalry/data/sync/outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

void main() {
  final skip = skipWithoutSqlite();

  group('OutboxWorker', () {
    test('delivers due rows in order and deletes them', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      var now = 1_000_000;
      final worker = OutboxWorker(db, now: () => now);
      addTearDown(worker.dispose);
      final seen = <String>[];
      worker.register('echo', (p) async => seen.add(p['v'] as String));

      await worker.enqueue('echo', {'v': 'a'});
      now += 1;
      await worker.enqueue('echo', {'v': 'b'});
      expect(await worker.drain(), 2);
      expect(seen, ['a', 'b']);
      expect(await db.dueOutbox(now), isEmpty);
    });

    test('a stable id delivers the latest payload once', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final seen = <int>[];
      worker.register('once', (p) async => seen.add(p['v'] as int));
      await worker.enqueue('once', {'v': 1}, id: 'same');
      await worker.enqueue('once', {'v': 2}, id: 'same');
      expect(await worker.drain(), 1);
      expect(seen, [2], reason: 'newest intent wins');
    });

    test('re-enqueueing a failed stable id resets its retry state', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      var now = 1_000_000;
      final worker = OutboxWorker(db, now: () => now);
      addTearDown(worker.dispose);
      var fail = true;
      worker.register('toggle', (p) async {
        if (fail) throw StateError('offline');
      });
      await worker.enqueue('toggle', {'hidden': false}, id: 'hide');
      expect(await worker.drain(), 0);
      expect((await db.dueOutbox(now + 60_000)).single.attempts, 1);

      // The user flips the switch back before the retry: due immediately.
      await worker.enqueue('toggle', {'hidden': true}, id: 'hide');
      final row = (await db.dueOutbox(now)).single;
      expect(row.attempts, 0);
      expect(row.lastError, isNull);
      fail = false;
      expect(await worker.drain(), 1);
    });

    test('a row enqueued mid-pass is delivered by a follow-up pass', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 1);
      addTearDown(worker.dispose);
      final gate = Completer<void>();
      final seen = <String>[];
      worker.register('slow', (p) async {
        await gate.future;
        seen.add('slow');
      });
      worker.register('echo', (p) async => seen.add('echo'));

      await worker.enqueue('slow', {});
      final pass = worker.drain();
      await Future<void>.delayed(Duration.zero);
      await worker.enqueue('echo', {});
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      expect(await pass, 2, reason: 'both rows, one drain() call');
      expect(seen, ['slow', 'echo']);
      expect(await db.dueOutbox(1), isEmpty);
    });

    test('OutboxSkip leaves the row untouched and continues', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      var now = 1;
      final worker = OutboxWorker(db, now: () => now);
      addTearDown(worker.dispose);
      final seen = <String>[];
      worker.register('theirs', (p) async => throw const OutboxSkip());
      worker.register('mine', (p) async => seen.add('mine'));
      await worker.enqueue('theirs', {}, id: 'theirs-1');
      now++;
      await worker.enqueue('mine', {}, id: 'mine-1');
      expect(await worker.drain(), 1);
      expect(seen, ['mine']);
      final left = (await db.dueOutbox(now)).single;
      expect(left.id, 'theirs-1');
      expect(left.attempts, 0);
      expect(left.lastError, isNull);
    });

    test(
      'failures back off and are retried later; retry-later waits',
      () async {
        final db = memoryDatabase();
        addTearDown(db.close);
        var now = 1_000_000;
        final worker = OutboxWorker(db, now: () => now);
        addTearDown(worker.dispose);
        var attempts = 0;
        worker.register('flaky', (p) async {
          attempts++;
          if (attempts == 1) throw StateError('boom');
        });
        worker.register('offline', (p) async => throw const OutboxRetryLater());

        await worker.enqueue('flaky', {});
        expect(await worker.drain(), 0);
        final row = (await db.dueOutbox(now + 60_000)).single;
        expect(row.attempts, 1);
        expect(row.lastError, contains('boom'));
        expect(row.nextAttemptAt, now + 30_000);

        // Not due yet.
        expect(await worker.drain(), 0);
        now += 30_000;
        expect(await worker.drain(), 1);
        expect(attempts, 2);

        // Retry-later leaves the row untouched.
        await worker.enqueue('offline', {});
        expect(await worker.drain(), 0);
        final waiting = (await db.dueOutbox(now)).single;
        expect(waiting.attempts, 0);
        expect(waiting.lastError, isNull);
      },
    );

    test('rows without a handler are skipped, not dropped', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final worker = OutboxWorker(db, now: () => 5);
      addTearDown(worker.dispose);
      await worker.enqueue('future_kind', {});
      expect(await worker.drain(), 0);
      expect((await db.dueOutbox(5)).length, 1);
    });

    test('gives up after the configured number of attempts', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      var now = 0;
      final worker = OutboxWorker(db, now: () => now, giveUpAfter: 2);
      addTearDown(worker.dispose);
      worker.register('bad', (p) async => throw StateError('always'));
      await worker.enqueue('bad', {});
      expect(await worker.drain(), 0);
      now += const Duration(hours: 7).inMilliseconds;
      expect(await worker.drain(), 0);
      expect(await db.dueOutbox(now), isEmpty);
    });
  }, skip: skip);
}
