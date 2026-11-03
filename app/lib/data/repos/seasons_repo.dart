import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../badges/badge_engine.dart';
import '../badges/badges_sync.dart';
import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'duels_repo.dart';
import 'leagues_repo.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// A quarter of play (docs/02 §12.3). Dates are calendar days in the
/// driver's local zone; [endsOn] is inclusive.
class Season {
  const Season({
    required this.id,
    required this.number,
    required this.name,
    required this.startsOn,
    required this.endsOn,
  });

  factory Season.fromJson(Map<String, dynamic> j) => Season(
    id: j['id'] as String,
    number: (j['number'] as num).toInt(),
    name: j['name'] as String? ?? 'Season ${j['number']}',
    startsOn: _date(j['starts_on'] as String),
    endsOn: _date(j['ends_on'] as String),
  );

  static DateTime _date(String s) {
    final p = s.split('-');
    return DateTime(
      int.parse(p[0]),
      int.parse(p[1]),
      int.parse(p[2].substring(0, 2)),
    );
  }

  static String _dateString(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  }

  final String id;
  final int number;
  final String name;
  final DateTime startsOn;
  final DateTime endsOn;

  /// First instant after the season (local midnight after [endsOn]).
  DateTime get endExclusive =>
      DateTime(endsOn.year, endsOn.month, endsOn.day + 1);

  bool contains(DateTime t) {
    final l = t.toLocal();
    return !l.isBefore(startsOn) && l.isBefore(endExclusive);
  }

  bool isOver(DateTime now) => !now.toLocal().isBefore(endExclusive);
  bool hasStarted(DateTime now) => !now.toLocal().isBefore(startsOn);

  /// Whole days until the season ends, counting today; 0 once over.
  int daysLeft(DateTime now) {
    final l = now.toLocal();
    if (isOver(l)) return 0;
    final today = DateTime(l.year, l.month, l.day);
    return endExclusive.difference(today).inDays;
  }

  /// Fraction of the season elapsed, 0..1.
  double progress(DateTime now) {
    final total = endExclusive.difference(startsOn).inMinutes;
    if (total <= 0) return 1;
    final done = now.toLocal().difference(startsOn).inMinutes;
    return (done / total).clamp(0, 1).toDouble();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'name': name,
    'starts_on': _dateString(startsOn),
    'ends_on': _dateString(endsOn),
  };
}

/// The seed in `0007_duels_challenges_seasons.sql`, so the card works before
/// the first cloud read and in offline builds. Keep in step.
final List<Season> builtInSeasons = List.unmodifiable([
  Season(
    id: '2026-q4',
    number: 1,
    name: 'Season 1',
    startsOn: DateTime(2026, 10, 1),
    endsOn: DateTime(2026, 12, 31),
  ),
  Season(
    id: '2027-q1',
    number: 2,
    name: 'Season 2',
    startsOn: DateTime(2027, 1, 1),
    endsOn: DateTime(2027, 3, 31),
  ),
  Season(
    id: '2027-q2',
    number: 3,
    name: 'Season 3',
    startsOn: DateTime(2027, 4, 1),
    endsOn: DateTime(2027, 6, 30),
  ),
  Season(
    id: '2027-q3',
    number: 4,
    name: 'Season 4',
    startsOn: DateTime(2027, 7, 1),
    endsOn: DateTime(2027, 9, 30),
  ),
  Season(
    id: '2027-q4',
    number: 5,
    name: 'Season 5',
    startsOn: DateTime(2027, 10, 1),
    endsOn: DateTime(2027, 12, 31),
  ),
]);

/// The season containing [t], if any (there are gaps before the first and
/// after the last seeded one).
Season? seasonFor(List<Season> seasons, DateTime t) {
  for (final s in seasons) {
    if (s.contains(t)) return s;
  }
  return null;
}

/// Counts and averages over a season's scored driver trips. Computed on the
/// phone from its own trips; the cloud only ever sees this summary.
class SeasonStats {
  const SeasonStats({
    required this.trips,
    required this.xp,
    required this.scoreAvg,
    required this.cleanTrips,
    required this.phoneFreeTrips,
    required this.bestScore,
  });

  static const none = SeasonStats(
    trips: 0,
    xp: 0,
    scoreAvg: null,
    cleanTrips: 0,
    phoneFreeTrips: 0,
    bestScore: null,
  );

  final int trips;
  final int xp;
  final double? scoreAvg;
  final int cleanTrips;
  final int phoneFreeTrips;
  final int? bestScore;

  Map<String, dynamic> toJson() => {
    'trips': trips,
    'xp': xp,
    'score_avg': scoreAvg,
    'clean_trips': cleanTrips,
    'phone_free_trips': phoneFreeTrips,
    'best_score': bestScore,
  };
}

SeasonStats computeSeasonStats(Season season, Iterable<ScoredTrip> trips) {
  var n = 0, xp = 0, clean = 0, phoneFree = 0, sum = 0;
  int? best;
  for (final t in trips) {
    if (!season.contains(
      DateTime.fromMillisecondsSinceEpoch(t.trip.startedAt),
    )) {
      continue;
    }
    n++;
    xp += t.score.xp;
    sum += t.score.score;
    if (t.clean) clean++;
    if (t.phoneFree) phoneFree++;
    if (best == null || t.score.score > best) best = t.score.score;
  }
  return SeasonStats(
    trips: n,
    xp: xp,
    scoreAvg: n == 0 ? null : (sum / n * 10).roundToDouble() / 10,
    cleanTrips: clean,
    phoneFreeTrips: phoneFree,
    bestScore: best,
  );
}

/// A `season_results` row.
class SeasonResult {
  const SeasonResult({
    required this.seasonId,
    required this.userId,
    required this.stats,
    this.bestTier,
    this.duelsWon = 0,
    this.duelsLost = 0,
  });

  factory SeasonResult.fromJson(Map<String, dynamic> j) => SeasonResult(
    seasonId: j['season_id'] as String,
    userId: j['user_id'] as String,
    stats: SeasonStats(
      trips: (j['trips'] as num?)?.toInt() ?? 0,
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      scoreAvg: (j['score_avg'] as num?)?.toDouble(),
      cleanTrips: (j['clean_trips'] as num?)?.toInt() ?? 0,
      phoneFreeTrips: (j['phone_free_trips'] as num?)?.toInt() ?? 0,
      bestScore: (j['best_score'] as num?)?.toInt(),
    ),
    bestTier: j['best_tier'] == null
        ? null
        : LeagueTier.fromWire(j['best_tier'] as String?),
    duelsWon: (j['duels_won'] as num?)?.toInt() ?? 0,
    duelsLost: (j['duels_lost'] as num?)?.toInt() ?? 0,
  );

  final String seasonId;
  final String userId;
  final SeasonStats stats;
  final LeagueTier? bestTier;
  final int duelsWon;
  final int duelsLost;

  Map<String, dynamic> toJson() => {
    'season_id': seasonId,
    'user_id': userId,
    ...stats.toJson(),
    'best_tier': bestTier?.wire,
    'duels_won': duelsWon,
    'duels_lost': duelsLost,
  };
}

// ---------------------------------------------------------------------------
// Remote API
// ---------------------------------------------------------------------------

abstract class SeasonsApi {
  Future<List<Season>> seasons();
  Future<List<SeasonResult>> myResults(String userId);
  Future<void> upsertResult(Map<String, dynamic> row);
}

class SupabaseSeasonsApi implements SeasonsApi {
  SupabaseSeasonsApi(this.client);
  final SupabaseClient client;

  @override
  Future<List<Season>> seasons() async {
    final rows = await client.from('seasons').select().order('number');
    return [for (final r in rows) Season.fromJson(r)];
  }

  @override
  Future<List<SeasonResult>> myResults(String userId) async {
    final rows = await client
        .from('season_results')
        .select()
        .eq('user_id', userId);
    return [for (final r in rows) SeasonResult.fromJson(r)];
  }

  @override
  Future<void> upsertResult(Map<String, dynamic> row) => client
      .from('season_results')
      .upsert(row, onConflict: 'season_id,user_id');
}

// ---------------------------------------------------------------------------
// Repo
// ---------------------------------------------------------------------------

/// Seasons: the calendar (cloud list, built-in fallback), this phone's
/// per-season stats, the one-time result upload when a season ends, and the
/// `season_1` badge.
class SeasonsRepo {
  SeasonsRepo({
    required this.db,
    required this.api,
    required this.outbox,
    required this.userId,
    this.awardBadge,
    this.bestTier,
    this.duelRecord,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _registerHandler();
  }

  final AppDatabase db;
  final SeasonsApi? api;
  final OutboxWorker outbox;
  final String? Function() userId;
  final Future<void> Function(String badgeId)? awardBadge;

  /// Highest league tier held right now, for the season row.
  final Future<LeagueTier?> Function()? bestTier;

  /// Duels won and lost inside a window, for the season row.
  final Future<(int, int)> Function(DateTime from, DateTime to)? duelRecord;
  final int Function() _now;

  static const kindResult = 'season_result';
  static const _listKey = 'seasons:list';
  static const _resultsKey = 'seasons:results';
  final ScoredTripParser _parser = ScoredTripParser();

  DateTime get _nowDt => DateTime.fromMillisecondsSinceEpoch(_now());

  void _registerHandler() {
    if (outbox.handles(kindResult)) return;
    outbox.register(kindResult, (p) async {
      final a = api;
      final uid = userId();
      if (a == null || uid == null) throw const OutboxRetryLater();
      if (p['user_id'] != uid) throw const OutboxSkip('another account');
      await a.upsertResult({
        'season_id': p['season_id'],
        'user_id': uid,
        'trips': p['trips'],
        'xp': p['xp'],
        'score_avg': p['score_avg'],
        'clean_trips': p['clean_trips'],
        'phone_free_trips': p['phone_free_trips'],
        'best_score': p['best_score'],
        'best_tier': p['best_tier'],
        'duels_won': p['duels_won'],
        'duels_lost': p['duels_lost'],
        'wrapped': p['wrapped'],
      });
    });
  }

  // ------------------------------------------------------------- calendar --

  /// Cloud list when reachable, else the last cached one, else built-in.
  Future<List<Season>> seasons({bool refresh = true}) async {
    final a = api;
    if (a != null && refresh) {
      try {
        final list = await a.seasons();
        if (list.isNotEmpty) {
          await db.cachePut(
            _listKey,
            jsonEncode([for (final s in list) s.toJson()]),
            _now(),
          );
          return list;
        }
      } catch (e) {
        debugPrint('seasons refresh failed: $e');
      }
    }
    final json = await db.cacheGet(_listKey);
    if (json != null) {
      return [
        for (final j in jsonDecode(json) as List)
          Season.fromJson(j as Map<String, dynamic>),
      ];
    }
    return builtInSeasons;
  }

  // ---------------------------------------------------------------- stats --

  Future<SeasonStats> stats(Season season) async => computeSeasonStats(
    season,
    _parser.parse(await db.scoredTripsWithScores()),
  );

  // ------------------------------------------------------------- results --

  Future<List<SeasonResult>> myResults({bool refresh = true}) async {
    final a = api;
    final uid = userId();
    if (a != null && uid != null && refresh) {
      try {
        final list = await a.myResults(uid);
        await db.cachePut(
          _resultsKey,
          jsonEncode([for (final r in list) r.toJson()]),
          _now(),
        );
        return list;
      } catch (e) {
        debugPrint('season results refresh failed: $e');
      }
    }
    final json = await db.cacheGet(_resultsKey);
    if (json == null) return const [];
    return [
      for (final j in jsonDecode(json) as List)
        SeasonResult.fromJson(j as Map<String, dynamic>),
    ];
  }

  static String uploadedKey(String seasonId, String uid) =>
      'season:$seasonId:uploaded:$uid';

  /// Uploads a result row once per ended season that has at least one
  /// scored trip on this phone, for the signed-in account, and awards
  /// `season_1` when the first season ends with a trip. A season with no
  /// trips (before the driver had the app) writes nothing and is remembered
  /// as empty. Returns the season ids queued this call. Safe to call on
  /// every open; cheap when nothing is due.
  Future<List<String>> uploadEndedSeasons({List<Season>? seasons}) async {
    final uid = userId();
    if (uid == null) return const [];
    final list = seasons ?? await this.seasons(refresh: false);
    final now = _nowDt;
    final queued = <String>[];
    List<ScoredTrip>? trips;
    for (final s in list) {
      if (!s.isOver(now)) continue;
      if (await db.getSetting(uploadedKey(s.id, uid)) != null) continue;
      trips ??= _parser.parse(await db.scoredTripsWithScores());
      final st = computeSeasonStats(s, trips);
      if (st.trips == 0) {
        // Nothing to report: the phone was not driving (or did not have the
        // app) that season. A past season cannot gain trips later, so the
        // parse is not repeated on every open.
        await db.setSetting(uploadedKey(s.id, uid), 'empty');
        continue;
      }
      final tier = await bestTier?.call();
      final (won, lost) =
          await duelRecord?.call(s.startsOn, s.endExclusive) ?? (0, 0);
      await outbox.enqueue(kindResult, {
        'season_id': s.id,
        'user_id': uid,
        ...st.toJson(),
        'best_tier': tier?.wire,
        'duels_won': won,
        'duels_lost': lost,
        'wrapped': {
          'headline': wrappedHeadline(s, st),
          'trips': st.trips,
          'xp': st.xp,
          'score_avg': st.scoreAvg,
          'best_score': st.bestScore,
        },
      }, id: 'season_result:${s.id}:$uid');
      await db.setSetting(uploadedKey(s.id, uid), '1');
      queued.add(s.id);
      if (s.number == 1 && st.trips > 0) await awardBadge?.call('season_1');
    }
    if (queued.isNotEmpty) outbox.scheduleDrain();
    return queued;
  }
}

/// One line for the Wrapped card and the season row. Never about speed.
String wrappedHeadline(Season season, SeasonStats s) {
  if (s.trips == 0) return '${season.name}: the car stayed parked.';
  final avg = s.scoreAvg;
  if (avg != null && avg >= 90) {
    return '${season.name}: ${s.trips} trips, averaging ${avg.toStringAsFixed(0)}. Chauffeur material.';
  }
  if (s.phoneFreeTrips == s.trips) {
    return '${season.name}: ${s.trips} trips and the phone stayed down every time.';
  }
  return '${season.name}: ${s.trips} trips, ${s.cleanTrips} of them clean.';
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final seasonsApiProvider = Provider<SeasonsApi?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : SupabaseSeasonsApi(client);
});

final seasonsRepoProvider = Provider<SeasonsRepo>((ref) {
  return SeasonsRepo(
    db: ref.watch(databaseProvider),
    api: ref.watch(seasonsApiProvider),
    outbox: ref.watch(outboxWorkerProvider),
    userId: () => ref.read(currentUserIdProvider),
    awardBadge: (id) async {
      await ref.read(badgesSyncProvider).engine.award(id);
    },
    bestTier: () async {
      final leagues = await ref.read(leaguesRepoProvider).cachedMyLeagues();
      LeagueTier? best;
      for (final l in leagues) {
        if (best == null || l.myTier.index > best.index) best = l.myTier;
      }
      return best;
    },
    duelRecord: (from, to) => ref.read(duelsRepoProvider).record(from, to),
  );
});

/// The season calendar (cloud, cache, or built-in).
final seasonsProvider = FutureProvider<List<Season>>(
  (ref) => ref.watch(seasonsRepoProvider).seasons(),
);

/// The season running now, from the best list available; null between
/// seasons.
final currentSeasonProvider = Provider<Season?>((ref) {
  final list = ref.watch(seasonsProvider).value ?? builtInSeasons;
  return seasonFor(list, DateTime.now());
});

/// This phone's stats for a season, live as trips are scored.
final seasonStatsProvider = StreamProvider.family<SeasonStats, String>((
  ref,
  seasonId,
) {
  final seasons = ref.watch(seasonsProvider).value ?? builtInSeasons;
  Season? season;
  for (final s in seasons) {
    if (s.id == seasonId) season = s;
  }
  if (season == null) return Stream.value(SeasonStats.none);
  final parser = ScoredTripParser();
  final s = season;
  return ref
      .watch(databaseProvider)
      .watchScoredTripsWithScores()
      .map((rows) => computeSeasonStats(s, parser.parse(rows)));
});

final mySeasonResultsProvider = FutureProvider<List<SeasonResult>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(seasonsRepoProvider).myResults();
});

/// Queues result rows for seasons that ended since the last check. Watched
/// by the seasons card so it runs on every open of the Leagues tab.
final seasonUploadProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(currentUserIdProvider);
  final repo = ref.watch(seasonsRepoProvider);
  final seasons = await ref.watch(seasonsProvider.future);
  return repo.uploadEndedSeasons(seasons: seasons);
});
