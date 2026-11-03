import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/stats/stats_engine.dart';
import '../../data/stats/stats_providers.dart';
import 'fun_facts.dart' show scoreText;

/// The Stats section of the owner's profile: a kicker, three all-time
/// numbers as tiles, and the doors to the full stats and the Season Wrapped.
class ProfileStatsCard extends ConsumerWidget {
  const ProfileStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(driverStatsProvider(StatsWindow.allTime)).value;
    final totals = stats?.totals ?? Totals.empty;
    final streak = stats?.records.currentCleanStreak ?? 0;
    void openStats() => context.push(Routes.stats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.md),
          child: Kicker('Stats'),
        ),
        StatGrid(
          children: [
            StatTile(
              value: '${totals.trips}',
              label: 'Trips',
              onTap: openStats,
            ),
            StatTile(
              value: scoreText(totals.averageScore),
              label: 'Average score',
              onTap: openStats,
            ),
            StatTile(value: '$streak', label: 'Clean streak', onTap: openStats),
          ],
        ),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            TextButton.icon(
              onPressed: openStats,
              icon: const Icon(Icons.query_stats),
              label: const Text('All stats'),
            ),
            TextButton.icon(
              onPressed: () => context.push(Routes.wrapped),
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Season Wrapped'),
            ),
          ],
        ),
      ],
    );
  }
}
