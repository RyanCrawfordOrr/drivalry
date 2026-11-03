import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// What a duel is fought on (docs/02 §7, §12.1). Never speed, never distance.
enum DuelMetric {
  xp('xp', 'XP', 'Most XP from scored trips wins.'),
  scoreAvg(
    'score_avg',
    'Drive Score',
    'Highest average Drive Score wins. Fewer than three trips forfeits.',
  ),
  phoneFree(
    'phone_free',
    'Phone-free trips',
    'Most scored trips without touching the phone wins.',
  );

  const DuelMetric(this.wire, this.label, this.description);
  final String wire;
  final String label;
  final String description;

  static DuelMetric fromWire(String? wire) =>
      values.firstWhere((m) => m.wire == wire, orElse: () => xp);

  /// `180 XP`, `87.5`, `4 trips`.
  String formatValue(double v) => switch (this) {
    xp => '${v.round()} XP',
    scoreAvg => v.toStringAsFixed(1),
    phoneFree => '${v.round()} trip${v.round() == 1 ? '' : 's'}',
  };
}

enum DuelStatus {
  pending('pending'),
  active('active'),
  declined('declined'),
  finished('finished'),
  expired('expired');

  const DuelStatus(this.wire);
  final String wire;

  static DuelStatus fromWire(String? wire) =>
      values.firstWhere((s) => s.wire == wire, orElse: () => pending);
}

/// The profile bits a duel card shows for one side.
class DuelParty {
  const DuelParty({
    required this.userId,
    required this.handle,
    required this.displayName,
    this.avatarUrl,
  });

  factory DuelParty.fromJson(Map<String, dynamic> j) => DuelParty(
    userId: j['user_id'] as String,
    handle: j['handle'] as String? ?? 'driver',
    displayName: j['display_name'] as String? ?? '',
    avatarUrl: j['avatar_url'] as String?,
  );

  final String userId;
  final String handle;
  final String displayName;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'handle': handle,
    'display_name': displayName,
    'avatar_url': avatarUrl,
  };
}

class Duel {
  const Duel({
    required this.id,
    required this.challenger,
    required this.opponent,
    required this.metric,
    required this.status,
    required this.createdAt,
    this.startsAt,
    this.endsAt,
    this.finishedAt,
    this.challengerValue,
    this.opponentValue,
    this.challengerTrips,
    this.opponentTrips,
    this.winnerId,
    this.loserBadgeId,
  });

  /// Reads both the cache shape (`challenger`/`opponent` objects with
  /// `user_id`) and the PostgREST row with embedded profiles.
  factory Duel.fromJson(Map<String, dynamic> j) {
    DuelParty party(String idKey, String objKey) {
      final raw = j[objKey];
      final obj = raw is Map<String, dynamic> ? raw : const <String, dynamic>{};
      return DuelParty.fromJson({
        ...obj,
        'user_id': obj['user_id'] ?? obj['id'] ?? j[idKey],
      });
    }

    DateTime? ts(String key) =>
        j[key] == null ? null : DateTime.tryParse(j[key] as String)?.toLocal();
    return Duel(
      id: j['id'] as String,
      challenger: party('challenger_id', 'challenger'),
      opponent: party('opponent_id', 'opponent'),
      metric: DuelMetric.fromWire(j['metric'] as String?),
      status: DuelStatus.fromWire(j['status'] as String?),
      createdAt: ts('created_at') ?? DateTime.fromMillisecondsSinceEpoch(0),
      startsAt: ts('starts_at'),
      endsAt: ts('ends_at'),
      finishedAt: ts('finished_at'),
      challengerValue: (j['challenger_value'] as num?)?.toDouble(),
      opponentValue: (j['opponent_value'] as num?)?.toDouble(),
      challengerTrips: (j['challenger_trips'] as num?)?.toInt(),
      opponentTrips: (j['opponent_trips'] as num?)?.toInt(),
      winnerId: j['winner_id'] as String?,
      loserBadgeId: j['loser_badge_id'] as String?,
    );
  }

  final String id;
  final DuelParty challenger;
  final DuelParty opponent;
  final DuelMetric metric;
  final DuelStatus status;
  final DateTime createdAt;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? finishedAt;
  final double? challengerValue;
  final double? opponentValue;
  final int? challengerTrips;
  final int? opponentTrips;

  /// Null while running, and for a draw.
  final String? winnerId;
  final String? loserBadgeId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'challenger_id': challenger.userId,
    'opponent_id': opponent.userId,
    'challenger': challenger.toJson(),
    'opponent': opponent.toJson(),
    'metric': metric.wire,
    'status': status.wire,
    'created_at': createdAt.toUtc().toIso8601String(),
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'finished_at': finishedAt?.toUtc().toIso8601String(),
    'challenger_value': challengerValue,
    'opponent_value': opponentValue,
    'challenger_trips': challengerTrips,
    'opponent_trips': opponentTrips,
    'winner_id': winnerId,
    'loser_badge_id': loserBadgeId,
  };

  Duel copyWith({
    DuelStatus? status,
    DateTime? startsAt,
    DateTime? endsAt,
    DateTime? finishedAt,
    double? challengerValue,
    double? opponentValue,
    String? winnerId,
    String? loserBadgeId,
  }) => Duel(
    id: id,
    challenger: challenger,
    opponent: opponent,
    metric: metric,
    status: status ?? this.status,
    createdAt: createdAt,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    finishedAt: finishedAt ?? this.finishedAt,
    challengerValue: challengerValue ?? this.challengerValue,
    opponentValue: opponentValue ?? this.opponentValue,
    challengerTrips: challengerTrips,
    opponentTrips: opponentTrips,
    winnerId: winnerId ?? this.winnerId,
    loserBadgeId: loserBadgeId ?? this.loserBadgeId,
  );

  bool involves(String userId) =>
      challenger.userId == userId || opponent.userId == userId;
  bool isChallenger(String userId) => challenger.userId == userId;

  /// The other side, from [userId]'s point of view.
  DuelParty other(String userId) =>
      challenger.userId == userId ? opponent : challenger;

  bool get isPending => status == DuelStatus.pending;
  bool get isActive => status == DuelStatus.active;
  bool get isFinished => status == DuelStatus.finished;
  bool get isDraw => isFinished && winnerId == null;

  String? get loserId => winnerId == null
      ? null
      : (winnerId == challenger.userId ? opponent.userId : challenger.userId);

  /// Running and past its end: the cloud can settle it.
  bool isDue(DateTime now) =>
      isActive && endsAt != null && !endsAt!.isAfter(now);
}

// ---------------------------------------------------------------------------
// Scoring (pure). Mirrors `duel_value` in 0007_duels_challenges_seasons.sql.
// ---------------------------------------------------------------------------

/// The per-trip facts a duel needs, from one `trip_summaries` row.
class DuelTrip {
  const DuelTrip({
    required this.userId,
    required this.xp,
    required this.score,
    required this.phoneHandling,
  });
  final String userId;
  final int xp;
  final int score;
  final bool phoneHandling;
}

class DuelValue {
  const DuelValue({required this.value, required this.trips});
  final double value;
  final int trips;
}

/// Minimum scored trips before an average Drive Score counts.
const int duelScoreAvgMinTrips = 3;

/// One driver's standing: XP sum, average score (forfeited under three
/// trips), or phone-free trip count. [trips] are that driver's scored driver
/// trips inside the duel window.
DuelValue duelValue(DuelMetric metric, Iterable<DuelTrip> trips) {
  final list = trips.toList();
  switch (metric) {
    case DuelMetric.xp:
      return DuelValue(
        value: list.fold<int>(0, (s, t) => s + t.xp).toDouble(),
        trips: list.length,
      );
    case DuelMetric.scoreAvg:
      if (list.length < duelScoreAvgMinTrips) {
        return DuelValue(value: 0, trips: list.length);
      }
      final sum = list.fold<int>(0, (s, t) => s + t.score);
      final avg = sum / list.length;
      return DuelValue(
        value: (avg * 100).roundToDouble() / 100,
        trips: list.length,
      );
    case DuelMetric.phoneFree:
      return DuelValue(
        value: list.where((t) => !t.phoneHandling).length.toDouble(),
        trips: list.length,
      );
  }
}

class DuelScoreboard {
  const DuelScoreboard({required this.challenger, required this.opponent});
  final DuelValue challenger;
  final DuelValue opponent;

  /// Who is ahead right now; null for a tie.
  String? leaderId(Duel duel) {
    if (challenger.value > opponent.value) return duel.challenger.userId;
    if (opponent.value > challenger.value) return duel.opponent.userId;
    return null;
  }

  DuelValue valueFor(Duel duel, String userId) =>
      duel.challenger.userId == userId ? challenger : opponent;
}

/// Scores both sides of [duel] from the trips of both drivers.
DuelScoreboard scoreDuel(Duel duel, Iterable<DuelTrip> trips) {
  final list = trips.toList();
  return DuelScoreboard(
    challenger: duelValue(
      duel.metric,
      list.where((t) => t.userId == duel.challenger.userId),
    ),
    opponent: duelValue(
      duel.metric,
      list.where((t) => t.userId == duel.opponent.userId),
    ),
  );
}

/// The fixed list the winner picks the loser's seven-day badge from.
const List<String> duelLoserBadges = [
  'sunday_driver',
  'lead_foot',
  'butterfingers',
];

String duelBadgeName(String id) => switch (id) {
  'sunday_driver' => 'Sunday Driver',
  'lead_foot' => 'Lead Foot',
  'butterfingers' => 'Butterfingers',
  _ => id,
};

/// Unanswered challenges lapse after a week (`finalize_due_duels`).
const Duration duelInviteLifetime = Duration(days: 7);
const Duration duelLength = Duration(days: 7);

// ---------------------------------------------------------------------------
// Remote API
// ---------------------------------------------------------------------------

class DuelException implements Exception {
  const DuelException(this.message);
  final String message;
  @override
  String toString() => 'DuelException($message)';
}

/// Everything the repo asks the cloud for. Faked in tests.
abstract class DuelsApi {
  Future<List<Duel>> myDuels(String userId);
  Future<void> create({
    required String id,
    required String challengerId,
    required String opponentId,
    required DuelMetric metric,
  });

  /// `respond_duel`; returns the resulting status wire value.
  Future<String> respond(String duelId, bool accept);

  /// `finalize_duel`; returns its json.
  Future<Map<String, dynamic>> finalize(String duelId);
  Future<void> pickBadge(String duelId, String badgeId);
  Future<void> cancel(String duelId);
  Future<List<DuelTrip>> trips(
    List<String> userIds,
    DateTime from,
    DateTime to,
  );
}

class SupabaseDuelsApi implements DuelsApi {
  SupabaseDuelsApi(this.client);
  final SupabaseClient client;

  String? _avatarUrl(String? path) => path == null || path.isEmpty
      ? null
      : client.storage.from('avatars').getPublicUrl(path);

  Map<String, dynamic> _party(Map<String, dynamic> row, String key) {
    final p = row[key] as Map<String, dynamic>? ?? const {};
    return {
      'user_id': p['id'] ?? row['${key}_id'],
      'handle': p['handle'],
      'display_name': p['display_name'],
      'avatar_url': _avatarUrl(p['avatar_path'] as String?),
    };
  }

  @override
  Future<List<Duel>> myDuels(String userId) async {
    final rows = await client
        .from('duels')
        .select(
          '*, challenger:profiles!duels_challenger_id_fkey(id, handle, '
          'display_name, avatar_path), opponent:profiles!duels_opponent_id_fkey'
          '(id, handle, display_name, avatar_path)',
        )
        .or('challenger_id.eq.$userId,opponent_id.eq.$userId')
        .order('created_at', ascending: false)
        .limit(60);
    return [
      for (final r in rows)
        Duel.fromJson({
          ...r,
          'challenger': _party(r, 'challenger'),
          'opponent': _party(r, 'opponent'),
        }),
    ];
  }

  @override
  Future<void> create({
    required String id,
    required String challengerId,
    required String opponentId,
    required DuelMetric metric,
  }) => client
      .from('duels')
      .upsert(
        {
          'id': id,
          'challenger_id': challengerId,
          'opponent_id': opponentId,
          'metric': metric.wire,
        },
        onConflict: 'id',
        ignoreDuplicates: true,
      );

  @override
  Future<String> respond(String duelId, bool accept) async {
    final r = await client.rpc(
      'respond_duel',
      params: {'p_duel_id': duelId, 'p_accept': accept},
    );
    return r as String;
  }

  @override
  Future<Map<String, dynamic>> finalize(String duelId) async {
    final r = await client.rpc('finalize_duel', params: {'p_duel_id': duelId});
    return r is Map<String, dynamic> ? r : const {};
  }

  @override
  Future<void> pickBadge(String duelId, String badgeId) => client.rpc(
    'pick_duel_badge',
    params: {'p_duel_id': duelId, 'p_badge_id': badgeId},
  );

  @override
  Future<void> cancel(String duelId) =>
      client.from('duels').delete().eq('id', duelId).eq('status', 'pending');

  @override
  Future<List<DuelTrip>> trips(
    List<String> userIds,
    DateTime from,
    DateTime to,
  ) async {
    if (userIds.isEmpty) return const [];
    // The embedded filter keeps every trip and only lists its phone events,
    // so a non-empty `trip_events` means the phone was handled.
    final rows = await client
        .from('trip_summaries')
        .select('user_id, xp, score, trip_events(kind)')
        .inFilter('user_id', userIds)
        .eq('scored', true)
        .eq('is_passenger', false)
        .eq('trip_events.kind', 'phone_handling')
        .gte('started_at', from.toUtc().toIso8601String())
        .lt('started_at', to.toUtc().toIso8601String());
    return [
      for (final r in rows)
        DuelTrip(
          userId: r['user_id'] as String,
          xp: (r['xp'] as num?)?.toInt() ?? 0,
          score: (r['score'] as num?)?.toInt() ?? 0,
          phoneHandling: ((r['trip_events'] as List?) ?? const []).isNotEmpty,
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Repo: cache-first reads, outbox writes
// ---------------------------------------------------------------------------

/// Duels for the signed-in user. The list is cached in `RemoteCache` so the
/// screen renders offline; creating and answering go through the outbox.
class DuelsRepo {
  DuelsRepo({
    required this.db,
    required this.api,
    required this.outbox,
    required this.userId,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _registerHandlers();
  }

  final AppDatabase db;
  final DuelsApi? api;
  final OutboxWorker outbox;
  final String? Function() userId;
  final int Function() _now;

  static const kindCreate = 'duel_create';
  static const kindRespond = 'duel_respond';
  static const _uuid = Uuid();
  static const _mineKey = 'duels:mine';

  DateTime get _nowDt => DateTime.fromMillisecondsSinceEpoch(_now());

  void _registerHandlers() {
    if (outbox.handles(kindCreate)) return;
    outbox.register(kindCreate, (p) async {
      final a = api;
      final uid = userId();
      if (a == null || uid == null) throw const OutboxRetryLater();
      if (p['challenger_id'] != uid) throw const OutboxSkip('another account');
      await a.create(
        id: p['id'] as String,
        challengerId: uid,
        opponentId: p['opponent_id'] as String,
        metric: DuelMetric.fromWire(p['metric'] as String?),
      );
    });
    outbox.register(kindRespond, (p) async {
      final a = api;
      final uid = userId();
      if (a == null || uid == null) throw const OutboxRetryLater();
      if (p['user_id'] != uid) throw const OutboxSkip('another account');
      try {
        await a.respond(p['duel_id'] as String, p['accept'] as bool);
      } on PostgrestException catch (e) {
        // Gone, not ours, or answered differently already: nothing a retry
        // would change. The next refresh shows the truth.
        if (const {'P0004', 'P0005', 'P0006'}.contains(e.code)) {
          debugPrint('duel_respond dropped: ${e.code} ${e.message}');
          return;
        }
        rethrow;
      }
    });
  }

  String _requireUser() {
    final uid = userId();
    if (uid == null) throw const DuelException('Sign in first.');
    return uid;
  }

  // ------------------------------------------------------------ my duels --

  Future<List<Duel>> cachedMyDuels() async {
    final json = await db.cacheGet(_mineKey);
    return json == null ? const [] : _decode(json);
  }

  Stream<List<Duel>> watchMyDuels() => db
      .watchCache(_mineKey)
      .map((json) => json == null ? const <Duel>[] : _decode(json));

  List<Duel> _decode(String json) => [
    for (final j in jsonDecode(json) as List)
      Duel.fromJson(j as Map<String, dynamic>),
  ];

  Future<void> _store(List<Duel> duels) => db.cachePut(
    _mineKey,
    jsonEncode([for (final d in duels) d.toJson()]),
    _now(),
  );

  /// Cloud first. Any running duel whose week is over is settled on the way
  /// (`finalize_duel` is idempotent; the daily cron is the backstop). Falls
  /// back to the cache and rethrows so the screen can say "last known".
  Future<List<Duel>> refreshMyDuels() async {
    final a = api;
    final uid = userId();
    if (a == null || uid == null) return cachedMyDuels();
    var duels = await a.myDuels(uid);
    var settled = false;
    for (final d in duels.where((d) => d.isDue(_nowDt))) {
      try {
        await a.finalize(d.id);
        settled = true;
      } catch (e) {
        debugPrint('finalize_duel(${d.id}): $e');
      }
    }
    if (settled) duels = await a.myDuels(uid);
    duels = await _withQueuedCreates(duels);
    await _store(duels);
    return duels;
  }

  /// Keeps the optimistic rows of challenges the outbox has not delivered
  /// yet: the server list cannot have them, and dropping them would make the
  /// duel vanish (and invite a second tap, hence a second duel) while the
  /// create keeps retrying.
  Future<List<Duel>> _withQueuedCreates(List<Duel> fromServer) async {
    final queued = <String>{};
    for (final row in await db.outboxOfKind(kindCreate)) {
      final id = (jsonDecode(row.payload) as Map<String, dynamic>)['id'];
      if (id is String) queued.add(id);
    }
    if (queued.isEmpty) return fromServer;
    final serverIds = {for (final d in fromServer) d.id};
    final cached = await cachedMyDuels();
    return [
      for (final d in cached)
        if (queued.contains(d.id) && !serverIds.contains(d.id)) d,
      ...fromServer,
    ];
  }

  /// Challenges a friend. The row lands through the outbox; the cache gets
  /// a pending entry at once so the list shows it offline.
  Future<Duel> challenge({
    required DuelParty opponent,
    required DuelMetric metric,
    DuelParty? me,
  }) async {
    final uid = _requireUser();
    if (opponent.userId == uid) {
      throw const DuelException('You cannot duel yourself.');
    }
    final current = await cachedMyDuels();
    final open = current.where(
      (d) =>
          (d.isPending || d.isActive) &&
          d.involves(uid) &&
          d.involves(opponent.userId),
    );
    if (open.isNotEmpty) {
      throw DuelException(
        'You already have a duel going with @${opponent.handle}.',
      );
    }
    final id = _uuid.v4();
    final duel = Duel(
      id: id,
      challenger: me ?? DuelParty(userId: uid, handle: 'you', displayName: ''),
      opponent: opponent,
      metric: metric,
      status: DuelStatus.pending,
      createdAt: _nowDt,
    );
    await _store([duel, ...current]);
    await outbox.enqueue(kindCreate, {
      'id': id,
      'challenger_id': uid,
      'opponent_id': opponent.userId,
      'metric': metric.wire,
    }, id: 'duel_create:$id');
    await outbox.drain();
    try {
      final fresh = await refreshMyDuels();
      return fresh.firstWhere((d) => d.id == id, orElse: () => duel);
    } catch (e) {
      debugPrint('challenge: refresh failed, using cache: $e');
      return duel;
    }
  }

  /// Accept or decline. Optimistic: the cache flips now, the RPC follows.
  Future<void> respond(String duelId, {required bool accept}) async {
    final uid = _requireUser();
    final current = await cachedMyDuels();
    final now = _nowDt;
    await _store([
      for (final d in current)
        if (d.id == duelId && d.isPending)
          d.copyWith(
            status: accept ? DuelStatus.active : DuelStatus.declined,
            startsAt: accept ? now : null,
            endsAt: accept ? now.add(duelLength) : null,
          )
        else
          d,
    ]);
    await outbox.enqueue(kindRespond, {
      'duel_id': duelId,
      'user_id': uid,
      'accept': accept,
    }, id: 'duel_respond:$duelId');
    await outbox.drain();
  }

  /// Withdraws an unanswered challenge of mine.
  Future<void> cancel(String duelId) async {
    _requireUser();
    await api?.cancel(duelId);
    await _store([
      for (final d in await cachedMyDuels())
        if (d.id != duelId) d,
    ]);
  }

  /// The winner's pick for the loser's seven-day badge.
  Future<void> pickBadge(String duelId, String badgeId) async {
    _requireUser();
    final a = api;
    if (a == null) throw const DuelException('Could not reach Drivalry.');
    if (!duelLoserBadges.contains(badgeId)) {
      throw const DuelException('Not one of the duel badges.');
    }
    try {
      await a.pickBadge(duelId, badgeId);
    } on PostgrestException catch (e) {
      throw DuelException(e.message);
    }
    await _store([
      for (final d in await cachedMyDuels())
        if (d.id == duelId) d.copyWith(loserBadgeId: badgeId) else d,
    ]);
  }

  // ----------------------------------------------------------- scoreboard --

  String _boardKey(String id) => 'duel:$id:board';

  /// Where a running duel stands, from both drivers' summaries so far. A
  /// finished duel reports the stored result. Cached per duel for offline.
  Future<DuelScoreboard> scoreboard(Duel duel) async {
    if (duel.isFinished) {
      return DuelScoreboard(
        challenger: DuelValue(
          value: duel.challengerValue ?? 0,
          trips: duel.challengerTrips ?? 0,
        ),
        opponent: DuelValue(
          value: duel.opponentValue ?? 0,
          trips: duel.opponentTrips ?? 0,
        ),
      );
    }
    final a = api;
    final start = duel.startsAt;
    if (a != null && start != null) {
      try {
        final end = duel.endsAt ?? start.add(duelLength);
        final trips = await a.trips(
          [duel.challenger.userId, duel.opponent.userId],
          start,
          end.isBefore(_nowDt) ? end : _nowDt,
        );
        final board = scoreDuel(duel, trips);
        await db.cachePut(
          _boardKey(duel.id),
          jsonEncode({
            'c': board.challenger.value,
            'ct': board.challenger.trips,
            'o': board.opponent.value,
            'ot': board.opponent.trips,
          }),
          _now(),
        );
        return board;
      } catch (e) {
        debugPrint('duel scoreboard refresh failed: $e');
      }
    }
    final cached = await db.cacheGet(_boardKey(duel.id));
    if (cached == null) {
      return const DuelScoreboard(
        challenger: DuelValue(value: 0, trips: 0),
        opponent: DuelValue(value: 0, trips: 0),
      );
    }
    final j = jsonDecode(cached) as Map<String, dynamic>;
    return DuelScoreboard(
      challenger: DuelValue(
        value: (j['c'] as num).toDouble(),
        trips: (j['ct'] as num).toInt(),
      ),
      opponent: DuelValue(
        value: (j['o'] as num).toDouble(),
        trips: (j['ot'] as num).toInt(),
      ),
    );
  }

  /// Won/lost counts for duels finished inside a window (season results).
  Future<(int won, int lost)> record(DateTime from, DateTime to) async {
    final uid = userId();
    if (uid == null) return (0, 0);
    var won = 0, lost = 0;
    for (final d in await cachedMyDuels()) {
      final at = d.finishedAt;
      if (!d.isFinished ||
          at == null ||
          at.isBefore(from) ||
          !at.isBefore(to)) {
        continue;
      }
      if (d.winnerId == uid) won++;
      if (d.loserId == uid) lost++;
    }
    return (won, lost);
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final duelsApiProvider = Provider<DuelsApi?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : SupabaseDuelsApi(client);
});

final duelsRepoProvider = Provider<DuelsRepo>((ref) {
  return DuelsRepo(
    db: ref.watch(databaseProvider),
    api: ref.watch(duelsApiProvider),
    outbox: ref.watch(outboxWorkerProvider),
    userId: () => ref.read(currentUserIdProvider),
  );
});

/// Cached snapshot, live.
final myDuelsProvider = StreamProvider<List<Duel>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(duelsRepoProvider).watchMyDuels();
});

/// Fires a cloud refresh when first watched and whenever invalidated.
final refreshMyDuelsProvider = FutureProvider<List<Duel>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(duelsRepoProvider).refreshMyDuels();
});

/// Pulls the duel list from the cloud once per sign-in (and at app start
/// with a session), so an incoming challenge reaches the Leagues-tab badge
/// before the user ever opens Duels. Kept alive by the sync bootstrap; the
/// push handler and the Duels screen refresh on top of it.
final duelsSignInRefreshProvider = Provider<void>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return;
  final repo = ref.read(duelsRepoProvider);
  unawaited(
    Future<void>.microtask(() async {
      try {
        await repo.refreshMyDuels();
      } catch (e) {
        debugPrint('duel refresh after sign-in: $e');
      }
    }),
  );
});

/// Challenges waiting for my answer (badge on the Leagues tab action).
final pendingDuelCountProvider = Provider<int>((ref) {
  final me = ref.watch(currentUserIdProvider);
  if (me == null) return 0;
  ref.watch(duelsSignInRefreshProvider);
  final duels = ref.watch(myDuelsProvider).value ?? const <Duel>[];
  return duels.where((d) => d.isPending && d.opponent.userId == me).length;
});

/// Live scoreboard for one duel, by id.
final duelScoreboardProvider = FutureProvider.family<DuelScoreboard?, String>((
  ref,
  id,
) async {
  final repo = ref.watch(duelsRepoProvider);
  final duels = ref.watch(myDuelsProvider).value ?? await repo.cachedMyDuels();
  Duel? duel;
  for (final d in duels) {
    if (d.id == id) duel = d;
  }
  if (duel == null) return null;
  return repo.scoreboard(duel);
});
