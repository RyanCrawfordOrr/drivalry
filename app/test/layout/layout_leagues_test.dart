// Layout audit for the Leagues area: the Leagues root, one league, duels,
// badges, seasons, stats and the Wrapped, plus their sheets and the
// celebration moment, each rendered at real phone sizes.
//
//   DRIVALRY_LAYOUT=1 flutter test test/layout/layout_leagues_test.dart
//   DRIVALRY_LAYOUT=1 DRIVALRY_LAYOUT_ONLY=duels-all,badges flutter test ...
//
// Opt-in like the scene audit: fonts come from the Flutter cache, which CI
// does not populate, so without DRIVALRY_LAYOUT the suite skips.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/badges/badge_defs.dart' show fallbackBadgeDefs;
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/challenges_repo.dart';
import 'package:drivalry/data/repos/duels_repo.dart';
import 'package:drivalry/data/repos/friends_repo.dart';
import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/data/stats/stats_providers.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/badges/badges_screen.dart';
import 'package:drivalry/features/badges/moment_ledger.dart';
import 'package:drivalry/features/leagues/challenges/new_challenge_sheet.dart';
import 'package:drivalry/features/leagues/create_league_screen.dart';
import 'package:drivalry/features/leagues/duels/duels_screen.dart';
import 'package:drivalry/features/leagues/duels/new_duel_sheet.dart';
import 'package:drivalry/features/leagues/invite_sheet.dart';
import 'package:drivalry/features/leagues/league_screen.dart';
import 'package:drivalry/features/leagues/leagues_screen.dart';
import 'package:drivalry/features/seasons/seasons_screen.dart';
import 'package:drivalry/features/stats/share_stats.dart';
import 'package:drivalry/features/stats/stats_screen.dart';
import 'package:drivalry/features/stats/wrapped_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../art/art_harness.dart';
import '../art/scenes/scene.dart';
import '../art/scenes/wrapped_scene.dart';
import '../support/scored_trips.dart';
import '../support/sqlite_support.dart';
import '../support/widget_support.dart';
import 'layout_audit.dart';

/// Comma-separated scene ids to render, for quick iteration. Empty = all.
const _onlyEnv = 'DRIVALRY_LAYOUT_ONLY';

Set<String> get _only => {
  for (final s in (Platform.environment[_onlyEnv] ?? '').split(','))
    if (s.trim().isNotEmpty) s.trim(),
};

/// The phone the owner tests real builds on: a tall Android with a 66 px
/// status bar and gesture navigation.
const ownerPhone = PhoneSize('android-large', 448, 997, top: 66, bottom: 24);

final List<PhoneSize> sizes = [...phoneSizes, ownerPhone];

void main() {
  setUpAll(() async {
    if (layoutShots) await loadArtFonts();
  });
  setUp(() => Haptics.enabled = false);
  final sqliteSkip = skipWithoutSqlite();
  for (final factory in _scenes) {
    final id = factory().id;
    if (_only.isNotEmpty && !_only.contains(id)) continue;
    for (final size in sizes) {
      testWidgets(
        '$id lays out on $size',
        (tester) async {
          final scene = factory();
          try {
            final app = await scene.build();
            final report = _withoutClippedText(
              tester,
              await auditLayout(
                tester,
                name: 'leagues-$id',
                app: app,
                size: size,
                settle: scene.settle,
                prepare: scene.prepare,
              ),
            );
            // Staggered lists schedule reveals up to 320 ms out; let every
            // timer fire before the tree goes away.
            await pumpFor(tester, const Duration(milliseconds: 400));
            await unmountAndSettle(tester);
            expect(report.blocking, isEmpty, reason: report.summary());
          } finally {
            await scene.dispose();
          }
        },
        skip: sqliteSkip != null || !layoutShots,
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}

/// Re-checks each overlap against the parts of both texts a scroll
/// viewport actually shows.
///
/// The audit measures every attached paragraph. A sliver list keeps the
/// rows just outside its viewport laid out (its cache extent), and rows
/// that scroll under a pinned app bar are painted and then covered, so
/// after a scroll both read as overlapping the title. Each paragraph is
/// clipped here to its sliver's visible band, from `overlap` (the pinned
/// extent above it) to `remainingPaintExtent`, while the tree is still
/// mounted; a pair whose visible parts no longer meet is dropped.
/// Everything else in the report stands.
LayoutReport _withoutClippedText(WidgetTester tester, LayoutReport report) {
  final visible = <String, Rect?>{};
  final seen = Set<RenderObject>.identity();
  for (final ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
    if (!seen.add(ro)) continue;
    final rect = MatrixUtils.transformRect(
      ro.getTransformTo(null),
      Offset.zero & ro.size,
    );
    final text = ro.text.toPlainText().replaceAll('\n', ' ').trim();
    visible['"${_short(text)}" ${_r(rect)}'] = _visiblePart(ro, rect);
  }
  final kept = <LayoutIssue>[];
  for (final issue in report.issues) {
    if (issue.kind == 'overlap') {
      final parts = [
        for (final e in visible.entries)
          if (issue.detail.contains(e.key)) e.value,
      ];
      if (parts.length == 2) {
        final a = parts[0], b = parts[1];
        if (a == null || b == null) continue;
        final x = a.intersect(b);
        if (x.width <= 2 || x.height <= 2) continue;
      }
    }
    kept.add(issue);
  }
  return LayoutReport(report.name, report.size, kept, report.pngPath);
}

/// The screen-space part of [ro] inside its sliver's visible band, null
/// when none of it shows, and the whole [rect] outside any sliver.
Rect? _visiblePart(RenderParagraph ro, Rect rect) {
  RenderSliver? sliver;
  for (var n = ro.parent; n != null; n = n.parent) {
    if (n is RenderSliver) {
      sliver = n;
      break;
    }
  }
  if (sliver == null) return rect;
  final c = sliver.constraints;
  if (axisDirectionToAxis(c.axisDirection) != Axis.vertical) return rect;
  final local = MatrixUtils.transformRect(
    ro.getTransformTo(sliver),
    Offset.zero & ro.size,
  );
  final band = Rect.fromLTRB(
    double.negativeInfinity,
    c.overlap,
    double.infinity,
    c.remainingPaintExtent,
  );
  final shown = local.intersect(band);
  if (shown.isEmpty) return null;
  return MatrixUtils.transformRect(sliver.getTransformTo(null), shown);
}

// Mirrors the audit's own formatting, so the strings match its details.
String _short(String s) => s.length <= 40 ? s : '${s.substring(0, 37)}...';
String _r(Rect r) =>
    '[${r.left.round()},${r.top.round()} ${r.width.round()}x'
    '${math.max(0, r.height.round())}]';

// ------------------------------------------------------------- scenes --

const _me = 'kai';

/// One screen state to audit. Built and disposed once per size.
abstract class _Scene {
  String get id;
  Duration get settle => const Duration(seconds: 2);
  Future<Widget> build();
  Future<void> prepare(WidgetTester tester) async {}
  Future<void> dispose() async {}
}

/// A screen over a fresh in-memory database seeded by [seed].
class _DbScene extends _Scene {
  _DbScene(
    this.id, {
    required this.home,
    this.seed,
    this.light = false,
    this.me = _me,
    this.clock,
    this.onPrepare,
    this.settle = const Duration(seconds: 2),
  });

  @override
  final String id;
  final Widget home;
  final Future<void> Function(AppDatabase db)? seed;
  final bool light;
  final String? me;

  /// Pinned "now" for the stats engine; null leaves the real clock.
  final DateTime Function()? clock;
  final Future<void> Function(WidgetTester tester)? onPrepare;
  @override
  final Duration settle;

  AppDatabase? _db;

  @override
  Future<Widget> build() async {
    final db = _db = memoryDatabase();
    await seed?.call(db);
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue(me),
        cloudConfiguredProvider.overrideWithValue(true),
        supabaseProvider.overrideWithValue(null),
        shareImageProvider.overrideWithValue(_noShare),
        if (clock != null) statsClockProvider.overrideWithValue(clock!),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: light ? ThemeMode.light : ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );
  }

  @override
  Future<void> prepare(WidgetTester tester) async {
    await onPrepare?.call(tester);
  }

  @override
  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}

/// A store scene reused as a layout state.
class _ArtSceneState extends _Scene {
  _ArtSceneState(this.id, this.scene);
  @override
  final String id;
  final ArtScene scene;
  @override
  Duration get settle => scene.settle;
  @override
  Future<Widget> build() => scene.build();
  @override
  Future<void> prepare(WidgetTester tester) => scene.prepare(tester);
  @override
  Future<void> dispose() => scene.dispose();
}

Future<void> _noShare({
  required Uint8List png,
  required String fileName,
  required String text,
}) async {}

/// An empty page that opens a sheet or a moment as soon as it is on screen,
/// so the overlay is audited over nothing but its own app bar.
class _OverlayHost extends ConsumerStatefulWidget {
  const _OverlayHost({required this.title, required this.open});
  final String title;
  final Future<void> Function(BuildContext context, WidgetRef ref) open;

  @override
  ConsumerState<_OverlayHost> createState() => _OverlayHostState();
}

class _OverlayHostState extends ConsumerState<_OverlayHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: const SizedBox.expand(),
  );
}

Future<void> _scrollBy(WidgetTester tester, Type scroller, double dy) async {
  await tester.drag(find.byType(scroller).first, Offset(0, -dy));
  await pumpFor(tester, const Duration(milliseconds: 600));
}

Future<void> _scrollTo(WidgetTester tester, String text, Type scroller) async {
  await tester.dragUntilVisible(
    find.text(text),
    find.byType(scroller).first,
    const Offset(0, -300),
  );
  await pumpFor(tester, const Duration(milliseconds: 600));
}

final List<_Scene Function()> _scenes = [
  // Leagues root.
  () => _DbScene(
    'root-empty',
    home: const LeaguesScreen(),
    seed: _seedSeasonTrips,
  ),
  () => _DbScene(
    'root-populated',
    home: const LeaguesScreen(),
    seed: _seedHub,
    settle: const Duration(seconds: 3),
  ),
  () => _DbScene(
    'root-populated-scrolled',
    home: const LeaguesScreen(),
    seed: _seedHub,
    settle: const Duration(seconds: 3),
    onPrepare: (t) => _scrollBy(t, CustomScrollView, 200),
  ),
  () => _DbScene(
    'root-populated-light',
    home: const LeaguesScreen(),
    seed: _seedHub,
    light: true,
    settle: const Duration(seconds: 3),
  ),
  () => _DbScene('root-signed-out', home: const LeaguesScreen(), me: null),
  // One league.
  () => _DbScene(
    'league-friend',
    home: const LeagueScreen(leagueId: _crewId),
    seed: _seedCrew,
    settle: const Duration(seconds: 3),
  ),
  () => _DbScene(
    'league-friend-light',
    home: const LeagueScreen(leagueId: _crewId),
    seed: _seedCrew,
    light: true,
    settle: const Duration(seconds: 3),
  ),
  () => _DbScene(
    'league-friend-scrolled',
    home: const LeagueScreen(leagueId: _crewId),
    seed: _seedCrew,
    settle: const Duration(seconds: 3),
    onPrepare: (t) => _scrollTo(t, 'RELEGATION ZONE', ListView),
  ),
  () => _DbScene(
    'league-global',
    home: const LeagueScreen(leagueId: _globalId),
    seed: _seedHub,
    settle: const Duration(seconds: 3),
  ),
  () => _DbScene(
    'league-members-sheet',
    home: _OverlayHost(
      title: 'Carpool Crew',
      open: (ctx, _) => showMembersSheet(ctx, _crewId),
    ),
    seed: _seedCrew,
  ),
  () => _DbScene(
    'league-add-sheet',
    home: _OverlayHost(title: 'Leagues', open: showAddLeagueSheet),
  ),
  () => _DbScene(
    'league-invite-sheet',
    home: _OverlayHost(
      title: 'Carpool Crew',
      open: (ctx, _) => showInviteSheet(ctx, _crewLeague()),
    ),
  ),
  () => _DbScene(
    'league-join-code-sheet',
    home: _OverlayHost(title: 'Leagues', open: joinLeagueByCode),
  ),
  () => _DbScene(
    'league-new-challenge-sheet',
    home: _OverlayHost(
      title: 'Carpool Crew',
      open: (ctx, _) => showNewChallengeSheet(ctx, _crewId),
    ),
    seed: _seedCrew,
  ),
  () => _DbScene('league-create', home: const CreateLeagueScreen()),
  // Duels.
  () => _DbScene(
    'duels-all',
    home: const DuelsScreen(),
    seed: _seedDuels,
    settle: const Duration(seconds: 3),
  ),
  () => _DbScene(
    'duels-all-scrolled',
    home: const DuelsScreen(),
    seed: _seedDuels,
    settle: const Duration(seconds: 3),
    onPrepare: (t) => _scrollTo(t, 'FINISHED', ListView),
  ),
  () => _DbScene('duels-empty', home: const DuelsScreen()),
  () => _DbScene(
    'duels-new-sheet',
    home: _OverlayHost(title: 'Duels', open: (ctx, _) => showNewDuelSheet(ctx)),
    seed: _seedFriends,
  ),
  // Badges.
  () => _DbScene(
    'badges',
    home: const BadgesScreen(),
    seed: _seedBadges,
    settle: const Duration(seconds: 3),
  ),
  () => _DbScene(
    'badges-scrolled',
    home: const BadgesScreen(),
    seed: _seedBadges,
    settle: const Duration(seconds: 3),
    onPrepare: (t) => _scrollTo(t, 'DISHONOURABLE', ListView),
  ),
  // Seasons.
  () =>
      _DbScene('seasons', home: const SeasonsScreen(), seed: _seedSeasonTrips),
  // Stats.
  () => _DbScene(
    'stats',
    home: const StatsScreen(),
    seed: _seedSeason,
    clock: () => _statsNow,
    settle: const Duration(seconds: 3),
  ),
  () => _DbScene(
    'stats-geography',
    home: const StatsScreen(),
    seed: _seedSeason,
    clock: () => _statsNow,
    settle: const Duration(seconds: 3),
    onPrepare: (t) async {
      await _scrollTo(t, 'GEOGRAPHY', ListView);
      await _scrollBy(t, ListView, 160);
    },
  ),
  () => _DbScene('stats-empty', home: const StatsScreen()),
  () => _DbScene(
    'stats-fuel-sheet',
    home: const _OverlayHost(title: 'Stats', open: showFuelAssumptionsSheet),
  ),
  // Wrapped: the store scene's season, on the intro and on card 2.
  () => _ArtSceneState('wrapped-intro', WrappedScene(card: -1)),
  () => _ArtSceneState('wrapped-card2', WrappedScene(card: 2)),
  () => _DbScene(
    'wrapped-empty',
    home: const WrappedScreen(),
    clock: () => _statsNow,
  ),
  // The celebration moment, from the kit, as the three Leagues screens
  // raise it.
  () => _DbScene(
    'moment-promoted',
    home: _OverlayHost(
      title: 'Leagues',
      open: (ctx, _) =>
          showCelebration(ctx, title: 'Promoted', verdict: 'Silver → Gold'),
    ),
  ),
  () => _DbScene(
    'moment-badge',
    home: _OverlayHost(
      title: 'Badges',
      open: (ctx, _) => showCelebration(
        ctx,
        title: 'Badge earned',
        verdict: 'Ten trips in a row without touching the phone.',
        badges: const ['Hands Off'],
      ),
    ),
  ),
  () => _DbScene(
    'moment-duel-won',
    home: _OverlayHost(
      title: 'Duels',
      open: (ctx, _) => showCelebration(
        ctx,
        title: 'Duel won',
        verdict: 'You beat @maya on phone-free trips',
        badges: const ['Sunday Driver'],
      ),
    ),
  ),
];

// -------------------------------------------------------------- seeds --

const _crewId = 'league-carpool-crew';
const _boysId = 'league-the-boys';
const _globalId = 'global-silver-12';

/// Late December, so the Wrapped season (Oct–Dec 2026) is the current one.
final DateTime _statsNow = DateTime(2026, 12, 29, 18);

typedef _Member = (String id, String name, LeagueTier tier, List<int> xps);

LeagueMember _member(String id, String name, LeagueTier tier) => LeagueMember(
  userId: id,
  handle: id,
  displayName: name,
  tier: tier,
  hiding: false,
);

/// The shape `LeaguesRepo` caches a week's rows in.
List<Map<String, Object?>> _encodeRows(List<Standing> rows) => [
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

/// Caches a league's members and this week's table from [members].
Future<List<Standing>> _seedWeek(
  AppDatabase db,
  String leagueId,
  List<_Member> members,
) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final weekStart = localWeekStart(DateTime.now());
  final list = [for (final m in members) _member(m.$1, m.$2, m.$3)];
  await db.cachePut(
    'league:$leagueId:members',
    jsonEncode([for (final m in list) m.toJson()]),
    nowMs,
  );
  final rows = computeStandings(list, [
    for (final m in members)
      for (final xp in m.$4) WeekSummary(userId: m.$1, xp: xp),
  ]);
  await db.cachePut(
    'league:$leagueId:week:${weekStartDate(weekStart)}',
    jsonEncode(_encodeRows(rows)),
    nowMs,
  );
  return rows;
}

const List<_Member> _crew = [
  ('priya', 'Priya', LeagueTier.gold, [92, 88, 81, 79, 72]),
  (_me, 'Kai', LeagueTier.silver, [96, 101, 95, 94]),
  ('sam', 'Sam', LeagueTier.silver, [90, 88, 84, 79]),
  ('jordan_rides_again', 'Jordan', LeagueTier.bronze, [91, 88, 83]),
  ('alex', 'Alex', LeagueTier.silver, [72, 68, 65]),
  ('maya', 'Maya', LeagueTier.bronze, [48]),
  ('theo', 'Theo', LeagueTier.bronze, [44]),
  ('nia', 'Nia', LeagueTier.learner, []),
];

League _crewLeague() => League(
  id: _crewId,
  name: 'Carpool Crew',
  kind: 'friend',
  inviteCode: 'CRPL2026',
  createdBy: 'priya',
  maxMembers: 30,
  createdAt: DateTime(2026, 9, 7),
  myTier: LeagueTier.silver,
  myHiding: false,
  memberCount: _crew.length,
);

League _boysLeague() => League(
  id: _boysId,
  name: 'The Boys',
  kind: 'friend',
  inviteCode: 'BOYS2026',
  createdBy: _me,
  maxMembers: 30,
  createdAt: DateTime(2026, 10, 12),
  myTier: LeagueTier.bronze,
  myHiding: true,
  memberCount: 4,
);

League _globalLeague() => League(
  id: _globalId,
  name: 'Global league',
  kind: 'global',
  inviteCode: '',
  createdBy: '',
  maxMembers: 30,
  createdAt: localWeekStart(DateTime.now()),
  myTier: LeagueTier.silver,
  myHiding: false,
  memberCount: 29,
);

/// Carpool Crew with eight members (so both zones show), a long handle, a
/// running challenge started by someone else and one finalised week.
Future<void> _seedCrew(AppDatabase db) async {
  final now = DateTime.now();
  final nowMs = now.millisecondsSinceEpoch;
  final weekStart = localWeekStart(now);
  final lastWeek = previousWeekStart(weekStart);
  await db.cachePut(
    'leagues:mine',
    jsonEncode([_crewLeague().toJson()]),
    nowMs,
  );
  await _seedWeek(db, _crewId, _crew);

  final byId = {for (final m in _crew) m.$1: _member(m.$1, m.$2, m.$3)};
  Standing past(String id, int rank, int xp, int trips, LeagueTier from) {
    final m = byId[id]!;
    return Standing(
      userId: m.userId,
      handle: m.handle,
      displayName: m.displayName,
      xp: xp,
      trips: trips,
      rating: null,
      rank: rank,
      tier: from,
      projectedTier: m.tier,
    );
  }

  await db.cachePut(
    'league:$_crewId:weeks',
    jsonEncode([
      {
        'week_start': weekStartDate(lastWeek),
        'rows': _encodeRows([
          past('priya', 1, 388, 5, LeagueTier.silver),
          past('sam', 2, 352, 4, LeagueTier.bronze),
          past(_me, 3, 340, 4, LeagueTier.bronze),
          past('alex', 4, 231, 3, LeagueTier.bronze),
          past('jordan_rides_again', 5, 174, 2, LeagueTier.learner),
          past('maya', 6, 0, 0, LeagueTier.silver),
          past('theo', 7, 0, 0, LeagueTier.silver),
          past('nia', 8, 0, 0, LeagueTier.bronze),
        ]),
      },
    ]),
    nowMs,
  );

  final challenge = GroupChallenge(
    id: 'challenge-clean-sweep',
    leagueId: _crewId,
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
    'league:$_crewId:challenges',
    jsonEncode([challenge.toJson()]),
    nowMs,
  );
  await db.cachePut(
    'challenge:${challenge.id}:progress',
    jsonEncode({
      'value': 17,
      'needed': 25,
      'target': 25,
      'members': _crew.length,
      'met': false,
      'per_member': <Object>[],
    }),
    nowMs,
  );
}

/// The Leagues root with everything on it: a global league I am in, two
/// friend leagues, one challenge waiting for an answer, two badges, a
/// season with trips.
Future<void> _seedHub(AppDatabase db) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  await _seedCrew(db);
  await db.cachePut(
    'leagues:mine',
    jsonEncode([
      _globalLeague().toJson(),
      _crewLeague().toJson(),
      _boysLeague().toJson(),
    ]),
    nowMs,
  );
  await _seedWeek(db, _boysId, const [
    ('dev', 'Dev', LeagueTier.bronze, [88, 84, 80]),
    (_me, 'Kai', LeagueTier.bronze, [96, 90]),
    ('marco', 'Marco', LeagueTier.bronze, [70, 66]),
    ('ben', 'Ben', LeagueTier.learner, [52]),
  ]);
  // Twenty-nine strangers at my tier; I sit fourth.
  const names = [
    'Avery', 'Blake', 'Casey', 'Drew', 'Ellis', 'Finley', 'Gray', 'Harper',
    'Indy', 'Jules', 'Kit', 'Lane', 'Morgan', 'Noor', 'Oakley', 'Parker',
    'Quinn', 'Reese', 'Sage', 'Tate', 'Uma', 'Vale', 'Wren', 'Xan', 'Yael',
    'Zion', 'Ash', 'Bo', //
  ];
  await _seedWeek(db, _globalId, [
    for (var i = 0; i < names.length; i++)
      (
        names[i].toLowerCase(),
        names[i],
        LeagueTier.silver,
        [for (var t = 0; t < 4; t++) 100 - i * 3 - t * 2],
      ),
    (_me, 'Kai', LeagueTier.silver, [92, 92, 90, 90]),
  ]);
  await _seedDuel(db, [_incomingDuel()]);
  await db.awardBadge(
    'first_trip',
    DateTime(2026, 10, 20, 18).millisecondsSinceEpoch,
  );
  await db.awardBadge(
    'clean_5',
    DateTime(2026, 11, 1, 18).millisecondsSinceEpoch,
  );
  await _seedSeasonTrips(db);
}

/// Marks every badge moment as already shown. Seeded trips earn badges the
/// moment the screen opens, and the celebration would otherwise cover it.
Future<void> _quietBadges(AppDatabase db) async {
  final ledger = MomentLedger(db);
  for (final def in fallbackBadgeDefs) {
    await ledger.claim('badge:${def.id}');
  }
}

// ---- duels

DuelParty _party(String id, String name) =>
    DuelParty(userId: id, handle: id, displayName: name);

Duel _incomingDuel() => Duel(
  id: 'duel-in',
  challenger: _party('sam', 'Sam'),
  opponent: _party(_me, 'Kai'),
  metric: DuelMetric.xp,
  status: DuelStatus.pending,
  createdAt: DateTime.now().subtract(const Duration(hours: 20)),
);

Future<void> _seedDuel(AppDatabase db, List<Duel> duels) => db.cachePut(
  'duels:mine',
  jsonEncode([for (final d in duels) d.toJson()]),
  DateTime.now().millisecondsSinceEpoch,
);

/// All four sections: one to answer, one running with a scoreboard, one
/// sent, one won (badge still to pick) and one lost.
Future<void> _seedDuels(AppDatabase db) async {
  final now = DateTime.now();
  final nowMs = now.millisecondsSinceEpoch;
  await _seedDuel(db, [
    _incomingDuel(),
    Duel(
      id: 'duel-run',
      challenger: _party(_me, 'Kai'),
      opponent: _party('priya', 'Priya'),
      metric: DuelMetric.phoneFree,
      status: DuelStatus.active,
      createdAt: now.subtract(const Duration(days: 3)),
      startsAt: now.subtract(const Duration(days: 3)),
      endsAt: now.add(const Duration(days: 4, hours: 3)),
    ),
    Duel(
      id: 'duel-sent',
      challenger: _party(_me, 'Kai'),
      opponent: _party('alex', 'Alex'),
      metric: DuelMetric.scoreAvg,
      status: DuelStatus.pending,
      createdAt: now.subtract(const Duration(hours: 2)),
    ),
    Duel(
      id: 'duel-won',
      challenger: _party(_me, 'Kai'),
      opponent: _party('maya', 'Maya'),
      metric: DuelMetric.xp,
      status: DuelStatus.finished,
      createdAt: now.subtract(const Duration(days: 10)),
      startsAt: now.subtract(const Duration(days: 9)),
      endsAt: now.subtract(const Duration(days: 2)),
      finishedAt: now.subtract(const Duration(days: 2)),
      challengerValue: 420,
      opponentValue: 310,
      challengerTrips: 6,
      opponentTrips: 4,
      winnerId: _me,
    ),
    Duel(
      id: 'duel-lost',
      challenger: _party('jordan_rides_again', 'Jordan'),
      opponent: _party(_me, 'Kai'),
      metric: DuelMetric.scoreAvg,
      status: DuelStatus.finished,
      createdAt: now.subtract(const Duration(days: 14)),
      startsAt: now.subtract(const Duration(days: 12)),
      endsAt: now.subtract(const Duration(days: 5)),
      finishedAt: now.subtract(const Duration(days: 5)),
      challengerValue: 91.2,
      opponentValue: 86.5,
      challengerTrips: 5,
      opponentTrips: 4,
      winnerId: 'jordan_rides_again',
      loserBadgeId: 'lead_foot',
    ),
  ]);
  await db.cachePut(
    'duel:duel-run:board',
    jsonEncode({'c': 4, 'ct': 4, 'o': 3, 'ot': 3}),
    nowMs,
  );
  // The win was celebrated when it landed; the screen shows the list.
  await MomentLedger(db).claim('duel:duel-won');
}

Future<void> _seedFriends(AppDatabase db) => db.cachePut(
  FriendsRepo.cacheKey,
  jsonEncode(
    const FriendsSnapshot(
      friends: [
        FriendProfile(id: 'priya', handle: 'priya', displayName: 'Priya'),
        FriendProfile(id: 'sam', handle: 'sam', displayName: 'Sam'),
        FriendProfile(
          id: 'jordan_rides_again',
          handle: 'jordan_rides_again',
          displayName: 'Jordan',
        ),
        FriendProfile(id: 'maya', handle: 'maya', displayName: ''),
      ],
    ).toJson(),
  ),
  DateTime.now().millisecondsSinceEpoch,
);

// ---- badges

/// Three earned badges, a twelve-trip clean streak with the phone picked up
/// seven trips ago, and one shame badge worn now. No moment: the screen
/// shows the list.
Future<void> _seedBadges(AppDatabase db) async {
  await _quietBadges(db);
  for (final (id, month, day) in [
    ('perfect_100', 10, 29),
    ('clean_5', 10, 24),
    ('first_trip', 10, 12),
  ]) {
    await db.awardBadge(
      id,
      DateTime(2026, month, day, 18).millisecondsSinceEpoch,
    );
  }
  await db.awardBadge(
    'lead_foot',
    DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
  );
  final newest = DateTime(2026, 11, 2, 17, 40);
  for (var i = 0; i < 16; i++) {
    await seedScoredTrip(
      db,
      id: 'streak-$i',
      startedAt: newest.subtract(Duration(days: i)).millisecondsSinceEpoch,
      score: switch (i) {
        3 => 100,
        12 => 71,
        _ => 84 + (i * 7) % 15,
      },
      phoneHandling: i == 7,
      packRegion: 'us-tn',
    );
  }
}

// ---- seasons and stats

/// A handful of October trips, so the season hero has numbers.
Future<void> _seedSeasonTrips(AppDatabase db) async {
  await _quietBadges(db);
  for (var i = 0; i < 6; i++) {
    await seedScoredTrip(
      db,
      id: 'season-trip-$i',
      startedAt: DateTime(2026, 10, 6 + i * 4, 8).millisecondsSinceEpoch,
      score: 82 + i * 2,
      xp: 55 + i * 3,
      packRegion: 'us-tn',
    );
  }
}

typedef _Trip = ({
  int day,
  int hour,
  int score,
  double km,
  double night,
  String weather,
  String region,
  bool away,
});

/// Day 0 is 1 October 2026: commutes, errands and four weekends out of
/// state. Fictional throughout.
const List<_Trip> _season = [
  (
    day: 1,
    hour: 7,
    score: 88,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 1,
    hour: 17,
    score: 84,
    km: 10.2,
    night: 0.1,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 3,
    hour: 14,
    score: 92,
    km: 64,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 5,
    hour: 18,
    score: 79,
    km: 10.2,
    night: 0.2,
    weather: 'rain',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 8,
    hour: 21,
    score: 86,
    km: 14,
    night: 1,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 10,
    hour: 9,
    score: 90,
    km: 285,
    night: 0,
    weather: 'clear',
    region: 'us-ky',
    away: true,
  ),
  (
    day: 11,
    hour: 16,
    score: 83,
    km: 290,
    night: 0.35,
    weather: 'clear',
    region: 'us-ky',
    away: true,
  ),
  (
    day: 13,
    hour: 17,
    score: 58,
    km: 10.2,
    night: 0.15,
    weather: 'rain',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 18,
    hour: 7,
    score: 89,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 24,
    hour: 15,
    score: 87,
    km: 390,
    night: 0.25,
    weather: 'clear',
    region: 'us-ga',
    away: true,
  ),
  (
    day: 26,
    hour: 10,
    score: 81,
    km: 240,
    night: 0,
    weather: 'rain',
    region: 'us-al',
    away: true,
  ),
  (
    day: 33,
    hour: 7,
    score: 90,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 36,
    hour: 22,
    score: 88,
    km: 31,
    night: 1,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 44,
    hour: 8,
    score: 89,
    km: 310,
    night: 0,
    weather: 'clear',
    region: 'us-nc',
    away: true,
  ),
  (
    day: 48,
    hour: 18,
    score: 93,
    km: 10.2,
    night: 0.7,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 62,
    hour: 7,
    score: 96,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 70,
    hour: 18,
    score: 85,
    km: 10.2,
    night: 0.9,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 79,
    hour: 9,
    score: 90,
    km: 48,
    night: 0,
    weather: 'snow',
    region: 'us-tn',
    away: false,
  ),
  (
    day: 88,
    hour: 7,
    score: 95,
    km: 9.6,
    night: 0,
    weather: 'clear',
    region: 'us-tn',
    away: false,
  ),
];

/// A whole season for the stats engine, with the per-trip aggregates the
/// finaliser would have written so the screen settles in one pass.
Future<void> _seedSeason(AppDatabase db) async {
  await _quietBadges(db);
  final seasonStart = DateTime(2026, 10, 1);
  const home = (lat: 36.1200, lon: -86.7900);
  const work = (lat: 36.1620, lon: -86.7810);
  await db
      .into(db.places)
      .insert(
        PlacesCompanion.insert(
          id: 'home',
          label: 'Home',
          kind: const Value('home'),
          lat: home.lat,
          lon: home.lon,
          createdAt: seasonStart.millisecondsSinceEpoch,
        ),
      );
  for (var i = 0; i < _season.length; i++) {
    final s = _season[i];
    final id = 'season-$i';
    final startedAt = seasonStart
        .add(Duration(days: s.day, hours: s.hour))
        .millisecondsSinceEpoch;
    final highway = s.km > 60;
    final movingS = s.km / (highway ? 95 : 30) * 3600;
    await seedScoredTrip(
      db,
      id: id,
      startedAt: startedAt,
      score: s.score,
      xp: (s.score * 0.6).round() + (highway ? 20 : 0),
      phoneHandling: s.score < 70,
      nightFraction: s.night,
      weather: s.weather,
      packRegion: s.region,
      distanceM: s.km * 1000,
      movingS: movingS,
    );
    final end = s.away
        ? (lat: 34.5 + 0.08 * i, lon: -84.0 - 0.06 * i)
        : (i.isEven ? work : home);
    await db.updateTrip(
      id,
      TripsCompanion(
        minLat: Value(home.lat < end.lat ? home.lat : end.lat),
        maxLat: Value(home.lat < end.lat ? end.lat : home.lat),
        minLon: Value(home.lon < end.lon ? home.lon : end.lon),
        maxLon: Value(home.lon < end.lon ? end.lon : home.lon),
        maxAltitudeM: Value(s.region == 'us-nc' ? 1980.0 : 210.0 + i),
        startLat: Value(home.lat),
        startLon: Value(home.lon),
        endLat: Value(end.lat),
        endLon: Value(end.lon),
        roadNames: Value(
          s.away ? '["I-24","I-65","I-40"]' : '["Broadway","West End Ave"]',
        ),
        statsAt: Value(startedAt + 1),
      ),
    );
  }
}
