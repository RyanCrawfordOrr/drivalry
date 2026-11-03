import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';
import '../../../features/cues/live_limit.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../widgets/units.dart';

/// The recording block at the top of the Drive sheet (docs/12 §7): the speed
/// in `display`, its unit in `label`, the limit and road as `title`, distance
/// and time as stat tiles, and one full-width "End drive".
class LiveDriveBlock extends StatelessWidget {
  const LiveDriveBlock({
    super.key,
    required this.live,
    required this.units,
    required this.onEnd,
    this.liveLimit,
    this.nowMs,
  });

  final LiveTripStats live;
  final SpeedUnits units;

  /// The road under the car from the live matcher, when a pack covers it.
  final LiveLimitState? liveLimit;
  final VoidCallback onEnd;

  /// Clock for the elapsed time; defaults to now.
  final int? nowMs;

  /// Whole units over the posted limit, in the way's unit, or 0.
  static int overBy(LiveLimitState limit) {
    final over = limit.overByMps ?? 0;
    final mph = limit.unitLabel == 'mph';
    return (mph ? over / 0.44704 : over * 3.6).round();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final limit = liveLimit;
    final hasLimit = limit != null && limit.hasLimit;
    final over = hasLimit ? overBy(limit) : 0;
    final road = limit?.roadName;

    return Column(
      key: const Key('live-block'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  formatSpeed(live.speedMps, units, withUnit: false),
                  key: const Key('live-speed'),
                  style: context.display,
                ),
                const SizedBox(width: Space.sm),
                Text(unitLabel(units), style: context.label),
              ],
            ),
            const Spacer(),
            const Pill('Recording', tone: PillTone.live, dot: true),
          ],
        ),
        const SizedBox(height: Space.sm),
        if (hasLimit)
          Row(
            key: const Key('live-limit'),
            children: [
              Expanded(
                child: Text(
                  'Limit ${limit.posted} ${limit.unitLabel}'
                  '${road == null || road.isEmpty ? '' : ' · $road'}',
                  style: context.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (over >= 1) ...[
                const SizedBox(width: Space.md),
                Text(
                  '$over over the limit',
                  style: context.label.copyWith(color: scheme.error),
                ),
              ],
            ],
          )
        else
          Text(
            'Scored when you park. Nothing leaves the phone.',
            style: context.bodyMuted,
          ),
        const SizedBox(height: Space.lg),
        StatGrid(
          columns: 2,
          children: [
            StatTile(
              value: formatDistance(live.distanceM, units),
              label: 'Distance',
            ),
            StatTile(value: formatElapsed(live.elapsedAt(now)), label: 'Time'),
          ],
        ),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'End drive', onPressed: onEnd),
      ],
    );
  }
}
