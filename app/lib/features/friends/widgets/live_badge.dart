import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// "Driving now" and friends: a tonal capsule with a breathing dot, so live
/// state reads as live (docs/12 §5b). Same shape as [Pill].
class LiveBadge extends StatelessWidget {
  const LiveBadge(this.label, {super.key, this.compact = true});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? Space.sm : Space.md,
        vertical: compact ? Space.xs : Space.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulsingDot(color: scheme.primary, size: 8),
          const SizedBox(width: Space.xs),
          Text(
            label,
            style: context.label.copyWith(color: scheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}
