import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/stats/stats_engine.dart';
import 'fun_facts.dart';
import 'us_states.dart';

/// A fact as a tile in the stats grid.
class FactTile extends StatelessWidget {
  const FactTile({super.key, required this.fact, this.onTap});

  final FunFact fact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(fact.icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      fact.label,
                      style: theme.textTheme.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fact.value,
                style: theme.textTheme.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (fact.hint.isNotEmpty)
                Text(
                  fact.hint,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "map that fills in": every state as a chip, visited ones filled.
class StatesGrid extends StatelessWidget {
  const StatesGrid({super.key, required this.visited, this.compact = false});

  final Set<String> visited;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      spacing: compact ? 3 : 4,
      runSpacing: compact ? 3 : 4,
      children: [
        for (final code in usStateCodes)
          Tooltip(
            message: usStateNames[code] ?? code,
            child: Container(
              width: compact ? 30 : 36,
              padding: EdgeInsets.symmetric(vertical: compact ? 2 : 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: visited.contains(code)
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                code,
                style: style?.copyWith(
                  color: visited.contains(code)
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  fontWeight: visited.contains(code) ? FontWeight.bold : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The shareable headline image (1080×1350): window, three or four big
/// numbers, the time-saved line. No roads, places or names.
class StatsHeadlineCard extends StatelessWidget {
  const StatsHeadlineCard({
    super.key,
    required this.stats,
    required this.facts,
    this.handle,
  });

  final DriverStats stats;
  final List<FunFact> facts;
  final String? handle;

  @override
  Widget build(BuildContext context) {
    final shareable = facts.where((f) => f.shareable).take(4).toList();
    final line = stats.reality.timeSavedLine;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101828), Color(0xFF1D3557)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(72),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DRIVALRY',
              style: TextStyle(
                color: DrivalryTheme.seed,
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              stats.range.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 72,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 64),
            for (final f in shareable) ...[
              Text(
                f.label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 32,
                  letterSpacing: 3,
                ),
              ),
              Text(
                f.value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 120,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 36),
            ],
            const Spacer(),
            if (line != null)
              Text(
                line,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  height: 1.3,
                ),
              ),
            const SizedBox(height: 24),
            Text(
              handle == null ? 'drivalry.app' : '@$handle · drivalry.app',
              style: const TextStyle(color: Colors.white54, fontSize: 32),
            ),
          ],
        ),
      ),
    );
  }
}
