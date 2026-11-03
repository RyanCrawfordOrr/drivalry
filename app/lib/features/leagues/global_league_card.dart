import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/leagues_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import 'widgets/tier_pill.dart';

/// The global league (docs/02 §12.4) as one tile: this week's place when
/// joined, else one sentence and one button. Matched by tier and Driver
/// Rating, never by speed.
class GlobalLeagueCard extends ConsumerStatefulWidget {
  const GlobalLeagueCard({super.key});

  @override
  ConsumerState<GlobalLeagueCard> createState() => _GlobalLeagueCardState();
}

class _GlobalLeagueCardState extends ConsumerState<GlobalLeagueCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final league = ref.watch(myGlobalLeagueProvider);
    final disc = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.public, color: scheme.onTertiaryContainer),
    );
    if (league != null) {
      final week = ref.watch(leagueCurrentWeekProvider(league.id)).value;
      final me = ref.watch(currentUserIdProvider);
      final mine = me == null ? null : week?.rowFor(me);
      final line = mine == null
          ? 'Drivers this week: ${league.memberCount}'
          : '#${mine.rank} of ${week!.rows.length} this week · ${mine.xp} XP';
      return Tile(
        onTap: () => context.push(Routes.league(league.id)),
        child: Row(
          children: [
            disc,
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    league.name,
                    style: context.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    line,
                    style: context.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            if (mine != null) ...[
              Pill('#${mine.rank}', tone: PillTone.primary, compact: true),
              const SizedBox(width: Space.xs),
            ],
            TierPill(tier: league.myTier),
          ],
        ),
      );
    }
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              disc,
              const SizedBox(width: Space.md),
              Text('Global league', style: context.title),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            'Up to 29 drivers at your tier, a new table every Monday.',
            style: context.bodyMuted,
          ),
          const SizedBox(height: Space.lg),
          SecondaryButton(
            label: _busy ? 'Joining…' : 'Join',
            onPressed: _busy ? null : _join,
          ),
        ],
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
