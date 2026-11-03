import 'dart:convert';
import 'dart:math' as math;

import 'package:drivalry_scoring/drivalry_scoring.dart' show Xp;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../badges/badges_sync.dart';
import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'leagues_repo.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// A league-wide goal for a week or two (docs/02 §12.2). Every goal counts
/// clean driving or showing up; none counts speed or distance.
enum ChallengeGoal {
  cleanTrips(
    'clean_trips',
    'Clean trips',
    'Trips scored 80 or better and not reckless, league total.',
    defaultTarget: 25,
    unit: 'trips',
  ),
  phoneFree(
    'phone_free',
    'Phone-free trips',
    'Trips without touching the phone, league total.',
    defaultTarget: 25,
    unit: 'trips',
  ),
  scoreAvg(
    'score_avg',
    'Average score',
    'Average Drive Score across every member trip.',
    defaultTarget: 85,
    unit: 'points',
  ),
  everyoneDrives(
    'everyone_drives',
    'Everyone drives',
    'Every member logs at least this many scored trips.',
    defaultTarget: 3,
    unit: 'trips each',
  );

  const ChallengeGoal(
    this.wire,
    this.label,
    this.description, {
    required this.defaultTarget,
    required this.unit,
  });
  final String wire;
  final String label;
  final String description;
  final int defaultTarget;
  final String unit;

  static ChallengeGoal fromWire(String? wire) =>
      values.firstWhere((g) => g.wire == wire, orElse: () => cleanTrips);

  /// The badge every member earns when the goal is met (seeded in 0007).
  String get badgeId => 'challenge_$wire';

  String get badgeName => switch (this) {
    cleanTrips => 'Clean Sweep',
    phoneFree => 'Hands Off, Together',
    scoreAvg => 'Class Act',
    everyoneDrives => 'Full House',
  };
}

/// One member's share of a challenge, as stored in `per_member`.
class ChallengeMemberProgress {
  const ChallengeMemberProgress({
    required this.userId,
    required this.trips,
    required this.clean,
    required this.phoneFree,
    this.scoreAvg,
  });

  factory ChallengeMemberProgress.fromJson(Map<String, dynamic> j) =>
      ChallengeMemberProgress(
        userId: j['user_id'] as String,
        trips: (j['trips'] as num?)?.toInt() ?? 0,
        clean: (j['clean'] as num?)?.toInt() ?? 0,
        phoneFree: (j['phone_free'] as num?)?.toInt() ?? 0,
        scoreAvg: (j['score_avg'] as num?)?.toDouble(),
      );

  final String userId;
  final int trips;
  final int clean;
  final int phoneFree;
  final double? scoreAvg;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'trips': trips,
    'clean': clean,
    'phone_free': phoneFree,
    'score_avg': scoreAvg,
  };
}

class GroupChallenge {
  const GroupChallenge({
    required this.id,
    required this.leagueId,
    required this.createdBy,
    required this.goal,
    required this.target,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.value,
    this.perMember = const [],
    this.finalizedAt,
  });

  factory GroupChallenge.fromJson(Map<String, dynamic> j) => GroupChallenge(
    id: j['id'] as String,
    leagueId: j['league_id'] as String,
    createdBy: j['created_by'] as String? ?? '',
    goal: ChallengeGoal.fromWire(j['goal'] as String?),
    target: (j['target'] as num?)?.toInt() ?? 1,
    startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
    endsAt: DateTime.parse(j['ends_at'] as String).toLocal(),
    status: j['status'] as String? ?? 'active',
    value: (j['value'] as num?)?.toDouble(),
    perMember: [
      for (final m in (j['per_member'] as List?) ?? const [])
        if (m is Map<String, dynamic>) ChallengeMemberProgress.fromJson(m),
    ],
    finalizedAt: j['finalized_at'] == null
        ? null
        : DateTime.tryParse(j['finalized_at'] as String)?.toLocal(),
  );

  final String id;
  final String leagueId;
  final String createdBy;
  final ChallengeGoal goal;

  /// Trips, points, or trips per member for `everyone_drives`.
  final int target;
  final DateTime startsAt;
  final DateTime endsAt;

  /// active | succeeded | failed
  final String status;
  final double? value;
  final List<ChallengeMemberProgress> perMember;
  final DateTime? finalizedAt;

  bool get isActive => status == 'active';
  bool get succeeded => status == 'succeeded';
  bool get failed => status == 'failed';

  /// Still marked active but past its end: the cloud can settle it.
  bool isDue(DateTime now) => isActive && !endsAt.isAfter(now);

  Map<String, dynamic> toJson() => {
    'id': id,
    'league_id': leagueId,
    'created_by': createdBy,
    'goal': goal.wire,
    'target': target,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'ends_at': endsAt.toUtc().toIso8601String(),
    'status': status,
    'value': value,
    'per_member': [for (final m in perMember) m.toJson()],
    'finalized_at': finalizedAt?.toUtc().toIso8601String(),
  };

  /// `Clean trips · 25 trips`, `Everyone drives · 3 trips each`.
  String get title => '${goal.label} · $target ${goal.unit}';
}

// ---------------------------------------------------------------------------
// Progress (pure). Mirrors `challenge_progress` in the 0007 migration.
// ---------------------------------------------------------------------------

/// The per-trip facts a challenge needs, from one `trip_summaries` row.
class ChallengeTrip {
  const ChallengeTrip({
    required this.userId,
    required this.score,
    required this.reckless,
    required this.phoneHandling,
  });
  final String userId;
  final int score;
  final bool reckless;
  final bool phoneHandling;

  bool get clean => score >= challengeCleanScore && !reckless;
}

/// A trip counts as clean from this Drive Score: the same line the XP
/// rules and streaks use (`Xp.cleanTripScore`, docs/02 §5 and §12.2).
const int challengeCleanScore = Xp.cleanTripScore ~/ 1;

class ChallengeProgress {
  const ChallengeProgress({
    required this.value,
    required this.needed,
    required this.target,
    required this.members,
    required this.met,
    required this.perMember,
  });

  /// League total (or members who hit the per-member target).
  final double value;

  /// What [value] has to reach: the target, or the member count for
  /// `everyone_drives`.
  final int needed;
  final int target;
  final int members;
  final bool met;
  final List<ChallengeMemberProgress> perMember;

  double get fraction => needed <= 0 ? 0 : math.min(1, value / needed);
}

/// Where [challenge] stands over [memberIds], from the members' scored
/// driver trips inside the window. Trips from non-members are ignored.
ChallengeProgress computeChallengeProgress(
  GroupChallenge challenge,
  List<String> memberIds,
  Iterable<ChallengeTrip> trips,
) {
  final ids = memberIds.toSet();
  final byMember = <String, List<ChallengeTrip>>{
    for (final id in memberIds) id: [],
  };
  for (final t in trips) {
    if (ids.contains(t.userId)) byMember[t.userId]!.add(t);
  }
  final per = <ChallengeMemberProgress>[];
  var totalTrips = 0, totalClean = 0, totalPhoneFree = 0, scoreSum = 0;
  var membersMeeting = 0;
  for (final id in memberIds.toList()..sort()) {
    final mine = byMember[id]!;
    final clean = mine.where((t) => t.clean).length;
    final phoneFree = mine.where((t) => !t.phoneHandling).length;
    final sum = mine.fold<int>(0, (s, t) => s + t.score);
    totalTrips += mine.length;
    totalClean += clean;
    totalPhoneFree += phoneFree;
    scoreSum += sum;
    if (mine.length >= challenge.target) membersMeeting++;
    per.add(
      ChallengeMemberProgress(
        userId: id,
        trips: mine.length,
        clean: clean,
        phoneFree: phoneFree,
        scoreAvg: mine.isEmpty
            ? null
            : (sum / mine.length * 10).roundToDouble() / 10,
      ),
    );
  }
  final members = memberIds.length;
  final value = switch (challenge.goal) {
    ChallengeGoal.cleanTrips => totalClean.toDouble(),
    ChallengeGoal.phoneFree => totalPhoneFree.toDouble(),
    ChallengeGoal.scoreAvg =>
      totalTrips == 0
          ? 0.0
          : (scoreSum / totalTrips * 100).roundToDouble() / 100,
    ChallengeGoal.everyoneDrives => membersMeeting.toDouble(),
  };
  final everyone = challenge.goal == ChallengeGoal.everyoneDrives;
  return ChallengeProgress(
    value: value,
    needed: everyone ? members : challenge.target,
    target: challenge.target,
    members: members,
    met: everyone ? members > 0 && value >= members : value >= challenge.target,
    perMember: per,
  );
}

/// Challenge lengths offered by the sheet.
const List<int> challengeDurationsDays = [7, 14];

// ---------------------------------------------------------------------------
// Remote API
// ---------------------------------------------------------------------------

class ChallengeException implements Exception {
  const ChallengeException(this.message);
  final String message;
  @override
  String toString() => 'ChallengeException($message)';
}

abstract class ChallengesApi {
  /// Newest first.
  Future<List<GroupChallenge>> forLeague(String leagueId);
  Future<void> create(Map<String, dynamic> row);

  /// `finalize_group_challenge`; returns its json.
  Future<Map<String, dynamic>> finalize(String challengeId);
  Future<void> cancel(String challengeId);
  Future<List<ChallengeTrip>> trips(
    List<String> userIds,
    DateTime from,
    DateTime to,
  );
}

class SupabaseChallengesApi implements ChallengesApi {
  SupabaseChallengesApi(this.client);
  final SupabaseClient client;

  @override
  Future<List<GroupChallenge>> forLeague(String leagueId) async {
    final rows = await client
        .from('group_challenges')
        .select()
        .eq('league_id', leagueId)
        .order('starts_at', ascending: false)
        .limit(12);
    return [for (final r in rows) GroupChallenge.fromJson(r)];
  }

  @override
  Future<void> create(Map<String, dynamic> row) => client
      .from('group_challenges')
      .upsert(row, onConflict: 'id', ignoreDuplicates: true);

  @override
  Future<Map<String, dynamic>> finalize(String challengeId) async {
    final r = await client.rpc(
      'finalize_group_challenge',
      params: {'p_challenge_id': challengeId},
    );
    return r is Map<String, dynamic> ? r : const {};
  }

  @override
  Future<void> cancel(String challengeId) => client
      .from('group_challenges')
      .delete()
      .eq('id', challengeId)
      .eq('status', 'active');

  @override
  Future<List<ChallengeTrip>> trips(
    List<String> userIds,
    DateTime from,
    DateTime to,
  ) async {
    if (userIds.isEmpty) return const [];
    final rows = await client
        .from('trip_summaries')
        .select('user_id, score, reckless, trip_events(kind)')
        .inFilter('user_id', userIds)
        .eq('scored', true)
        .eq('is_passenger', false)
        .eq('trip_events.kind', 'phone_handling')
        .gte('started_at', from.toUtc().toIso8601String())
        .lt('started_at', to.toUtc().toIso8601String());
    return [
      for (final r in rows)
        ChallengeTrip(
          userId: r['user_id'] as String,
          score: (r['score'] as num?)?.toInt() ?? 0,
          reckless: r['reckless'] as bool? ?? false,
          phoneHandling: ((r['trip_events'] as List?) ?? const []).isNotEmpty,
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Repo
// ---------------------------------------------------------------------------

/// Group challenges per league: cached list, outbox creation, live progress
/// computed on the phone from members' summaries (like league standings).
class ChallengesRepo {
  ChallengesRepo({
    required this.db,
    required this.api,
    required this.outbox,
    required this.userId,
    this.awardBadge,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _registerHandlers();
  }

  final AppDatabase db;
  final ChallengesApi? api;
  final OutboxWorker outbox;
  final String? Function() userId;

  /// Local badge award for a met challenge (the cloud writes `user_badges`
  /// for every member; this makes it show on this phone at once).
  final Future<void> Function(String badgeId)? awardBadge;
  final int Function() _now;

  static const kindCreate = 'challenge_create';
  static const _uuid = Uuid();

  DateTime get _nowDt => DateTime.fromMillisecondsSinceEpoch(_now());

  void _registerHandlers() {
    if (outbox.handles(kindCreate)) return;
    outbox.register(kindCreate, (p) async {
      final a = api;
      final uid = userId();
      if (a == null || uid == null) throw const OutboxRetryLater();
      if (p['user_id'] != uid) throw const OutboxSkip('another account');
      try {
        await a.create({
          'id': p['id'],
          'league_id': p['league_id'],
          'created_by': uid,
          'goal': p['goal'],
          'target': p['target'],
          'starts_at': p['starts_at'],
          'ends_at': p['ends_at'],
        });
      } on PostgrestException catch (e) {
        // 23505: another member started one first (one active per league).
        if (e.code == '23505') {
          debugPrint('challenge_create dropped: league already has one');
          return;
        }
        rethrow;
      }
    });
  }

  String _requireUser() {
    final uid = userId();
    if (uid == null) throw const ChallengeException('Sign in first.');
    return uid;
  }

  String _listKey(String leagueId) => 'league:$leagueId:challenges';

  Future<List<GroupChallenge>> _cached(String leagueId) async {
    final json = await db.cacheGet(_listKey(leagueId));
    if (json == null) return const [];
    return [
      for (final j in jsonDecode(json) as List)
        GroupChallenge.fromJson(j as Map<String, dynamic>),
    ];
  }

  Future<void> _store(String leagueId, List<GroupChallenge> list) =>
      db.cachePut(
        _listKey(leagueId),
        jsonEncode([for (final c in list) c.toJson()]),
        _now(),
      );

  /// The league's challenges, newest first. A running one whose window has
  /// closed is settled first (idempotent RPC; the daily cron is the
  /// backstop) and, when met, the goal's badge is awarded locally.
  Future<List<GroupChallenge>> challenges(
    String leagueId, {
    bool refresh = true,
  }) async {
    final a = api;
    if (a != null && refresh) {
      try {
        var list = await a.forLeague(leagueId);
        var settled = false;
        for (final c in list.where((c) => c.isDue(_nowDt))) {
          try {
            final r = await a.finalize(c.id);
            settled = true;
            if (r['status'] == 'succeeded') {
              await awardBadge?.call(c.goal.badgeId);
            }
          } catch (e) {
            debugPrint('finalize_group_challenge(${c.id}): $e');
          }
        }
        if (settled) list = await a.forLeague(leagueId);
        await _store(leagueId, list);
        return list;
      } catch (e) {
        debugPrint('challenges refresh failed: $e');
      }
    }
    return _cached(leagueId);
  }

  /// The running challenge, if any.
  Future<GroupChallenge?> current(
    String leagueId, {
    bool refresh = true,
  }) async {
    final list = await challenges(leagueId, refresh: refresh);
    for (final c in list) {
      if (c.isActive) return c;
    }
    return null;
  }

  /// Starts a challenge. Optimistic cache entry, then the outbox.
  Future<GroupChallenge> create({
    required String leagueId,
    required ChallengeGoal goal,
    required int target,
    int days = 7,
  }) async {
    final uid = _requireUser();
    if (target <= 0 || target > 10000) {
      throw const ChallengeException('Pick a target above zero.');
    }
    if (goal == ChallengeGoal.scoreAvg && target > 100) {
      throw const ChallengeException('A Drive Score target is at most 100.');
    }
    if (!challengeDurationsDays.contains(days)) {
      throw const ChallengeException('Challenges run one or two weeks.');
    }
    final existing = await _cached(leagueId);
    if (existing.any((c) => c.isActive && !c.isDue(_nowDt))) {
      throw const ChallengeException(
        'This league already has a challenge running.',
      );
    }
    final now = _nowDt;
    final challenge = GroupChallenge(
      id: _uuid.v4(),
      leagueId: leagueId,
      createdBy: uid,
      goal: goal,
      target: target,
      startsAt: now,
      endsAt: now.add(Duration(days: days)),
      status: 'active',
    );
    await _store(leagueId, [challenge, ...existing]);
    await outbox.enqueue(kindCreate, {
      'id': challenge.id,
      'league_id': leagueId,
      'user_id': uid,
      'goal': goal.wire,
      'target': target,
      'starts_at': challenge.startsAt.toUtc().toIso8601String(),
      'ends_at': challenge.endsAt.toUtc().toIso8601String(),
    }, id: 'challenge_create:${challenge.id}');
    await outbox.drain();
    return challenge;
  }

  /// The creator calls off a running challenge.
  Future<void> cancel(GroupChallenge challenge) async {
    _requireUser();
    await api?.cancel(challenge.id);
    await _store(challenge.leagueId, [
      for (final c in await _cached(challenge.leagueId))
        if (c.id != challenge.id) c,
    ]);
  }

  String _progressKey(String id) => 'challenge:$id:progress';

  /// Live progress from members' summaries; the stored result once settled.
  Future<ChallengeProgress> progress(
    GroupChallenge challenge,
    List<LeagueMember> members,
  ) async {
    final ids = [for (final m in members) m.userId];
    if (!challenge.isActive) {
      return ChallengeProgress(
        value: challenge.value ?? 0,
        needed: challenge.goal == ChallengeGoal.everyoneDrives
            ? challenge.perMember.length
            : challenge.target,
        target: challenge.target,
        members: challenge.perMember.length,
        met: challenge.succeeded,
        perMember: challenge.perMember,
      );
    }
    final a = api;
    if (a != null) {
      try {
        final to = challenge.endsAt.isBefore(_nowDt)
            ? challenge.endsAt
            : _nowDt;
        final trips = await a.trips(ids, challenge.startsAt, to);
        final p = computeChallengeProgress(challenge, ids, trips);
        await db.cachePut(
          _progressKey(challenge.id),
          jsonEncode({
            'value': p.value,
            'needed': p.needed,
            'target': p.target,
            'members': p.members,
            'met': p.met,
            'per_member': [for (final m in p.perMember) m.toJson()],
          }),
          _now(),
        );
        return p;
      } catch (e) {
        debugPrint('challenge progress refresh failed: $e');
      }
    }
    final cached = await db.cacheGet(_progressKey(challenge.id));
    if (cached == null) {
      return computeChallengeProgress(challenge, ids, const []);
    }
    final j = jsonDecode(cached) as Map<String, dynamic>;
    return ChallengeProgress(
      value: (j['value'] as num).toDouble(),
      needed: (j['needed'] as num).toInt(),
      target: (j['target'] as num).toInt(),
      members: (j['members'] as num).toInt(),
      met: j['met'] as bool,
      perMember: [
        for (final m in (j['per_member'] as List?) ?? const [])
          ChallengeMemberProgress.fromJson(m as Map<String, dynamic>),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final challengesApiProvider = Provider<ChallengesApi?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : SupabaseChallengesApi(client);
});

final challengesRepoProvider = Provider<ChallengesRepo>((ref) {
  return ChallengesRepo(
    db: ref.watch(databaseProvider),
    api: ref.watch(challengesApiProvider),
    outbox: ref.watch(outboxWorkerProvider),
    userId: () => ref.read(currentUserIdProvider),
    awardBadge: (id) async {
      await ref.read(badgesSyncProvider).engine.award(id);
    },
  );
});

/// A league's challenges, newest first (cloud, then cache).
final leagueChallengesProvider =
    FutureProvider.family<List<GroupChallenge>, String>(
      (ref, leagueId) => ref.watch(challengesRepoProvider).challenges(leagueId),
    );

/// Progress for one challenge, keyed by (leagueId, challengeId).
final challengeProgressProvider =
    FutureProvider.family<ChallengeProgress?, (String, String)>((
      ref,
      key,
    ) async {
      final (leagueId, challengeId) = key;
      final list = await ref.watch(leagueChallengesProvider(leagueId).future);
      GroupChallenge? challenge;
      for (final c in list) {
        if (c.id == challengeId) challenge = c;
      }
      if (challenge == null) return null;
      final members = await ref.watch(leagueMembersProvider(leagueId).future);
      return ref.watch(challengesRepoProvider).progress(challenge, members);
    });
