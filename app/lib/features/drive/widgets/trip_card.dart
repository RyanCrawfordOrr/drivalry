import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/ui/ui.dart';
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

/// Hero tag shared by the list ring and the trip screen ring, so the ring
/// flies between them (docs/12 §5).
String tripRingTag(String tripId) => 'trip-ring-$tripId';

/// A trip in the Drive sheet. [large] is the "Last trip" hero: ring 96,
/// verdict as `title`, three stats. Otherwise a compact row: ring 44, verdict
/// on one line, the time underneath.
class TripCard extends StatelessWidget {
  const TripCard({
    super.key,
    required this.trip,
    required this.score,
    required this.units,
    this.large = false,
    this.onTap,
    this.onLongPress,
  });

  final Trip trip;
  final TripScoreView? score;
  final SpeedUnits units;
  final bool large;
  final VoidCallback? onTap;

  /// Opens the actions sheet (share, passenger, delete).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = score;
    final scored = s != null && s.scored;
    final verdict = scored && s.roastText != null
        ? s.roastText!
        : unscoredLabel(trip, s);
    final italic = scored && s.headlineIsRoast ? FontStyle.italic : null;
    final distance = formatDistance(trip.distanceM, units);
    final time = formatElapsed(Duration(seconds: trip.movingS.round()));

    if (!large) {
      return Tile(
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            Hero(
              tag: tripRingTag(trip.id),
              child: ScoreRing(
                score: scored ? s.score : null,
                size: 44,
                stroke: 5,
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    verdict,
                    style: context.body.copyWith(fontStyle: italic),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${tripDateLabel(trip)} · $distance · $time',
                    style: context.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Ring and verdict side by side, the figures across the full width
    // underneath: three columns beside a 96 ring do not fit at 360 wide.
    return Tile(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: tripRingTag(trip.id),
                child: ScoreRing(
                  score: scored ? s.score : null,
                  size: 96,
                  stroke: 9,
                  reckless: s?.reckless ?? false,
                  animate: true,
                ),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tripDateLabel(trip), style: context.caption),
                    const SizedBox(height: Space.xs),
                    Text(
                      verdict,
                      style: context.title.copyWith(fontStyle: italic),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: _MiniStat(value: distance, label: 'Distance'),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: _MiniStat(value: time, label: 'Time'),
              ),
              if (scored) ...[
                const SizedBox(width: Space.sm),
                Expanded(
                  child: _MiniStat(value: '+${s.xp}', label: 'XP'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: context.label.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label, style: context.caption),
      ],
    );
  }
}
