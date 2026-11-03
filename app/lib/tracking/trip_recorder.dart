import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show PhoneEventKind;
import 'package:flutter/foundation.dart';

import '../data/db/database.dart';
import '../data/models/trip_phase.dart';
import 'tracking_models.dart';

/// Turns plugin events into database rows (docs/08 §4, §5).
///
/// Idempotent: the same event delivered twice (live and then from the spool)
/// changes nothing the second time. Fix batches are keyed by `(tripId, t)`;
/// the other tables use natural primary keys with insert-or-ignore.
class TripRecorder {
  TripRecorder(this._db, {required this.onTripEnded, int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final int Function() _now;

  /// Called once per `ended` phase event, after the row is updated.
  final FutureOr<void> Function(String tripId) onTripEnded;

  /// Trips whose screen is currently projecting to CarPlay / Android Auto.
  /// Phone handling while projecting is not phone handling (docs/02 §3).
  final Set<String> _projecting = {};

  /// Tentatives discarded in this process. A `tentative` replayed from the
  /// spool after its `discarded` must not resurrect the row.
  final Set<String> _discarded = {};

  /// Serialises writes so a burst of spooled events keeps its order.
  Future<void> _chain = Future.value();

  Future<void> handle(TrackingEvent event) {
    final next = _chain.then((_) => _handle(event)).catchError((
      Object e,
      StackTrace s,
    ) {
      debugPrint('TripRecorder: failed to handle ${event.runtimeType}: $e\n$s');
    });
    _chain = next;
    return next;
  }

  Future<void> handleAll(Iterable<TrackingEvent> events) async {
    for (final e in events) {
      await handle(e);
    }
  }

  /// Completes when every event handed in so far has been written (and, for
  /// an `ended` event, finalised).
  Future<void> flush() => _chain;

  Future<void> _handle(TrackingEvent event) async {
    switch (event) {
      case PhaseEvent():
        await _phase(event);
      case FixesEvent():
        await _fixes(event);
      case MotionPeaksEvent():
        await _ensureTrip(event.tripId!, event.t, null);
        await _db.insertMotionPeaks([
          for (final p in event.peaks)
            MotionPeaksCompanion.insert(
              tripId: event.tripId!,
              t: p.t,
              peak: p.peak,
            ),
        ]);
      case PhoneEventRaw():
        await _phone(event);
      case HintEvent():
        await _ensureTrip(event.tripId!, event.t, null);
        if (event.name != null && event.name!.isNotEmpty) {
          await _db.updateTrip(
            event.tripId!,
            TripsCompanion(vehicleLabel: Value(event.name)),
          );
        }
      case TrackingError():
        debugPrint('tracking plugin error ${event.code}: ${event.message}');
    }
  }

  Future<void> _ensureTrip(String tripId, int t, String? trigger) =>
      _db.ensureTrip(
        TripsCompanion.insert(
          id: tripId,
          startedAt: t,
          phase: TripPhase.recording.wire,
          triggerKind: Value(trigger),
          createdAt: _now(),
        ),
      );

  /// Phase events are replayed from the spool after they were seen live
  /// (docs/08 §5), so every branch here must be a no-op the second time and
  /// must never move a trip backwards in its lifecycle.
  Future<void> _phase(PhaseEvent e) async {
    final tripId = e.tripId!;
    switch (e.phase) {
      case TripPhaseSignal.tentative:
        if (_discarded.contains(tripId)) return;
        await _ensureTrip(tripId, e.t, e.reason);
      case TripPhaseSignal.active:
        if (_discarded.contains(tripId)) return;
        final startedAt = e.startedAt ?? e.t;
        await _ensureTrip(tripId, startedAt, e.reason);
        final existing = await _db.tripById(tripId);
        if (existing == null ||
            existing.deletedAt != null ||
            existing.phase != TripPhase.recording.wire) {
          return; // already ended or scored; a replayed event
        }
        await _db.updateTrip(
          tripId,
          TripsCompanion(
            startedAt: Value(startedAt),
            triggerKind: e.reason == null
                ? const Value.absent()
                : Value(e.reason),
          ),
        );
      case TripPhaseSignal.discarded:
        _projecting.remove(tripId);
        _discarded.add(tripId);
        await _db.deleteTripHard(tripId);
      case TripPhaseSignal.ended:
        _projecting.remove(tripId);
        final existing = await _db.tripById(tripId);
        if (existing == null) {
          // Nothing recorded for it (spool lost). Nothing to score either.
          return;
        }
        if (existing.phase != TripPhase.recording.wire ||
            existing.endedAt != null) {
          return; // already ended; replayed event
        }
        await _db.updateTrip(
          tripId,
          TripsCompanion(
            endedAt: Value(e.t),
            endReason: Value(e.reason),
            phase: Value(TripPhase.pendingPassenger.wire),
          ),
        );
        await onTripEnded(tripId);
    }
  }

  Future<void> _fixes(FixesEvent e) async {
    if (e.fixes.isEmpty) return;
    final tripId = e.tripId!;
    await _ensureTrip(tripId, e.fixes.first.t, null);
    await _db.insertFixBatch(tripId, e.t, [
      for (final f in e.fixes)
        SamplesCompanion.insert(
          tripId: tripId,
          t: f.t,
          lat: f.lat,
          lon: f.lon,
          speed: Value(f.speed),
          accuracy: f.accuracy,
          heading: Value(f.heading),
          altitude: Value(f.altitude),
        ),
    ]);
  }

  Future<void> _phone(PhoneEventRaw e) async {
    final tripId = e.tripId!;
    switch (e.kind) {
      case PhoneSignal.projectionOn:
        _projecting.add(tripId);
        return;
      case PhoneSignal.projectionOff:
        _projecting.remove(tripId);
        return;
      case PhoneSignal.unlock:
      case PhoneSignal.interaction:
      case PhoneSignal.callStart:
        if (_projecting.contains(tripId)) return;
        await _ensureTrip(tripId, e.t, null);
        // Android reports an `interaction` alongside every `unlock`. One
        // physical act, one engine event: within a second the unlock wins.
        if (e.kind == PhoneSignal.interaction || e.kind == PhoneSignal.unlock) {
          final near = await _db.phoneEventsNear(
            tripId,
            e.t,
            unlockMergeWindowMs,
          );
          for (final other in near) {
            if (e.kind == PhoneSignal.interaction &&
                other.kind == PhoneEventKind.unlock.wire) {
              return;
            }
            if (e.kind == PhoneSignal.unlock &&
                other.kind == PhoneEventKind.interaction.wire) {
              await _db.deletePhoneEvent(tripId, other.t, other.kind);
            }
          }
        }
        await _db.insertPhoneEvent(
          PhoneEventsCompanion.insert(
            tripId: tripId,
            t: e.t,
            kind: engineKind(e.kind)!.wire,
          ),
        );
      case PhoneSignal.screenOn:
      case PhoneSignal.screenOff:
      case PhoneSignal.callEnd:
      case PhoneSignal.foreground:
      case PhoneSignal.background:
        return;
    }
  }

  /// An `interaction` this close to an `unlock` is the same act.
  static const int unlockMergeWindowMs = 1000;

  /// The scoring engine's kind for a raw signal, or null when it is not one
  /// the engine scores.
  static PhoneEventKind? engineKind(PhoneSignal s) => switch (s) {
    PhoneSignal.unlock => PhoneEventKind.unlock,
    PhoneSignal.interaction => PhoneEventKind.interaction,
    PhoneSignal.callStart => PhoneEventKind.callHandheld,
    _ => null,
  };
}
