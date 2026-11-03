import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/badges/badges_providers.dart';
import '../../data/badges/streaks.dart';

/// Earned and locked badges, plus the two streaks. Shame badges sit apart.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(myBadgesProvider);
    final streaks = ref.watch(streaksProvider).value ?? Streaks.none;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Badges')),
      body: badges.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load badges: $e')),
        data: (list) {
          final regular = list.where((b) => !b.def.isShame).toList();
          final shame = list.where((b) => b.def.isShame).toList();
          final earnedCount = regular.where((b) => b.earned).length;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StreakRow(streaks: streaks),
              const SizedBox(height: 16),
              Text(
                '$earnedCount of ${regular.length} earned',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final b in regular) _BadgeTile(badge: b),
              if (shame.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Dishonourable',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Handed out by duels and reckless trips. They wear off.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final b in shame) _BadgeTile(badge: b, muted: true),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StreakRow extends StatelessWidget {
  const _StreakRow({required this.streaks});
  final Streaks streaks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget stat(String value, String label, IconData icon) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 4),
              Text(value, style: theme.textTheme.headlineSmall),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        stat('${streaks.clean}', 'clean streak', Icons.verified_outlined),
        const SizedBox(width: 8),
        stat(
          '${streaks.phoneFree}',
          'phone-free streak',
          Icons.phonelink_erase_outlined,
        ),
        const SizedBox(width: 8),
        stat('+${streaks.bonusXp}', 'streak XP', Icons.bolt_outlined),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, this.muted = false});
  final MyBadge badge;
  final bool muted;

  IconData get _icon => switch (badge.def.category) {
    'exploration' => Icons.explore_outlined,
    'social' => Icons.people_outline,
    'season' => Icons.calendar_month_outlined,
    'shame' => Icons.sentiment_very_dissatisfied_outlined,
    _ => Icons.shield_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final earned = badge.earned;
    final color = !earned || muted
        ? theme.colorScheme.outline
        : theme.colorScheme.primary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: earned && !muted
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(earned ? _icon : Icons.lock_outline, color: color),
      ),
      title: Text(
        badge.def.name,
        style: TextStyle(color: earned ? null : theme.colorScheme.outline),
      ),
      subtitle: Text(badge.def.description),
      trailing: earned
          ? Text(
              DateFormat.yMMMd().format(badge.awardedAt!),
              style: theme.textTheme.labelSmall,
            )
          : null,
    );
  }
}
