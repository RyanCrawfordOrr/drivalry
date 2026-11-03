import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';
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

/// A league tier as the house [Pill], tinted with the tier's colour. The
/// capsule, padding and type come from the Pill; only the two colours differ.
class TierPill extends StatelessWidget {
  const TierPill({super.key, required this.tier, this.compact = true});

  final LeagueTier tier;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = tierColor(tier, scheme);
    return Theme(
      data: theme.copyWith(
        colorScheme: scheme.copyWith(
          primaryContainer: color.withValues(alpha: 0.18),
          onPrimaryContainer: color,
        ),
      ),
      child: Pill(tier.label, tone: PillTone.primary, compact: compact),
    );
  }
}
