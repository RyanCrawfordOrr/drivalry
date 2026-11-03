import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';

import '../../../data/convoy/recap_builder.dart';
import '../../../data/convoy/settle_up.dart';
import '../../../data/db/database.dart' show ConvoyTrack;
import '../../../widgets/units.dart';
import 'recap_playback.dart';

/// Square share image for a convoy recap (rendered off-screen).
const recapCardSize = Size(540, 540);

class RecapShareCard extends StatelessWidget {
  const RecapShareCard({
    super.key,
    required this.recap,
    required this.tracks,
    required this.units,
  });

  final ConvoyRecap recap;
  final Map<String, List<ConvoyTrack>> tracks;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = recap.members.fold(0.0, (a, m) => a + m.distanceM);
    final d = recap.duration;
    final honours = recap.awards.where((a) => a.honourable).take(3).toList();
    final nameOf = {for (final m in recap.members) m.userId: m.name};
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surface,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            recap.name,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            [
              '${recap.members.length} cars',
              formatDistance(total, units),
              if (d != null) formatElapsed(d),
              '${recap.stopsDone} stops',
              if (recap.totalCostCents > 0)
                formatCents(recap.totalCostCents, currency: recap.costCurrency),
            ].join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: RecapPlayback(
                tracks: tracks,
                progress: 1,
                order: [for (final m in recap.members) m.userId],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final a in honours)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${a.title}: ${nameOf[a.userId] ?? 'Driver'}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Drivalry convoy',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
