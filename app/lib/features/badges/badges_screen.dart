import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../app/ui/ui.dart';
import '../../data/badges/badge_defs.dart';
import '../../data/badges/badges_providers.dart';
import '../../data/badges/streaks.dart';
import '../../widgets/friendly_error.dart';
import '../leagues/widgets/live_numbers.dart';
import 'badge_moments.dart';
import 'moment_ledger.dart';

/// Colour per badge category, from the scheme so the rebrand carries it.
Color badgeCategoryColor(String category, ColorScheme scheme) =>
    switch (category) {
      'exploration' => scheme.tertiary,
      'social' => scheme.secondary,
      'season' => DrivalryTheme.teal,
      'shame' => scheme.outline,
      _ => scheme.primary,
    };

IconData badgeCategoryIcon(String category) => switch (category) {
  'exploration' => Icons.explore_outlined,
  'social' => Icons.people_outline,
  'season' => Icons.calendar_month_outlined,
  'shame' => Icons.sentiment_very_dissatisfied_outlined,
  _ => Icons.shield_outlined,
};

/// Progress toward a locked badge when the engine can say so cheaply: the
/// streak badges, from the live streaks. Null means "just locked".
(int current, int target)? badgeProgress(BadgeDef def, Streaks streaks) =>
    switch (def.id) {
      'clean_5' => (streaks.clean, 5),
      'clean_20' => (streaks.clean, 20),
      'phone_free_10' => (streaks.phoneFree, 10),
      _ => null,
    };

/// Streaks, then every badge: earned ones with their date, locked ones with
/// progress where it exists. Shame badges sit apart. A new badge gets the
/// celebration once (docs/12 §5, §7).
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(myBadgesProvider);
    final streaks = ref.watch(streaksProvider).value ?? Streaks.none;
    return Scaffold(
      appBar: AppBar(title: const Text('Badges')),
      body: BadgeMoments(
        child: badges.when(
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              Space.xxxl,
            ),
            children: const [
              SkeletonTile(height: 96),
              SizedBox(height: Space.xxl),
              SkeletonTile(height: 84),
              SizedBox(height: Space.md),
              SkeletonTile(height: 84),
              SizedBox(height: Space.md),
              SkeletonTile(height: 84),
            ],
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.xxxl,
              Space.gutter,
              0,
            ),
            child: Text(
              friendlyError(e, doing: 'load your badges'),
              style: context.bodyMuted,
            ),
          ),
          data: (list) => _BadgesList(list: list, streaks: streaks),
        ),
      ),
    );
  }
}

class _BadgesList extends StatelessWidget {
  const _BadgesList({required this.list, required this.streaks});
  final List<MyBadge> list;
  final Streaks streaks;

  @override
  Widget build(BuildContext context) {
    final regular = list.where((b) => !b.def.isShame).toList();
    final shame = list.where((b) => b.def.isShame).toList();
    final earned = regular.where((b) => b.earned).length;
    return ListView(
      padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
      children: [
        Reveal(
          child: Padding(
            padding: Space.screen,
            child: StatGrid(
              children: [
                StatTile(
                  value: '${streaks.clean}',
                  label: 'Clean streak',
                  icon: Icons.verified_outlined,
                ),
                StatTile(
                  value: '${streaks.phoneFree}',
                  label: 'Phone-free',
                  icon: Icons.phonelink_erase_outlined,
                ),
                StatTile(
                  value: '+${streaks.bonusXp}',
                  label: 'Streak XP',
                  icon: Icons.bolt_outlined,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.section),
        EditorialSection(
          kicker: '$earned of ${regular.length} badges earned',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < regular.length; i++) ...[
                if (i > 0) const SizedBox(height: Space.md),
                Reveal(
                  delay: Reveal.stagger(i + 1),
                  child: _BadgeTile(badge: regular[i], streaks: streaks),
                ),
              ],
            ],
          ),
        ),
        if (shame.isNotEmpty)
          EditorialSection(
            kicker: 'Dishonourable',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Lost duels and reckless trips. Worn for a week.',
                  style: context.caption,
                ),
                const SizedBox(height: Space.md),
                for (var i = 0; i < shame.length; i++) ...[
                  if (i > 0) const SizedBox(height: Space.md),
                  _BadgeTile(badge: shame[i], streaks: streaks, muted: true),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.badge,
    required this.streaks,
    this.muted = false,
  });
  final MyBadge badge;
  final Streaks streaks;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final earned = badge.earned;
    final lit = earned && !muted;
    final color = badgeCategoryColor(badge.def.category, scheme);
    final fresh =
        lit && recentlyAt(badge.awardedAt, DateTime.now(), badgeMomentWindow);
    final progress = earned ? null : badgeProgress(badge.def, streaks);
    final Widget? trailing = earned
        ? null
        : progress != null
        ? Text(
            '${progress.$1}/${progress.$2}',
            style: context.label.copyWith(color: scheme.onSurfaceVariant),
          )
        : const Pill('Locked', compact: true);
    return Tile(
      padding: const EdgeInsets.all(Space.lg),
      child: Row(
        children: [
          _Disc(
            icon: earned
                ? badgeCategoryIcon(badge.def.category)
                : Icons.lock_outline,
            color: lit ? color : scheme.onSurfaceVariant,
            background: lit
                ? color.withValues(alpha: 0.18)
                : scheme.surfaceContainerHighest,
            scaleIn: fresh,
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.def.name,
                  style: context.title.copyWith(
                    color: earned ? null : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  badge.def.description,
                  style: context.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (progress != null) ...[
                  const SizedBox(height: Space.sm),
                  GrowBar(
                    fraction: progress.$2 == 0 ? 0 : progress.$1 / progress.$2,
                    color: color,
                  ),
                ],
                if (earned) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    DateFormat.yMMMd().format(badge.awardedAt!),
                    style: context.caption.copyWith(color: scheme.outline),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Space.md), trailing],
        ],
      ),
    );
  }
}

/// 48 px icon disc; a freshly earned badge's disc springs in.
class _Disc extends StatelessWidget {
  const _Disc({
    required this.icon,
    required this.color,
    required this.background,
    required this.scaleIn,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final bool scaleIn;

  @override
  Widget build(BuildContext context) {
    final disc = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 24, color: color),
    );
    if (!scaleIn || context.reduceMotion) return disc;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1),
      duration: Motion.celebrate,
      curve: Curves.elasticOut,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: disc,
    );
  }
}
