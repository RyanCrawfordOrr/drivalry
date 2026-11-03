import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/leagues_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/signed_in_scope.dart';
import 'challenges/challenge_card.dart';
import 'invite_sheet.dart';
import 'promotion_moments.dart';
import 'widgets/live_numbers.dart';
import 'widgets/standings_table.dart';
import 'widgets/tier_pill.dart';

/// One league: a hero with the name, the week countdown and your rank and
/// XP, the challenge tile, then the standings. Past weeks, members, invite,
/// hiding and leave stay in the app bar.
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
  /// null = the running week; otherwise a finalised week start.
  DateTime? _selectedWeek;

  @override
  Widget build(BuildContext context) {
    final leagues = ref.watch(myLeaguesProvider).value ?? const <League>[];
    League? league;
    for (final l in leagues) {
      if (l.id == widget.leagueId) league = l;
    }
    final me = ref.watch(currentUserIdProvider);
    final current = ref.watch(leagueCurrentWeekProvider(widget.leagueId));
    final past = ref.watch(leaguePastWeeksProvider(widget.leagueId));
    // Week badges come from `league_weeks` directly, so they do not depend
    // on this league still existing (a global one is closed every Monday).
    ref.watch(leagueWeekBadgesProvider);

    final WeekStandings? shown = _selectedWeek == null
        ? current.value
        : past.value?.where((w) => w.weekStart == _selectedWeek).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (league != null && !league.isGlobal)
            IconButton(
              tooltip: 'Invite',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: () => showInviteSheet(context, league!),
            ),
          IconButton(
            tooltip: 'Members',
            icon: const Icon(Icons.people_outline),
            onPressed: () => _showMembers(context),
          ),
          if (league != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => _onMenu(v, league!),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'hiding',
                  child: Text(
                    league!.myHiding
                        ? 'Show my trips here'
                        : 'Hide my trips here',
                  ),
                ),
                PopupMenuItem(
                  value: 'leave',
                  child: Text(
                    league.isGlobal ? 'Leave global league' : 'Leave league',
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SignedInScope(
        child: PromotionMoments(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(leagueCurrentWeekProvider(widget.leagueId));
              ref.invalidate(leaguePastWeeksProvider(widget.leagueId));
              ref.invalidate(leagueMembersProvider(widget.leagueId));
              await ref.read(leagueCurrentWeekProvider(widget.leagueId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.xxxl,
              ),
              children: [
                Reveal(
                  child: _Hero(
                    name: league?.name ?? 'League',
                    week: shown,
                    me: me,
                    notes: [
                      if (league != null && league.myHiding)
                        'You are hiding here. Others see that, not your trips.',
                      if (league != null && league.isGlobal)
                        'Matched by tier and Driver Rating. New table every '
                            'Monday.',
                    ],
                  ),
                ),
                const SizedBox(height: Space.xl),
                // Global leagues are rebuilt weekly; a challenge needs a
                // table that outlives the week (docs/02 §12.2).
                if (league != null && !league.isGlobal) ...[
                  ChallengeCard(leagueId: widget.leagueId),
                  const SizedBox(height: Space.xl),
                ],
                _WeekSwitcher(
                  selected: _selectedWeek,
                  current: current.value,
                  past: past.value ?? const [],
                  onSelect: (w) => setState(() => _selectedWeek = w),
                ),
                const SizedBox(height: Space.lg),
                if (shown == null)
                  const Column(
                    children: [
                      SkeletonTile(height: 56),
                      SizedBox(height: Space.md),
                      SkeletonTile(height: 56),
                      SizedBox(height: Space.md),
                      SkeletonTile(height: 56),
                    ],
                  )
                else
                  StandingsTable(week: shown, me: me),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(String value, League league) async {
    final repo = ref.read(leaguesRepoProvider);
    switch (value) {
      case 'hiding':
        await repo.setHiding(league.id, !league.myHiding);
        ref.invalidate(leagueMembersProvider(league.id));
      case 'leave':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Leave ${league.name}?'),
            content: Text(
              league.isGlobal
                  ? 'You leave the global pool too. Rejoin any time; your '
                        'tier is kept.'
                  : 'You can rejoin with the invite code any time.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Leave'),
              ),
            ],
          ),
        );
        if (ok == true) {
          await repo.leave(league.id);
          if (mounted) context.go(Routes.leagues);
        }
    }
  }

  Future<void> _showMembers(BuildContext context) {
    return showDrivalrySheet<void>(
      context,
      title: 'Members',
      scrollable: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final members = ref.watch(leagueMembersProvider(widget.leagueId));
          return members.when(
            loading: () => const Column(
              children: [
                SkeletonTile(height: 56),
                SizedBox(height: Space.md),
                SkeletonTile(height: 56),
              ],
            ),
            error: (e, _) => Text(
              friendlyError(e, doing: 'load the members'),
              style: ctx.bodyMuted,
            ),
            data: (list) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in list) ...[
                  _MemberRow(
                    member: m,
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push(Routes.userProfile(m.userId));
                    },
                  ),
                  const SizedBox(height: Space.sm),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// League name, the week's countdown and your two numbers.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.name,
    required this.week,
    required this.me,
    this.notes = const [],
  });

  final String name;
  final WeekStandings? week;
  final String? me;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final w = week;
    final mine = me == null ? null : w?.rowFor(me!);
    final String sub;
    if (w == null) {
      sub = 'Loading this week';
    } else if (w.finalized) {
      sub = 'Week of ${DateFormat.MMMd().format(w.weekStart)} · final';
    } else {
      final left =
          (nextWeekStart(w.weekStart).difference(DateTime.now()).inHours / 24)
              .ceil()
              .clamp(0, 7);
      final days = left == 1 ? '1 day' : '$left days';
      sub = 'Closes Sunday night · $days left';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: context.headline),
        const SizedBox(height: Space.xs),
        Text(sub, style: context.caption),
        for (final note in notes) ...[
          const SizedBox(height: Space.xs),
          Text(note, style: context.caption),
        ],
        const SizedBox(height: Space.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CountingHero(
              kicker: 'Your rank',
              value: mine?.rank,
              prefix: '#',
              caption: w == null ? null : 'of ${w.rows.length}',
            ),
            const SizedBox(width: Space.xxl),
            CountingHero(
              kicker: 'Your XP',
              value: mine?.xp,
              unit: 'XP',
              caption: mine == null
                  ? null
                  : '${mine.trips} trip${mine.trips == 1 ? '' : 's'}',
            ),
          ],
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});
  final LeagueMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = member;
    final name = m.displayName.isNotEmpty ? m.displayName : m.handle;
    final caption = [
      if (m.displayName.isNotEmpty) m.displayName,
      if (m.rating != null) 'Driver Rating ${m.rating!.toStringAsFixed(0)}',
    ].join(' · ');
    return InkWell(
      onTap: () {
        Haptics.tap();
        onTap();
      },
      borderRadius: Radii.tileRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            Avatar(
              name: name,
              image: m.avatarUrl == null ? null : NetworkImage(m.avatarUrl!),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${m.handle}', style: context.body),
                  if (caption.isNotEmpty)
                    Text(
                      caption,
                      style: context.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (m.hiding) ...[
              const Pill(
                'Hiding',
                icon: Icons.visibility_off_outlined,
                compact: true,
              ),
              const SizedBox(width: Space.sm),
            ],
            TierPill(tier: m.tier),
          ],
        ),
      ),
    );
  }
}

class _WeekSwitcher extends StatelessWidget {
  const _WeekSwitcher({
    required this.selected,
    required this.current,
    required this.past,
    required this.onSelect,
  });

  final DateTime? selected;
  final WeekStandings? current;
  final List<WeekStandings> past;
  final ValueChanged<DateTime?> onSelect;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.MMMd();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('This week'),
            selected: selected == null,
            onSelected: (_) => onSelect(null),
          ),
          for (final w in past) ...[
            const SizedBox(width: Space.sm),
            ChoiceChip(
              label: Text('Week of ${fmt.format(w.weekStart)}'),
              selected: selected == w.weekStart,
              onSelected: (_) => onSelect(w.weekStart),
            ),
          ],
        ],
      ),
    );
  }
}
