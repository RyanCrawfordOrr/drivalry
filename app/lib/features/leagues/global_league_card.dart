import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/leagues_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import 'widgets/tier_chip.dart';

/// The global league (docs/02 §12.4): this week's table when joined, else a
/// join button. Matched by tier and Driver Rating, never by speed.
class GlobalLeagueCard extends ConsumerStatefulWidget {
  const GlobalLeagueCard({super.key});

  @override
  ConsumerState<GlobalLeagueCard> createState() => _GlobalLeagueCardState();
}

class _GlobalLeagueCardState extends ConsumerState<GlobalLeagueCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final league = ref.watch(myGlobalLeagueProvider);
    if (league != null) {
      final week = ref.watch(leagueCurrentWeekProvider(league.id)).value;
      final me = ref.watch(currentUserIdProvider);
      final mine = me == null ? null : week?.rowFor(me);
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => context.push(Routes.league(league.id)),
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.tertiaryContainer,
            child: Icon(
              Icons.public,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          title: Text(league.name),
          subtitle: Text(
            [
              '${league.memberCount} driver${league.memberCount == 1 ? '' : 's'}',
              if (mine != null)
                '#${mine.rank} of ${week!.rows.length} · ${mine.xp} XP',
              'reshuffles Monday',
            ].join(' · '),
          ),
          trailing: TierChip(tier: league.myTier, dense: true),
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.public, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Global league', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Get matched every Monday with up to 29 drivers at your tier. '
              'Same rules as a friend league: XP ranks, Driver Rating breaks '
              'ties, top five move up, bottom five move down. Never by speed.',
              style: theme.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : _join,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: const Text('Join the global league'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final id = await ref.read(leaguesRepoProvider).joinGlobalLeague();
      if (mounted) context.push(Routes.league(id));
    } on LeagueJoinException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
