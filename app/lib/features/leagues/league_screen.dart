import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../data/badges/badges_sync.dart';
import '../../data/repos/leagues_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';
import 'invite_sheet.dart';
import 'widgets/standings_table.dart';
import 'widgets/tier_chip.dart';

/// One league: this week's table, past weeks, members, invite, hiding, leave.
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({super.key, required this.leagueId});

  final String leagueId;

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
  /// null = the running week; otherwise a finalised week start.
  DateTime? _selectedWeek;
  bool _badgesChecked = false;

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
    _awardWeekBadges(past.value, me);

    final WeekStandings? shown = _selectedWeek == null
        ? current.value
        : past.value?.where((w) => w.weekStart == _selectedWeek).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(league?.name ?? 'League'),
        actions: [
          if (league != null)
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
                const PopupMenuItem(
                  value: 'leave',
                  child: Text('Leave league'),
                ),
              ],
            ),
        ],
      ),
      body: SignedInScope(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(leagueCurrentWeekProvider(widget.leagueId));
            ref.invalidate(leaguePastWeeksProvider(widget.leagueId));
            ref.invalidate(leagueMembersProvider(widget.leagueId));
            await ref.read(leagueCurrentWeekProvider(widget.leagueId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (league != null && league.myHiding)
                _Banner(
                  icon: Icons.visibility_off_outlined,
                  text:
                      'You are hiding in this league. Members can see that '
                      'you are hiding; they cannot see your trips or roasts.',
                ),
              _WeekSwitcher(
                selected: _selectedWeek,
                current: current.value,
                past: past.value ?? const [],
                onSelect: (w) => setState(() => _selectedWeek = w),
              ),
              const SizedBox(height: 12),
              if (shown == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                StandingsTable(week: shown, me: me),
            ],
          ),
        ),
      ),
    );
  }

  /// Awards `league_week` and `promoted` once the finalised weeks are known.
  void _awardWeekBadges(List<WeekStandings>? weeks, String? me) {
    if (_badgesChecked || weeks == null || me == null) return;
    _badgesChecked = true;
    // Awards write to the database; keep that out of the build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final engine = ref.read(badgesSyncProvider).engine;
      for (final w in weeks) {
        final mine = w.rowFor(me);
        if (mine == null) continue;
        engine.award('league_week');
        if (mine.promotes) engine.award('promoted');
      }
    });
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
            content: const Text(
              'Your past weeks stay in the table. You can rejoin with the code.',
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
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final members = ref.watch(leagueMembersProvider(widget.leagueId));
          return SafeArea(
            child: members.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load members: $e'),
              ),
              data: (list) => ListView(
                shrinkWrap: true,
                children: [
                  for (final m in list)
                    ListTile(
                      leading: MemberAvatar(handle: m.handle, url: m.avatarUrl),
                      title: Text('@${m.handle}'),
                      subtitle: Text(
                        [
                          m.displayName,
                          if (m.rating != null)
                            'rating ${m.rating!.toStringAsFixed(0)}',
                          if (m.hiding) 'hiding',
                        ].where((s) => s.isNotEmpty).join(' · '),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (m.hiding)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.visibility_off_outlined),
                            ),
                          TierChip(tier: m.tier, dense: true),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push(Routes.userProfile(m.userId));
                      },
                    ),
                ],
              ),
            ),
          );
        },
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
            const SizedBox(width: 8),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
