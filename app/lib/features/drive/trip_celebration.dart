import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/badges/badges_providers.dart';
import '../../data/db/database.dart';
import '../../data/models/trip_phase.dart';
import '../../data/models/trip_score_view.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../widgets/units.dart';
import 'share_card.dart';

/// Decides which scored trips get the full-screen moment, and when (docs/12
/// §5): once per trip, never while a drive is being recorded (queued until
/// parked), and never for trips that were already scored before this phone
/// started keeping track.
///
/// Pure: no clock, no database. The provider below feeds it snapshots and
/// persists [shown].
class CelebrationQueue {
  CelebrationQueue({Set<String> shown = const {}, this._primed = false})
    : _shown = {...shown};

  final Set<String> _shown;
  final List<TripWithScore> _queued = [];

  /// False until the first snapshot has been seen. That snapshot is the
  /// baseline: everything already scored in it is old news.
  bool _primed;

  Set<String> get shown => Set.unmodifiable(_shown);
  List<TripWithScore> get queued => List.unmodifiable(_queued);

  static bool isScored(TripWithScore r) =>
      r.trip.phase == TripPhase.scored.wire && (r.score?.scored ?? false);

  /// Feeds one snapshot of the recent trips. Returns the trips to celebrate
  /// now; empty while [recording], in which case they wait for [onParked].
  List<TripWithScore> onTrips(
    List<TripWithScore> rows, {
    required bool recording,
  }) {
    for (final r in rows) {
      if (!isScored(r)) continue;
      final id = r.trip.id;
      if (_shown.contains(id) || _queued.any((q) => q.trip.id == id)) continue;
      if (!_primed) {
        _shown.add(id);
        continue;
      }
      _queued.add(r);
    }
    _primed = true;
    return recording ? const [] : _take();
  }

  /// The car is parked: whatever was held back is due now.
  List<TripWithScore> onParked() => _take();

  List<TripWithScore> _take() {
    if (_queued.isEmpty) return const [];
    final out = List<TripWithScore>.of(_queued);
    _queued.clear();
    for (final r in out) {
      _shown.add(r.trip.id);
    }
    return out;
  }
}

/// Persists the shown ids in `Settings` so a trip never celebrates twice,
/// across restarts included.
class CelebratedTripsStore {
  CelebratedTripsStore(this.db);

  final AppDatabase db;
  static const key = 'celebrated_trips';

  /// Newest ids kept; older trips have long scrolled off the Drive tab.
  static const keep = 200;

  /// Null when this phone has never saved the set (first launch after the
  /// feature arrived): the caller then treats the first snapshot as baseline.
  Future<Set<String>?> load() async {
    final raw = await db.getSetting(key);
    if (raw == null) return null;
    try {
      return {for (final e in jsonDecode(raw) as List) e as String};
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Set<String> ids) {
    final list = ids.toList();
    final tail = list.length > keep ? list.sublist(list.length - keep) : list;
    return db.setSetting(key, jsonEncode(tail));
  }
}

final celebratedTripsStoreProvider = Provider<CelebratedTripsStore>(
  (ref) => CelebratedTripsStore(ref.watch(databaseProvider)),
);

/// Trips due for the moment, oldest first. The Drive tab's
/// [TripCelebrationHost] shows them one at a time and calls [dismiss].
class TripCelebrations extends Notifier<List<TripWithScore>> {
  CelebrationQueue? _queue;
  Future<void>? _ready;

  @override
  List<TripWithScore> build() {
    final store = ref.watch(celebratedTripsStoreProvider);
    _ready = store.load().then((ids) {
      _queue = CelebrationQueue(shown: ids ?? const {}, primed: ids != null);
    });
    ref.listen(recentTripsProvider, (_, next) {
      final rows = next.value;
      if (rows != null) unawaited(_onTrips(rows));
    }, fireImmediately: true);
    ref.listen(trackingControllerProvider.select((s) => s.live != null), (
      prev,
      recording,
    ) {
      if (prev == true && !recording) unawaited(_onParked());
    });
    return const [];
  }

  bool get _recording => ref.read(trackingControllerProvider).live != null;

  Future<void> _onTrips(List<TripWithScore> rows) async {
    await _ready;
    final q = _queue;
    if (q == null || !ref.mounted) return;
    final queuedBefore = q.queued.length;
    final due = q.onTrips(rows, recording: _recording);
    // A score that lands mid-drive still gets its buzz; the moment itself
    // waits until the car is parked (showCelebration buzzes on its own).
    if (due.isEmpty && q.queued.length > queuedBefore) Haptics.success();
    _emit(due, q);
  }

  Future<void> _onParked() async {
    await _ready;
    final q = _queue;
    if (q == null || !ref.mounted) return;
    _emit(q.onParked(), q);
  }

  void _emit(List<TripWithScore> due, CelebrationQueue q) {
    if (due.isNotEmpty) state = [...state, ...due];
    unawaited(
      ref
          .read(celebratedTripsStoreProvider)
          .save(q.shown)
          .catchError((Object e) => debugPrint('celebrations: $e')),
    );
  }

  void dismiss(String tripId) {
    state = [
      for (final r in state)
        if (r.trip.id != tripId) r,
    ];
  }
}

final tripCelebrationsProvider =
    NotifierProvider<TripCelebrations, List<TripWithScore>>(
      TripCelebrations.new,
    );

/// Whether the app is in the foreground; tests override to script it.
final appInForegroundProvider = Provider<bool Function()>((_) {
  return () {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  };
});

/// Shows the moment for each due trip while this widget is mounted and the
/// app is in the foreground. Wraps the Drive tab.
class TripCelebrationHost extends ConsumerStatefulWidget {
  const TripCelebrationHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TripCelebrationHost> createState() =>
      _TripCelebrationHostState();
}

class _TripCelebrationHostState extends ConsumerState<TripCelebrationHost>
    with WidgetsBindingObserver {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeShow();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tripCelebrationsProvider, (_, _) => _maybeShow());
    return widget.child;
  }

  Future<void> _maybeShow() async {
    if (_showing || !mounted) return;
    final pending = ref.read(tripCelebrationsProvider);
    if (pending.isEmpty) return;
    if (!ref.read(appInForegroundProvider)()) return;
    final r = pending.first;
    final scoreRow = r.score;
    if (scoreRow == null) {
      ref.read(tripCelebrationsProvider.notifier).dismiss(r.trip.id);
      return;
    }
    _showing = true;
    final score = TripScoreView.fromJsonString(scoreRow.scoreJson);
    final badges = await _newBadgeNames(scoreRow.scoredAt);
    if (!mounted) {
      _showing = false;
      return;
    }
    ref.read(tripCelebrationsProvider.notifier).dismiss(r.trip.id);
    try {
      await showCelebration(
        context,
        title: 'Trip scored',
        score: score.score,
        verdict: score.roastText,
        xp: score.xp,
        badges: badges,
        reckless: score.reckless,
        onShare: () {
          final units = resolveUnits(
            ref.read(unitsSettingProvider).value ?? UnitsSetting.auto,
            packRegion: r.trip.packRegion,
          );
          unawaited(shareTripFromApp(context, ref, r.trip, score, units));
        },
      );
    } finally {
      _showing = false;
    }
    if (mounted) unawaited(_maybeShow());
  }

  /// Badges awarded alongside this score, by name. Best effort: the badge
  /// engine runs on the same snapshot and may land a moment later.
  Future<List<String>> _newBadgeNames(int scoredAt) async {
    try {
      final awards = await ref.read(databaseProvider).allBadgeAwards();
      final fresh = [
        for (final a in awards)
          if (a.awardedAt >= scoredAt - 5000) a.badgeId,
      ];
      if (fresh.isEmpty) return const [];
      final defs = await ref
          .read(badgeDefsProvider.future)
          .timeout(const Duration(seconds: 1));
      return [
        for (final id in fresh)
          for (final d in defs)
            if (d.id == id) d.name,
      ];
    } catch (_) {
      return const [];
    }
  }
}
