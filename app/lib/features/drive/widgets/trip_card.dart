import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db/database.dart';
import '../../../data/models/trip_phase.dart';
import '../../../data/models/trip_score_view.dart';
import '../../../widgets/units.dart';
import 'score_ring.dart';

/// Caption for a trip that produced no score.
String unscoredLabel(Trip trip, TripScoreView? score) {
  if (trip.phase == TripPhase.recording.wire) return 'Recording…';
  if (trip.phase == TripPhase.pendingPassenger.wire) return 'Scoring…';
  if (trip.isPassenger == true || score?.unscoredReason == 'passenger') {
    return 'Passenger trip';
  }
  return 'Too short to judge';
}

String tripDateLabel(Trip trip) {
  final start = DateTime.fromMillisecondsSinceEpoch(trip.startedAt);
  final now = DateTime.now();
  final sameDay =
      start.year == now.year &&
      start.month == now.month &&
      start.day == now.day;
  final time = DateFormat.jm().format(start);
  if (sameDay) return 'Today, $time';
  final yesterday = now.subtract(const Duration(days: 1));
  if (start.year == yesterday.year &&
      start.month == yesterday.month &&
      start.day == yesterday.day) {
    return 'Yesterday, $time';
  }
  return '${DateFormat.MMMEd().format(start)}, $time';
}

/// The trip card: score ring, headline line, components, coverage.
/// [large] is the "Last trip" card on the Drive tab; otherwise a list row.
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.trip,
    required this.score,
    required this.units,
    this.large = false,
    this.onTap,
  });

  final Trip trip;
  final TripScoreView? score;
  final SpeedUnits units;
  final bool large;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = score;
    final scored = s != null && s.scored;
    final headline = s?.roastText;
    final subtitle = <String>[
      formatDistance(trip.distanceM, units),
      formatElapsed(Duration(seconds: trip.movingS.round())),
      if (trip.limitCoverage != null)
        '${(trip.limitCoverage! * 100).round()}% limit coverage',
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(large ? 16 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ScoreRing(
                score: scored ? s.score : null,
                size: large ? 96 : 56,
                stroke: large ? 9 : 6,
                reckless: s?.reckless ?? false,
                label: scored ? '+${s.xp} XP' : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tripDateLabel(trip),
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    if (scored && headline != null)
                      Text(
                        headline,
                        style:
                            (large
                                    ? theme.textTheme.titleMedium
                                    : theme.textTheme.bodyMedium)
                                ?.copyWith(
                                  fontStyle: s.headlineIsRoast
                                      ? FontStyle.italic
                                      : null,
                                ),
                        maxLines: large ? 4 : 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        unscoredLabel(trip, s),
                        style: theme.textTheme.bodyMedium,
                      ),
                    const SizedBox(height: 6),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                    if (large && scored) ...[
                      const SizedBox(height: 10),
                      ComponentChips(score: s),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four small chips, one per score component, showing points lost.
class ComponentChips extends StatelessWidget {
  const ComponentChips({super.key, required this.score});

  final TripScoreView score;

  @override
  Widget build(BuildContext context) {
    final p = score.penalties;
    final items = [
      ('Speed', p.speed),
      ('Smooth', p.smoothness),
      ('Attention', p.attention),
      ('Efficiency', p.efficiency),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (label, lost) in items)
          Chip(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            label: Text(
              lost < 0.05
                  ? '$label ✓'
                  : '$label −${lost.toStringAsFixed(lost < 10 ? 1 : 0)}',
            ),
          ),
      ],
    );
  }
}
