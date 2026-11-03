import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/stats/stats_engine.dart';
import '../../data/stats/stats_providers.dart';
import 'fun_facts.dart' show scoreText;

/// The Stats section of the owner's profile: three all-time numbers and the
/// doors to the full stats and the Season Wrapped.
class ProfileStatsCard extends ConsumerWidget {
  const ProfileStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(driverStatsProvider(StatsWindow.allTime)).value;
    final theme = Theme.of(context);
    final totals = stats?.totals ?? Totals.empty;
    final streak = stats?.records.currentCleanStreak ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Stats', style: theme.textTheme.labelLarge),
        ),
        Row(
          children: [
            Expanded(
              child: _Number(label: 'Trips', value: '${totals.trips}'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Number(
                label: 'Average score',
                value: scoreText(totals.averageScore),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Number(label: 'Clean streak', value: '$streak'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push(Routes.stats),
                icon: const Icon(Icons.query_stats),
                label: const Text('All stats'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => context.push(Routes.wrapped),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Season Wrapped'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Number extends StatelessWidget {
  const _Number({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(value, style: theme.textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}
