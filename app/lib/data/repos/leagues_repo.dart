import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../badges/badges_sync.dart';
import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Duolingo-style tiers (docs/02-game-design.md §7). Declaration order is
/// rank order; promotion moves one step up, demotion one step down.
enum LeagueTier {
  learner('learner', 'Learner'),
  bronze('bronze', 'Bronze'),
  silver('silver', 'Silver'),
  gold('gold', 'Gold'),
  platinum('platinum', 'Platinum'),
  diamond('diamond', 'Diamond'),
  chauffeur('chauffeur', 'Chauffeur');

  const LeagueTier(this.wire, this.label);
  final String wire;
  final String label;

  static LeagueTier fromWire(String? wire) =>
      values.firstWhere((t) => t.wire == wire, orElse: () => learner);

  LeagueTier get next => index == values.length - 1 ? this : values[index + 1];
  LeagueTier get previous => index == 0 ? this : values[index - 1];
}

/// A league the user belongs to, with their own membership row folded in.
class League {
  const League({
    required this.id,
    required this.name,
    required this.kind,
    required this.inviteCode,
    required this.createdBy,
    required this.maxMembers,
    required this.createdAt,
    required this.myTier,
    required this.myHiding,
    required this.memberCount,
    this.closedAt,
  });

  factory League.fromJson(Map<String, dynamic> j) => League(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: j['kind'] as String? ?? 'friend',
    inviteCode: j['invite_code'] as String? ?? '',
    createdBy: j['created_by'] as String? ?? '',
    maxMembers: (j['max_members'] as num?)?.toInt() ?? 30,
    createdAt:
        DateTime.tryParse(j['created_at'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    myTier: LeagueTier.fromWire(j['my_tier'] as String?),
    myHiding: j['my_hiding'] as bool? ?? false,
    memberCount: (j['member_count'] as num?)?.toInt() ?? 1,
    closedAt: DateTime.tryParse(j['closed_at'] as String? ?? ''),
  );

  final String id;
  final String name;
  final String kind;
  final String inviteCode;
  final String createdBy;
  final int maxMembers;
  final DateTime createdAt;
  final LeagueTier myTier;
  final bool myHiding;
  final int memberCount;

  /// Set on a global league once Monday's matchmaking replaced it. Its
  /// finalised week stays readable (the badge pass needs it) but it is no
  /// longer one of "my leagues".
  final DateTime? closedAt;

  bool get isClosed => closedAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'invite_code': inviteCode,
    'created_by': createdBy,
    'max_members': maxMembers,
    'created_at': createdAt.toUtc().toIso8601String(),
    'my_tier': myTier.wire,
    'my_hiding': myHiding,
    'member_count': memberCount,
    'closed_at': closedAt?.toIso8601String(),
  };

  League copyWith({bool? myHiding, LeagueTier? myTier, int? memberCount}) =>
      League(
        id: id,
        name: name,
        kind: kind,
        inviteCode: inviteCode,
        createdBy: createdBy,
        maxMembers: maxMembers,
        createdAt: createdAt,
        myTier: myTier ?? this.myTier,
        myHiding: myHiding ?? this.myHiding,
        memberCount: memberCount ?? this.memberCount,
        closedAt: closedAt,
      );

  /// `drivalry://join/league/<code>`; opened by the app's deep-link handler.
  String get inviteLink => 'drivalry://join/league/$inviteCode';

  /// Matchmade every Monday (docs/02 §12.4): no invite code, no owner, and
  /// leaving goes through `leave_global_league`.
  bool get isGlobal => kind == 'global';
}

class LeagueMember {
  const LeagueMember({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.tier,
    required this.hiding,
    this.avatarUrl,
    this.rating,
  });

  factory LeagueMember.fromJson(Map<String, dynamic> j) => LeagueMember(
    userId: j['user_id'] as String,
    handle: j['handle'] as String? ?? 'driver',
    displayName: j['display_name'] as String? ?? '',
    tier: LeagueTier.fromWire(j['tier'] as String?),
    hiding: j['hiding'] as bool? ?? false,
    avatarUrl: j['avatar_url'] as String?,
    rating: (j['rating'] as num?)?.toDouble(),
  );

  final String userId;
  final String handle;
  final String displayName;
  final LeagueTier tier;

  /// Visible to the whole league: this member is hiding their trips here.
  final bool hiding;
  final String? avatarUrl;

  /// Driver Rating (30-day), the tie-breaker. Null until five scored trips.
  final double? rating;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'handle': handle,
    'display_name': displayName,
    'tier': tier.wire,
    'hiding': hiding,
    'avatar_url': avatarUrl,
    'rating': rating,
  };
}

/// One member's week: XP and trips, ranked, with where the tier is heading.
class Standing {
  const Standing({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.xp,
    required this.trips,
    required this.rating,
    required this.rank,
    required this.tier,
    required this.projectedTier,
  });

  final String userId;
  final String handle;
  final String displayName;
  final int xp;
  final int trips;
  final double? rating;
  final int rank;

  /// Tier at the start of the week.
  final LeagueTier tier;

  /// Where the week's rules put this member: live projection for the current
  /// week, the recorded outcome for a finalised one.
  final LeagueTier projectedTier;

  bool get promotes => projectedTier.index > tier.index;
  bool get demotes => projectedTier.index < tier.index;
}

class WeekStandings {
  const WeekStandings({
    required this.weekStart,
    required this.rows,
    required this.finalized,
  });

  /// Local Monday 00:00.
  final DateTime weekStart;
  final List<Standing> rows;
  final bool finalized;

  Standing? rowFor(String userId) {
    for (final r in rows) {
      if (r.userId == userId) return r;
    }
    return null;
  }
}

/// The minimum a standings computation needs from `trip_summaries`.
class WeekSummary {
  const WeekSummary({required this.userId, required this.xp});
  final String userId;
  final int xp;
}

// ---------------------------------------------------------------------------
// Week math and standings (pure)
// ---------------------------------------------------------------------------

/// Local Monday 00:00 of the week containing [t]. Built from calendar fields,
/// so a daylight-saving change inside the week cannot shift it.
DateTime localWeekStart(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day - (l.weekday - DateTime.monday));
}

DateTime nextWeekStart(DateTime weekStart) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day + 7);

DateTime previousWeekStart(DateTime weekStart) =>
    DateTime(weekStart.year, weekStart.month, weekStart.day - 7);

/// `yyyy-MM-dd`, the `week_start` date the database stores.
String weekStartDate(DateTime weekStart) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${weekStart.year.toString().padLeft(4, '0')}-'
      '${two(weekStart.month)}-${two(weekStart.day)}';
}

/// Parses a `yyyy-MM-dd` week start into local midnight.
DateTime parseWeekStartDate(String s) {
  final parts = s.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2].substring(0, 2)),
  );
}

/// Mirrors `finalize_league_week` in `0001_init.sql`: zero trips demote; top
/// five promote and bottom five demote once the league has more than five
/// members; Learner cannot fall and Chauffeur cannot rise.
LeagueTier projectTier({
  required LeagueTier tier,
  required int rank,
  required int total,
  required int trips,
}) {
  if (trips == 0) return tier.previous;
  if (rank <= 5 && total > 5) return tier.next;
  if (rank > total - 5 && total > 5) return tier.previous;
  return tier;
}

/// Sums each member's week and ranks them: XP, then Driver Rating (nulls
/// last), then user id, exactly like the database function.
List<Standing> computeStandings(
  List<LeagueMember> members,
  List<WeekSummary> summaries,
) {
  final xp = <String, int>{};
  final trips = <String, int>{};
  for (final s in summaries) {
    xp[s.userId] = (xp[s.userId] ?? 0) + s.xp;
    trips[s.userId] = (trips[s.userId] ?? 0) + 1;
  }
  final sorted = [...members]
    ..sort((a, b) {
      final byXp = (xp[b.userId] ?? 0).compareTo(xp[a.userId] ?? 0);
      if (byXp != 0) return byXp;
      final ra = a.rating, rb = b.rating;
      if (ra != null || rb != null) {
        if (ra == null) return 1;
        if (rb == null) return -1;
        final byRating = rb.compareTo(ra);
        if (byRating != 0) return byRating;
      }
      return a.userId.compareTo(b.userId);
    });
  final total = sorted.length;
  return [
    for (var i = 0; i < sorted.length; i++)
      Standing(
        userId: sorted[i].userId,
        handle: sorted[i].handle,
        displayName: sorted[i].displayName,
        xp: xp[sorted[i].userId] ?? 0,
        trips: trips[sorted[i].userId] ?? 0,
        rating: sorted[i].rating,
        rank: i + 1,
        tier: sorted[i].tier,
        projectedTier: projectTier(
          tier: sorted[i].tier,
          rank: i + 1,
          total: total,
          trips: trips[sorted[i].userId] ?? 0,
        ),
      ),
  ];
}

/// Reads a finalised `league_weeks.standings` array.
List<Standing> standingsFromFinalized(
  List<dynamic> json,
  Map<String, LeagueMember> members,
) => [
  for (final raw in json)
    if (raw is Map<String, dynamic>)
      Standing(
        userId: raw['user_id'] as String,
        handle: members[raw['user_id']]?.handle ?? 'driver',
        displayName: members[raw['user_id']]?.displayName ?? '',
        xp: (raw['xp'] as num?)?.toInt() ?? 0,
        trips: (raw['trips'] as num?)?.toInt() ?? 0,
        rating: (raw['rating'] as num?)?.toDouble(),
        rank: (raw['rank'] as num?)?.toInt() ?? 0,
        tier: LeagueTier.fromWire(raw['tier_before'] as String?),
        projectedTier: LeagueTier.fromWire(raw['tier_after'] as String?),
      ),
]..sort((a, b) => a.rank.compareTo(b.rank));

// ---------------------------------------------------------------------------
// Remote API
// ---------------------------------------------------------------------------

enum LeagueJoinError { invalidCode, full, notSignedIn, unavailable }

class LeagueJoinException implements Exception {
  const LeagueJoinException(this.error, [this.detail]);
  final LeagueJoinError error;
  final String? detail;

  String get message => switch (error) {
    LeagueJoinError.invalidCode => 'That invite code is not valid.',
    LeagueJoinError.full => 'That league is full (30 members).',
    LeagueJoinError.notSignedIn => 'Sign in first.',
    LeagueJoinError.unavailable => 'Could not reach Drivalry. Try again.',
  };

  @override
  String toString() => 'LeagueJoinException($error, $detail)';
}

/// Maps the error codes `join_league` raises (`0001_init.sql`).
LeagueJoinError mapJoinError(Object e) {
  if (e is PostgrestException) {
    if (e.code == 'P0001') return LeagueJoinError.invalidCode;
    if (e.code == 'P0002') return LeagueJoinError.full;
    final m = e.message.toLowerCase();
    if (m.contains('invalid invite code')) return LeagueJoinError.invalidCode;
    if (m.contains('full')) return LeagueJoinError.full;
  }
  return LeagueJoinError.unavailable;
}

/// Everything the repo asks the cloud for. Faked in tests.
abstract class LeaguesApi {
  Future<List<League>> myLeagues(String userId);
  Future<List<LeagueMember>> members(String leagueId);
  Future<List<WeekSummary>> weekSummaries(
    List<String> userIds,
    DateTime fromLocal,
    DateTime toLocal,
  );

  /// `week_start` date → standings json, newest first.
  Future<List<(String, List<dynamic>)>> weeks(String leagueId);

  /// Every finalised week the caller can read (RLS: leagues they belong to,
  /// closed global ones included) with `week_start >= sinceDate`, as
  /// `(league_id, week_start, standings)`. Feeds the week-badge pass, which
  /// must not depend on the league still being listed.
  Future<List<(String, String, List<dynamic>)>> recentWeeks(String sinceDate);
  Future<String> joinByCode(String code);
  Future<void> leave(String leagueId, String userId);
  Future<void> finalizeWeek(String leagueId, String weekStartDate);
  Future<void> createLeague({
    required String id,
    required String name,
    required String userId,
  });
  Future<void> setHiding({
    required String leagueId,
    required String userId,
    required bool hiding,
  });

  /// `join_global_league()`: joins the pool and returns this week's league.
  Future<String> joinGlobalLeague();

  /// `leave_global_league()`: out of this week's league and the pool.
  Future<void> leaveGlobalLeague();
}

class SupabaseLeaguesApi implements LeaguesApi {
  SupabaseLeaguesApi(this.client);
  final SupabaseClient client;

  String? _avatarUrl(String? path) => path == null || path.isEmpty
      ? null
      : client.storage.from('avatars').getPublicUrl(path);

  @override
  Future<List<League>> myLeagues(String userId) async {
    final rows = await client
        .from('league_members')
        .select(
          'tier, hiding, leagues(id, name, kind, invite_code, created_by, '
          'max_members, created_at, closed_at)',
        )
        .eq('user_id', userId);
    final leagues = <League>[];
    for (final r in rows) {
      final l = r['leagues'] as Map<String, dynamic>?;
      if (l == null) continue;
      leagues.add(
        League.fromJson({...l, 'my_tier': r['tier'], 'my_hiding': r['hiding']}),
      );
    }
    if (leagues.isEmpty) return leagues;
    final counts = <String, int>{};
    final memberRows = await client
        .from('league_members')
        .select('league_id')
        .inFilter('league_id', [for (final l in leagues) l.id]);
    for (final r in memberRows) {
      final id = r['league_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return [for (final l in leagues) l.copyWith(memberCount: counts[l.id] ?? 1)]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Future<List<LeagueMember>> members(String leagueId) async {
    final rows = await client
        .from('league_members')
        .select(
          'user_id, tier, hiding, profiles(handle, display_name, avatar_path, '
          'driver_rating)',
        )
        .eq('league_id', leagueId);
    return [
      for (final r in rows)
        LeagueMember(
          userId: r['user_id'] as String,
          handle: (r['profiles']?['handle'] as String?) ?? 'driver',
          displayName: (r['profiles']?['display_name'] as String?) ?? '',
          tier: LeagueTier.fromWire(r['tier'] as String?),
          hiding: r['hiding'] as bool? ?? false,
          avatarUrl: _avatarUrl(r['profiles']?['avatar_path'] as String?),
          rating: (r['profiles']?['driver_rating'] as num?)?.toDouble(),
        ),
    ];
  }

  @override
  Future<List<WeekSummary>> weekSummaries(
    List<String> userIds,
    DateTime fromLocal,
    DateTime toLocal,
  ) async {
    if (userIds.isEmpty) return const [];
    final rows = await client
        .from('trip_summaries')
        .select('user_id, xp')
        .inFilter('user_id', userIds)
        .eq('scored', true)
        .eq('is_passenger', false)
        .gte('started_at', fromLocal.toUtc().toIso8601String())
        .lt('started_at', toLocal.toUtc().toIso8601String());
    return [
      for (final r in rows)
        WeekSummary(
          userId: r['user_id'] as String,
          xp: (r['xp'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  @override
  Future<List<(String, List<dynamic>)>> weeks(String leagueId) async {
    final rows = await client
        .from('league_weeks')
        .select('week_start, standings')
        .eq('league_id', leagueId)
        .order('week_start', ascending: false)
        .limit(26);
    return [
      for (final r in rows)
        (r['week_start'] as String, (r['standings'] as List?) ?? const []),
    ];
  }

  @override
  Future<List<(String, String, List<dynamic>)>> recentWeeks(
    String sinceDate,
  ) async {
    final rows = await client
        .from('league_weeks')
        .select('league_id, week_start, standings')
        .gte('week_start', sinceDate)
        .order('week_start', ascending: false)
        .limit(60);
    return [
      for (final r in rows)
        (
          r['league_id'] as String,
          r['week_start'] as String,
          (r['standings'] as List?) ?? const [],
        ),
    ];
  }

  @override
  Future<String> joinByCode(String code) async {
    try {
      final id = await client.rpc('join_league', params: {'code': code.trim()});
      return id as String;
    } catch (e) {
      throw LeagueJoinException(mapJoinError(e), e.toString());
    }
  }

  @override
  Future<void> leave(String leagueId, String userId) => client
      .from('league_members')
      .delete()
      .eq('league_id', leagueId)
      .eq('user_id', userId);

  @override
  Future<void> finalizeWeek(String leagueId, String weekStartDate) =>
      client.rpc(
        'finalize_league_week',
        params: {'p_league_id': leagueId, 'p_week_start': weekStartDate},
      );

  @override
  Future<void> createLeague({
    required String id,
    required String name,
    required String userId,
  }) async {
    await client
        .from('leagues')
        .upsert(
          {'id': id, 'name': name, 'created_by': userId},
          onConflict: 'id',
          ignoreDuplicates: true,
        );
    await client
        .from('league_members')
        .upsert(
          {'league_id': id, 'user_id': userId},
          onConflict: 'league_id,user_id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> setHiding({
    required String leagueId,
    required String userId,
    required bool hiding,
  }) => client
      .from('league_members')
      .update({'hiding': hiding})
      .eq('league_id', leagueId)
      .eq('user_id', userId);

  @override
  Future<String> joinGlobalLeague() async {
    try {
      final id = await client.rpc('join_global_league');
      return id as String;
    } catch (e) {
      throw LeagueJoinException(mapJoinError(e), e.toString());
    }
  }

  @override
  Future<void> leaveGlobalLeague() => client.rpc('leave_global_league');
}

// ---------------------------------------------------------------------------
// Repo: cache-first reads, outbox writes
// ---------------------------------------------------------------------------

/// Leagues for the signed-in user. Reads go cloud → `RemoteCache` so the tab
/// renders offline with the last snapshot; writes go through the outbox.
class LeaguesRepo {
  LeaguesRepo({
    required this.db,
    required this.api,
    required this.outbox,
    required this.userId,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _registerHandlers();
  }

  final AppDatabase db;
  final LeaguesApi? api;
  final OutboxWorker outbox;
  final String? Function() userId;
  final int Function() _now;

  static const kindCreate = 'league_create';
  static const kindHiding = 'league_hiding';
  static const _uuid = Uuid();

  void _registerHandlers() {
    if (outbox.handles(kindCreate)) return;
    outbox.register(kindCreate, (p) async {
      final a = api;
      final uid = userId();
      if (a == null || uid == null) throw const OutboxRetryLater();
      if (p['user_id'] != uid) throw const OutboxSkip('another account');
      await a.createLeague(
        id: p['id'] as String,
        name: p['name'] as String,
        userId: p['user_id'] as String,
      );
    });
    outbox.register(kindHiding, (p) async {
      final a = api;
      final uid = userId();
      if (a == null || uid == null) throw const OutboxRetryLater();
      if (p['user_id'] != uid) throw const OutboxSkip('another account');
      await a.setHiding(
        leagueId: p['league_id'] as String,
        userId: p['user_id'] as String,
        hiding: p['hiding'] as bool,
      );
    });
  }

  String _requireUser() {
    final uid = userId();
    if (uid == null) {
      throw const LeagueJoinException(LeagueJoinError.notSignedIn);
    }
    return uid;
  }

  // ----------------------------------------------------------- my leagues --

  static const _mineKey = 'leagues:mine';

  Future<List<League>> cachedMyLeagues() async {
    final json = await db.cacheGet(_mineKey);
    if (json == null) return const [];
    return _decodeLeagues(json);
  }

  Stream<List<League>> watchMyLeagues() => db
      .watchCache(_mineKey)
      .map((json) => json == null ? const <League>[] : _decodeLeagues(json));

  List<League> _decodeLeagues(String json) => [
    for (final j in jsonDecode(json) as List)
      League.fromJson(j as Map<String, dynamic>),
  ];

  /// Cloud first; on failure the cache is left as it was and rethrown so the
  /// screen can say "showing last known".
  Future<List<League>> refreshMyLeagues() async {
    final a = api;
    final uid = userId();
    if (a == null || uid == null) return cachedMyLeagues();
    // A closed global league is last week's table: readable for its week
    // row, no longer somewhere to play.
    final leagues = [
      for (final l in await a.myLeagues(uid))
        if (!l.isClosed) l,
    ];
    await db.cachePut(
      _mineKey,
      jsonEncode([for (final l in leagues) l.toJson()]),
      _now(),
    );
    return leagues;
  }

  /// Settings key holding the newest `week_start` the badge pass has seen.
  static String weekBadgesKey(String uid) => 'league_week_badges:$uid';

  /// Awards `league_week` and `promoted` from every finalised week that
  /// includes me, reading `league_weeks` directly so a global league that
  /// was closed on Monday (or a friend league I since left) still counts.
  /// Looks back eight weeks the first time, then from the last week seen.
  /// Returns the number of my rows processed; 0 offline or signed out.
  Future<int> awardRecentWeekBadges(
    Future<bool> Function(String badgeId) award, {
    DateTime? now,
  }) async {
    final a = api;
    final uid = userId();
    if (a == null || uid == null) return 0;
    final seen = await db.getSetting(weekBadgesKey(uid));
    final since = seen != null && seen.isNotEmpty
        ? parseWeekStartDate(seen).add(const Duration(days: 1))
        : (now ?? DateTime.fromMillisecondsSinceEpoch(_now())).subtract(
            const Duration(days: 56),
          );
    final rows = await a.recentWeeks(weekStartDate(since));
    var mine = 0;
    String? newest;
    for (final (_, weekStart, standings) in rows) {
      if (newest == null || weekStart.compareTo(newest) > 0) {
        newest = weekStart;
      }
      for (final raw in standings) {
        if (raw is! Map || raw['user_id'] != uid) continue;
        mine++;
        await award('league_week');
        final before = LeagueTier.fromWire(raw['tier_before'] as String?);
        final after = LeagueTier.fromWire(raw['tier_after'] as String?);
        if (after.index > before.index) await award('promoted');
      }
    }
    if (newest != null) await db.setSetting(weekBadgesKey(uid), newest);
    return mine;
  }

  Future<League> createLeague(String name) async {
    final uid = _requireUser();
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) {
      throw ArgumentError('League names are 1 to 40 characters.');
    }
    final id = _uuid.v4();
    await outbox.enqueue(kindCreate, {
      'id': id,
      'name': trimmed,
      'user_id': uid,
    }, id: 'league_create:$id');
    await outbox.drain();
    List<League> leagues;
    try {
      leagues = await refreshMyLeagues();
    } catch (e) {
      debugPrint('createLeague: refresh failed, using cache: $e');
      leagues = await cachedMyLeagues();
    }
    return leagues.firstWhere(
      (l) => l.id == id,
      orElse: () => League(
        id: id,
        name: trimmed,
        kind: 'friend',
        inviteCode: '',
        createdBy: uid,
        maxMembers: 30,
        createdAt: DateTime.fromMillisecondsSinceEpoch(_now()),
        myTier: LeagueTier.learner,
        myHiding: false,
        memberCount: 1,
      ),
    );
  }

  Future<String> joinByCode(String code) async {
    _requireUser();
    final a = api;
    if (a == null) {
      throw const LeagueJoinException(LeagueJoinError.unavailable);
    }
    final id = await a.joinByCode(code);
    await refreshMyLeagues();
    return id;
  }

  Future<void> leave(String leagueId) async {
    final uid = _requireUser();
    final a = api;
    League? league;
    for (final l in await cachedMyLeagues()) {
      if (l.id == leagueId) league = l;
    }
    if (league != null && league.isGlobal) {
      await a?.leaveGlobalLeague();
    } else {
      await a?.leave(leagueId, uid);
    }
    await db.cacheDeletePrefix('league:$leagueId:');
    await refreshMyLeagues();
  }

  /// Joins the global pool (docs/02 §12.4) and returns this week's league
  /// id. Needs the cloud: there is nothing to queue, the server seats you.
  Future<String> joinGlobalLeague() async {
    _requireUser();
    final a = api;
    if (a == null) {
      throw const LeagueJoinException(LeagueJoinError.unavailable);
    }
    final id = await a.joinGlobalLeague();
    await refreshMyLeagues();
    return id;
  }

  /// Optimistic: the cache flips at once, the cloud follows via the outbox.
  Future<void> setHiding(String leagueId, bool hiding) async {
    final uid = _requireUser();
    final current = await cachedMyLeagues();
    await db.cachePut(
      _mineKey,
      jsonEncode([
        for (final l in current)
          (l.id == leagueId ? l.copyWith(myHiding: hiding) : l).toJson(),
      ]),
      _now(),
    );
    await outbox.enqueue(kindHiding, {
      'league_id': leagueId,
      'user_id': uid,
      'hiding': hiding,
    }, id: 'league_hiding:$leagueId:$uid');
  }

  // -------------------------------------------------------------- members --

  String _membersKey(String id) => 'league:$id:members';

  Future<List<LeagueMember>> members(
    String leagueId, {
    bool refresh = true,
  }) async {
    final a = api;
    if (a != null && refresh) {
      try {
        final fresh = await a.members(leagueId);
        await db.cachePut(
          _membersKey(leagueId),
          jsonEncode([for (final m in fresh) m.toJson()]),
          _now(),
        );
        return fresh;
      } catch (e) {
        debugPrint('league members refresh failed: $e');
      }
    }
    final json = await db.cacheGet(_membersKey(leagueId));
    if (json == null) return const [];
    return [
      for (final j in jsonDecode(json) as List)
        LeagueMember.fromJson(j as Map<String, dynamic>),
    ];
  }

  // ------------------------------------------------------------ standings --

  /// The running week, computed on the phone from members' summaries.
  Future<WeekStandings> currentWeek(String leagueId, {DateTime? now}) async {
    final weekStart = localWeekStart(now ?? DateTime.now());
    final key = 'league:$leagueId:week:${weekStartDate(weekStart)}';
    final members = await this.members(leagueId);
    final a = api;
    if (a != null && members.isNotEmpty) {
      try {
        final summaries = await a.weekSummaries(
          [for (final m in members) m.userId],
          weekStart,
          nextWeekStart(weekStart),
        );
        final rows = computeStandings(members, summaries);
        await db.cachePut(key, jsonEncode(_encodeRows(rows)), _now());
        return WeekStandings(
          weekStart: weekStart,
          rows: rows,
          finalized: false,
        );
      } catch (e) {
        debugPrint('standings refresh failed: $e');
      }
    }
    final cached = await db.cacheGet(key);
    return WeekStandings(
      weekStart: weekStart,
      rows: cached == null
          ? computeStandings(members, const [])
          : _decodeRows(cached),
      finalized: false,
    );
  }

  /// Finalised weeks, newest first. Triggers the previous week's rollover
  /// once per league per week if nobody has done it yet (docs/03 §7).
  Future<List<WeekStandings>> pastWeeks(
    String leagueId, {
    DateTime? now,
  }) async {
    final a = api;
    final key = 'league:$leagueId:weeks';
    if (a != null) {
      await _ensurePreviousWeekFinalized(leagueId, a, now ?? DateTime.now());
      try {
        final members = {
          for (final m in await this.members(leagueId)) m.userId: m,
        };
        final weeks = await a.weeks(leagueId);
        final result = [
          for (final (date, json) in weeks)
            WeekStandings(
              weekStart: parseWeekStartDate(date),
              rows: standingsFromFinalized(json, members),
              finalized: true,
            ),
        ];
        await db.cachePut(
          key,
          jsonEncode([
            for (final w in result)
              {
                'week_start': weekStartDate(w.weekStart),
                'rows': _encodeRows(w.rows),
              },
          ]),
          _now(),
        );
        return result;
      } catch (e) {
        debugPrint('past weeks refresh failed: $e');
      }
    }
    final cached = await db.cacheGet(key);
    if (cached == null) return const [];
    return [
      for (final w in jsonDecode(cached) as List)
        WeekStandings(
          weekStart: parseWeekStartDate(w['week_start'] as String),
          rows: _decodeRows(jsonEncode(w['rows'])),
          finalized: true,
        ),
    ];
  }

  Future<void> _ensurePreviousWeekFinalized(
    String leagueId,
    LeaguesApi a,
    DateTime now,
  ) async {
    final prev = weekStartDate(previousWeekStart(localWeekStart(now)));
    final settingKey = 'league:$leagueId:finalized:$prev';
    if (await db.getSetting(settingKey) != null) {
      return;
    }
    try {
      final weeks = await a.weeks(leagueId);
      if (!weeks.any((w) => w.$1 == prev)) {
        await a.finalizeWeek(leagueId, prev);
      }
      await db.setSetting(settingKey, '1');
    } catch (e) {
      // 'week not over yet' (P0003), a duplicate, or no network: try again on
      // the next open.
      debugPrint('finalize_league_week($leagueId, $prev): $e');
    }
  }

  List<Map<String, dynamic>> _encodeRows(List<Standing> rows) => [
    for (final r in rows)
      {
        'user_id': r.userId,
        'handle': r.handle,
        'display_name': r.displayName,
        'xp': r.xp,
        'trips': r.trips,
        'rating': r.rating,
        'rank': r.rank,
        'tier': r.tier.wire,
        'projected': r.projectedTier.wire,
      },
  ];

  List<Standing> _decodeRows(String json) => [
    for (final j in jsonDecode(json) as List)
      Standing(
        userId: j['user_id'] as String,
        handle: j['handle'] as String? ?? 'driver',
        displayName: j['display_name'] as String? ?? '',
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        trips: (j['trips'] as num?)?.toInt() ?? 0,
        rating: (j['rating'] as num?)?.toDouble(),
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        tier: LeagueTier.fromWire(j['tier'] as String?),
        projectedTier: LeagueTier.fromWire(j['projected'] as String?),
      ),
  ];
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final leaguesApiProvider = Provider<LeaguesApi?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : SupabaseLeaguesApi(client);
});

final leaguesRepoProvider = Provider<LeaguesRepo>((ref) {
  return LeaguesRepo(
    db: ref.watch(databaseProvider),
    api: ref.watch(leaguesApiProvider),
    outbox: ref.watch(outboxWorkerProvider),
    userId: () => ref.read(currentUserIdProvider),
  );
});

/// Cached snapshot, live. The screen calls [refreshMyLeaguesProvider] for a
/// cloud refresh.
final myLeaguesProvider = StreamProvider<List<League>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(leaguesRepoProvider).watchMyLeagues();
});

/// Fires a cloud refresh when first watched and whenever invalidated.
final refreshMyLeaguesProvider = FutureProvider<List<League>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(leaguesRepoProvider).refreshMyLeagues();
});

/// Runs the week-badge pass once per sign-in and whenever invalidated;
/// watched by the Leagues tab and the league screen (docs/02 §7).
final leagueWeekBadgesProvider = FutureProvider<int>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return 0;
  final engine = ref.read(badgesSyncProvider).engine;
  try {
    return await ref
        .watch(leaguesRepoProvider)
        .awardRecentWeekBadges(engine.award);
  } catch (e) {
    debugPrint('week badges: $e');
    return 0;
  }
});

/// The global league I sit in this week, if I joined the pool.
final myGlobalLeagueProvider = Provider<League?>((ref) {
  final leagues = ref.watch(myLeaguesProvider).value ?? const <League>[];
  for (final l in leagues) {
    if (l.isGlobal) return l;
  }
  return null;
});

final leagueMembersProvider = FutureProvider.family<List<LeagueMember>, String>(
  (ref, id) => ref.watch(leaguesRepoProvider).members(id),
);

final leagueCurrentWeekProvider = FutureProvider.family<WeekStandings, String>(
  (ref, id) => ref.watch(leaguesRepoProvider).currentWeek(id),
);

final leaguePastWeeksProvider =
    FutureProvider.family<List<WeekStandings>, String>(
      (ref, id) => ref.watch(leaguesRepoProvider).pastWeeks(id),
    );
