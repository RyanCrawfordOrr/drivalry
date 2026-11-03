import 'package:flutter/material.dart';

import '../../../data/repos/leagues_repo.dart';

/// Colour per tier; Learner is neutral so new leagues do not shout.
Color tierColor(LeagueTier tier, ColorScheme scheme) => switch (tier) {
  LeagueTier.learner => scheme.outline,
  LeagueTier.bronze => const Color(0xFFCD7F32),
  LeagueTier.silver => const Color(0xFF8E9BA6),
  LeagueTier.gold => const Color(0xFFD4AF37),
  LeagueTier.platinum => const Color(0xFF5FA8A8),
  LeagueTier.diamond => const Color(0xFF3FA9F5),
  LeagueTier.chauffeur => scheme.primary,
};

/// Small labelled chip for a league tier.
class TierChip extends StatelessWidget {
  const TierChip({super.key, required this.tier, this.dense = false});

  final LeagueTier tier;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = tierColor(tier, scheme);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            tier == LeagueTier.chauffeur
                ? Icons.workspace_premium
                : Icons.shield_outlined,
            size: dense ? 12 : 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            tier.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
