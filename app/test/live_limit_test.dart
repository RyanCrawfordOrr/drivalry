import 'dart:async';

import 'package:drivalry/features/cues/live_limit.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart'
    show GpsSample, RoadClass;
import 'package:flutter_test/flutter_test.dart';

PackWay way(int id, int posted, {String? name}) => PackWay(
  id: id,
  roadClass: RoadClass.residential,
  lats: const [38.9, 38.901],
  lons: const [-77.03, -77.03],
  name: name ?? 'Way $id',
  maxForward: posted,
  mph: true,
  source: LimitSource.tag,
);

/// Returns a fixed way for every fix, applying overrides like the real
/// matcher does; `wayFor` may change between calls to script a limit change.
class FakeLocator implements LiveLocator {
  FakeLocator(this.wayFor);
  PackWay? Function(GpsSample fix) wayFor;
  bool closed = false;
  int calls = 0;
  Map<int, LimitOverride> lastOverrides = const {};

  @override
  String get region => 'us-dc';

  @override
  RoadMatch? locate(
    GpsSample fix, {
    Map<int, LimitOverride> overrides = const {},
  }) {
    calls++;
    lastOverrides = overrides;
    final w = wayFor(fix);
    if (w == null) return null;
    final ov = overrides[w.id];
    return RoadMatch(
      way: w,
      forward: true,
      distanceM: 2,
      limitMps: ov?.limitMps ?? w.limitMps(forward: true),
      confidence: ov?.confidence ?? w.confidence,
    );
  }

  @override
  void close() => closed = true;
}

class FakeFactory implements LiveLocatorFactory {
  FakeFactory(this.locator);
  final LiveLocator? locator;
  int opens = 0;

  @override
  Future<LiveLocator?> openFor(double lat, double lon) async {
    opens++;
    return locator;
  }
}

Fix fix(int t, {double speed = 10}) =>
    Fix(t: t, lat: 38.9005, lon: -77.03, accuracy: 5, speed: speed, heading: 0);

FixesEvent fixes(String trip, List<Fix> f) =>
    FixesEvent(tripId: trip, t: f.last.t, fixes: f);

void main() {
  const t0 = 1_700_000_000_000;

  test('matches every 5 s of trip time and reports the limit', () async {
    final loc = FakeLocator((_) => way(1, 25, name: 'Elm St'));
    final factory = FakeFactory(loc);
    final tracker = LiveLimitTracker(
      factory: factory,
      overridesFor: (_) async => const {},
    );
    final seen = <LiveLimitState>[];
    tracker.states.listen(seen.add);

    await tracker.handle(
      PhaseEvent(
        tripId: 'a',
        t: t0,
        phase: TripPhaseSignal.active,
        startedAt: t0,
      ),
    );
    // 15 fixes at 1 Hz, as one plugin batch.
    await tracker.handle(
      fixes('a', [for (var i = 0; i < 15; i++) fix(t0 + i * 1000, speed: 12)]),
    );
    expect(factory.opens, 1);
    expect(loc.calls, 3, reason: 'fixes at 0, 5 and 10 s');
    final s = tracker.state;
    expect(s.tripId, 'a');
    expect(s.posted, 25);
    expect(s.unitLabel, 'mph');
    expect(s.roadName, 'Elm St');
    expect(s.hasLimit, isTrue);
    expect(s.limitMps, closeTo(25 * 0.44704, 1e-9));
    expect(s.speedMps, 12);
    expect(s.overByMps, closeTo(12 - 25 * 0.44704, 1e-9));
    expect(s.sinceMs, t0);

    // Limit changes: sinceMs moves.
    loc.wayFor = (_) => way(2, 35);
    await tracker.handle(fixes('a', [fix(t0 + 20_000)]));
    expect(tracker.state.posted, 35);
    expect(tracker.state.sinceMs, t0 + 20_000);

    await tracker.handle(
      PhaseEvent(tripId: 'a', t: t0 + 30_000, phase: TripPhaseSignal.ended),
    );
    expect(loc.closed, isTrue);
    expect(tracker.state.tripId, isNull);
    expect(seen.length, greaterThan(3));
    tracker.dispose();
  });

  test(
    'no pack means no limit, and the pack is looked for again later',
    () async {
      final factory = FakeFactory(null);
      final tracker = LiveLimitTracker(
        factory: factory,
        overridesFor: (_) async => const {},
        openRetryMs: 60_000,
      );
      await tracker.handle(
        PhaseEvent(tripId: 'b', t: t0, phase: TripPhaseSignal.active),
      );
      await tracker.handle(
        fixes('b', [fix(t0), fix(t0 + 5000), fix(t0 + 10_000)]),
      );
      expect(factory.opens, 1, reason: 'one attempt per minute');
      expect(tracker.state.hasLimit, isFalse);
      expect(tracker.state.limitMps, isNull);
      expect(tracker.state.speedMps, 10);
      expect(tracker.state.overByMps, isNull);
      await tracker.handle(fixes('b', [fix(t0 + 61_000)]));
      expect(factory.opens, 2);
      tracker.dispose();
    },
  );

  test('no road near the car clears the limit', () async {
    var onRoad = true;
    final loc = FakeLocator((_) => onRoad ? way(1, 25) : null);
    final tracker = LiveLimitTracker(
      factory: FakeFactory(loc),
      overridesFor: (_) async => const {},
    );
    await tracker.handle(
      PhaseEvent(tripId: 'c', t: t0, phase: TripPhaseSignal.active),
    );
    await tracker.handle(fixes('c', [fix(t0)]));
    expect(tracker.state.posted, 25);
    onRoad = false;
    await tracker.handle(fixes('c', [fix(t0 + 5000)]));
    expect(tracker.state.posted, isNull);
    expect(tracker.state.hasLimit, isFalse);
    expect(tracker.state.roadName, isNull);
    tracker.dispose();
  });

  test('overrides for the pack region are applied', () async {
    final loc = FakeLocator((_) => way(7, 45));
    String? askedRegion;
    final tracker = LiveLimitTracker(
      factory: FakeFactory(loc),
      overridesFor: (region) async {
        askedRegion = region;
        return {
          7: const LimitOverride(wayId: 7, limitMps: 13.4112, confidence: 0.85),
        };
      },
    );
    await tracker.handle(
      PhaseEvent(tripId: 'd', t: t0, phase: TripPhaseSignal.active),
    );
    await tracker.handle(fixes('d', [fix(t0)]));
    expect(askedRegion, 'us-dc');
    expect(loc.lastOverrides.keys, [7]);
    expect(tracker.state.limitMps, closeTo(13.4112, 1e-9));
    expect(tracker.state.confidence, 0.85);
    // Posted stays the pack's number for display.
    expect(tracker.state.posted, 45);
    tracker.dispose();
  });

  test('fixes for a trip that was never seen starting adopt it', () async {
    final loc = FakeLocator((_) => way(1, 25));
    final tracker = LiveLimitTracker(
      factory: FakeFactory(loc),
      overridesFor: (_) async => const {},
    );
    await tracker.handle(fixes('late', [fix(t0)]));
    expect(tracker.state.tripId, 'late');
    expect(tracker.state.posted, 25);
    tracker.dispose();
  });

  test('a low-confidence limit is not a usable limit', () {
    const s = LiveLimitState(
      limitMps: 11.176,
      posted: 25,
      confidence: 0.5,
      speedMps: 20,
    );
    expect(s.hasLimit, isFalse);
    expect(s.overByMps, isNull);
  });

  test('events are processed in order even while the pack opens', () async {
    final opened = Completer<void>();
    final loc = FakeLocator((_) => way(1, 25));
    final tracker = LiveLimitTracker(
      factory: _SlowFactory(loc, opened.future),
      overridesFor: (_) async => const {},
    );
    unawaited(
      tracker.handle(
        PhaseEvent(tripId: 'e', t: t0, phase: TripPhaseSignal.active),
      ),
    );
    unawaited(tracker.handle(fixes('e', [fix(t0)])));
    final ended = tracker.handle(
      PhaseEvent(tripId: 'e', t: t0 + 9000, phase: TripPhaseSignal.ended),
    );
    opened.complete();
    await ended;
    expect(tracker.state.tripId, isNull);
    expect(loc.closed, isTrue);
    tracker.dispose();
  });
}

class _SlowFactory implements LiveLocatorFactory {
  _SlowFactory(this.locator, this.gate);
  final LiveLocator locator;
  final Future<void> gate;

  @override
  Future<LiveLocator?> openFor(double lat, double lon) async {
    await gate;
    return locator;
  }
}
