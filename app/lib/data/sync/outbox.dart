import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// Uploads one outbox row. Must be idempotent: the same payload may be
/// delivered more than once. Throw [OutboxRetryLater] to postpone the whole
/// pass without counting an attempt (not signed in, no network), or
/// [OutboxSkip] to leave just this row alone and carry on with the next one;
/// any other exception counts as a failed attempt with exponential backoff.
typedef OutboxHandler = Future<void> Function(Map<String, dynamic> payload);

/// "Not now": the row stays queued, the attempt counter is untouched, and the
/// pass stops (every later row would hit the same wall).
class OutboxRetryLater implements Exception {
  const OutboxRetryLater([this.reason = 'retry later']);
  final String reason;
  @override
  String toString() => 'OutboxRetryLater($reason)';
}

/// "Not mine": the row belongs to another account on this phone. It stays
/// queued untouched for whoever it belongs to; the pass continues.
class OutboxSkip implements Exception {
  const OutboxSkip([this.reason = 'skip']);
  final String reason;
  @override
  String toString() => 'OutboxSkip($reason)';
}

/// The one queue every cloud write goes through (docs/03 §7). Features
/// register a handler per `kind`; the worker drains due rows in order and
/// retries failures with backoff capped at six hours. Rows that fail
/// [giveUpAfter] times are dropped and logged, so a poisoned payload cannot
/// block the queue forever.
///
/// Rows with a caller-chosen id are "latest intent wins": enqueueing the same
/// id again replaces the payload and resets the retry state, so toggling a
/// setting twice while offline uploads the final value, not the first.
class OutboxWorker {
  OutboxWorker(this.db, {int Function()? now, this.giveUpAfter = 30})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase db;
  final int Function() _now;
  final int giveUpAfter;
  final Map<String, OutboxHandler> _handlers = {};
  Future<int>? _draining;
  bool _dirty = false;
  Timer? _debounce;

  static const _uuid = Uuid();

  void register(String kind, OutboxHandler handler) {
    _handlers[kind] = handler;
  }

  bool handles(String kind) => _handlers.containsKey(kind);

  /// Queues a write and schedules a drain shortly after. Returns the row id.
  /// An existing row with the same [id] is replaced (payload and retry state).
  Future<String> enqueue(
    String kind,
    Map<String, dynamic> payload, {
    String? id,
  }) async {
    final rowId = id ?? _uuid.v4();
    await db.enqueueOutbox(
      OutboxCompanion(
        id: Value(rowId),
        kind: Value(kind),
        payload: Value(jsonEncode(payload)),
        createdAt: Value(_now()),
        attempts: const Value(0),
        nextAttemptAt: const Value(0),
        lastError: const Value(null),
      ),
    );
    if (_draining != null) {
      // A pass is running and may have read its rows already: make sure one
      // more pass follows it, without waiting for the debounce timer.
      _dirty = true;
    } else {
      scheduleDrain();
    }
    return rowId;
  }

  /// Drains soon, coalescing bursts of enqueues into one pass.
  void scheduleDrain([Duration delay = const Duration(milliseconds: 300)]) {
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      drain();
    });
  }

  /// Processes every due row. Concurrent calls share the running pass, and a
  /// call that arrives while a pass is in flight guarantees one more pass
  /// afterwards, so a row enqueued mid-pass is delivered without waiting for
  /// the next external trigger. Returns how many rows were delivered.
  Future<int> drain() {
    final running = _draining;
    if (running != null) {
      _dirty = true;
      return running;
    }
    final pass = _runPasses();
    _draining = pass;
    return pass;
  }

  Future<int> _runPasses() async {
    var total = 0;
    try {
      do {
        _dirty = false;
        total += await _drainOnce();
      } while (_dirty);
    } finally {
      _draining = null;
    }
    return total;
  }

  Future<int> _drainOnce() async {
    var delivered = 0;
    final rows = await db.dueOutbox(_now());
    for (final row in rows) {
      final handler = _handlers[row.kind];
      if (handler == null) {
        // Unknown kind: a newer app wrote it, or a feature is not loaded yet.
        continue;
      }
      try {
        final payload = jsonDecode(row.payload) as Map<String, dynamic>;
        await handler(payload);
        await db.deleteOutbox(row.id);
        delivered++;
      } on OutboxRetryLater {
        // Leave the row exactly as it is; a later drain picks it up.
        break;
      } on OutboxSkip {
        // Another account's row: leave it, keep going.
        continue;
      } catch (e) {
        final attempts = row.attempts + 1;
        if (attempts >= giveUpAfter) {
          debugPrint(
            'outbox: dropping ${row.kind} ${row.id} after $attempts attempts: $e',
          );
          await db.deleteOutbox(row.id);
          continue;
        }
        final backoffMs = math.min(
          30_000 * math.pow(2, attempts - 1).toInt(),
          const Duration(hours: 6).inMilliseconds,
        );
        await db.failOutbox(
          row.id,
          attempts: attempts,
          nextAttemptAt: _now() + backoffMs,
          error: e.toString(),
        );
      }
    }
    return delivered;
  }

  void dispose() {
    _debounce?.cancel();
  }
}

final outboxWorkerProvider = Provider<OutboxWorker>((ref) {
  final worker = OutboxWorker(ref.watch(databaseProvider));
  ref.onDispose(worker.dispose);
  return worker;
});

/// Rows still waiting to upload, for the diagnostics screen.
final outboxCountProvider = StreamProvider<int>(
  (ref) => ref.watch(databaseProvider).watchOutboxCount(),
);
