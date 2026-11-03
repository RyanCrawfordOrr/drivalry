import 'dart:convert';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/challenges_repo.dart';
import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/leagues/league_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/sqlite_support.dart';
import '../art_harness.dart';
import 'scene.dart';

/// `03-league`: the real [LeagueScreen] over a seeded friend league.
///
/// The league screens read the cloud through the drift `remote_cache` table,
/// the phone's mirror of the Supabase rows (`leagues`, `league_members`,
/// `trip_summaries` folded into standings, `league_weeks`,
/// `group_challenges`). Seeding that table under the repo's own keys, with
/// no Supabase client, makes every provider serve the seeded week exactly as
/// it would offline.
class LeagueScene extends ArtScene {
  static const _me = 'kai';
  static const _leagueId = 'league-carpool-crew';

  AppDatabase? _db;

  @override
  String get id => '03-league';

  @override
  String get headline => 'Weekly leagues with your friends.';

  @override
  String get subline =>
      'Smooth, legal driving climbs the table. Monday resets it.';

  @override
  Duration get settle => const Duration(seconds: 3);

  @override
  Future<Widget> build() async {
    final db = _db = memoryDatabase();
    await _seed(db);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(_me),
        cloudConfiguredProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const LeagueScreen(leagueId: _leagueId),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _seed(AppDatabase db) async {
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final weekStart = localWeekStart(now);
    final lastWeek = previousWeekStart(weekStart);

    // Tier at the start of this week. Driver Rating (the tie-breaker) is
    // left null: with it the row subtitle wraps to two lines at phone width,
    // and the table ranks on XP alone here anyway.
    final members = [
      _member('priya', 'Priya', LeagueTier.gold),
      _member(_me, 'Kai', LeagueTier.silver),
      _member('sam', 'Sam', LeagueTier.silver),
      _member('jordan', 'Jordan', LeagueTier.bronze),
      _member('alex', 'Alex', LeagueTier.silver),
      _member('maya', 'Maya', LeagueTier.bronze),
    ];
    final byId = {for (final m in members) m.userId: m};

    final league = League(
      id: _leagueId,
      name: 'Carpool Crew',
      kind: 'friend',
      inviteCode: 'CRPL2026',
      createdBy: 'priya',
      maxMembers: 30,
      createdAt: DateTime(2026, 9, 7),
      myTier: LeagueTier.silver,
      myHiding: false,
      memberCount: members.length,
    );
    await db.cachePut('leagues:mine', jsonEncode([league.toJson()]), nowMs);
    await db.cachePut(
      'league:$_leagueId:members',
      jsonEncode([for (final m in members) m.toJson()]),
      nowMs,
    );

    // This week: one summary per scored trip, ranked the way the repo ranks
    // them (XP, then rating), which puts me second.
    const tripXp = {
      'priya': [92, 88, 81, 79, 72],
      _me: [96, 101, 95, 94],
      'sam': [90, 88, 84, 79],
      'jordan': [91, 88, 83],
      'alex': [72, 68, 65],
      'maya': [48],
    };
    final rows = computeStandings(members, [
      for (final MapEntry(key: uid, value: xps) in tripXp.entries)
        for (final xp in xps) WeekSummary(userId: uid, xp: xp),
    ]);
    await db.cachePut(
      'league:$_leagueId:week:${weekStartDate(weekStart)}',
      jsonEncode(_encodeRows(rows)),
      nowMs,
    );

    // Last week, finalised: the tiers it handed out are the ones above.
    final past = [
      _past(byId['priya']!, 1, xp: 388, trips: 5, from: LeagueTier.silver),
      _past(byId['sam']!, 2, xp: 352, trips: 4, from: LeagueTier.bronze),
      _past(byId[_me]!, 3, xp: 340, trips: 4, from: LeagueTier.bronze),
      _past(byId['alex']!, 4, xp: 231, trips: 3, from: LeagueTier.bronze),
      _past(byId['jordan']!, 5, xp: 174, trips: 2, from: LeagueTier.learner),
      _past(byId['maya']!, 6, xp: 0, trips: 0, from: LeagueTier.silver),
    ];
    await db.cachePut(
      'league:$_leagueId:weeks',
      jsonEncode([
        {'week_start': weekStartDate(lastWeek), 'rows': _encodeRows(past)},
      ]),
      nowMs,
    );

    // A running group challenge, started by someone else so the card shows
    // no "call off" button. Progress is the cloud's cached answer.
    final challenge = GroupChallenge(
      id: 'challenge-clean-sweep',
      leagueId: _leagueId,
      createdBy: 'priya',
      goal: ChallengeGoal.cleanTrips,
      target: 25,
      startsAt: weekStart,
      endsAt: nextWeekStart(
        nextWeekStart(weekStart),
      ).subtract(const Duration(minutes: 1)),
      status: 'active',
    );
    await db.cachePut(
      'league:$_leagueId:challenges',
      jsonEncode([challenge.toJson()]),
      nowMs,
    );
    await db.cachePut(
      'challenge:${challenge.id}:progress',
      jsonEncode({
        'value': 17,
        'needed': 25,
        'target': 25,
        'members': members.length,
        'met': false,
        'per_member': <Object>[],
      }),
      nowMs,
    );
  }

  static LeagueMember _member(String id, String name, LeagueTier tier) =>
      LeagueMember(
        userId: id,
        handle: id,
        displayName: name,
        tier: tier,
        hiding: false,
      );

  /// A finalised row: [from] is the tier before, the member's current tier is
  /// what the week left them with.
  static Standing _past(
    LeagueMember m,
    int rank, {
    required int xp,
    required int trips,
    required LeagueTier from,
  }) => Standing(
    userId: m.userId,
    handle: m.handle,
    displayName: m.displayName,
    xp: xp,
    trips: trips,
    rating: m.rating,
    rank: rank,
    tier: from,
    projectedTier: m.tier,
  );

  /// The shape `LeaguesRepo` caches a week's rows in.
  static List<Map<String, Object?>> _encodeRows(List<Standing> rows) => [
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
}
