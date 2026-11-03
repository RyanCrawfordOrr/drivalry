import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';
import '../../../features/cues/live_limit.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../widgets/units.dart';

/// The recording block at the top of the Drive sheet (docs/12 §7): the speed
/// in `display`, its unit in `label`, the limit and road as `title`, distance
/// and time as stat tiles, and one full-width "End drive". The numbers count
/// rather than jump and the recording dot breathes (docs/12 §5b).
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
    final distance = distanceParts(live.distanceM, units);
    final elapsed = live.elapsedAt(now);
    final time = elapsedParts(elapsed);

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
                KeyedSubtree(
                  key: const Key('live-speed'),
                  child: AnimatedNumber(
                    value: speedValue(live.speedMps, units),
                    style: context.display,
                    duration: Motion.celebrate,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(unitLabel(units), style: context.label),
              ],
            ),
            const Spacer(),
            PulsingDot(color: scheme.primary, size: 8),
            const SizedBox(width: Space.xs),
            Text('Recording', style: context.label),
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
        Row(
          children: [
            Expanded(
              child: _LiveStat(
                label: 'Distance',
                child: AnimatedNumber(
                  value: distance.value,
                  decimals: distance.decimals,
                  suffix: ' ${distance.unit}',
                  style: _statStyle(context),
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: _LiveStat(
                label: 'Time',
                child: time == null
                    ? Text(formatElapsed(elapsed), style: _statStyle(context))
                    : AnimatedNumber(
                        value: time.value,
                        suffix: ' ${time.unit}',
                        style: _statStyle(context),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        PrimaryButton(label: 'End drive', onPressed: onEnd),
      ],
    );
  }

  static TextStyle _statStyle(BuildContext context) =>
      context.title.copyWith(fontWeight: FontWeight.w700);
}

/// Same shape as `StatTile`, but the figure is a widget so it can count.
class _LiveStat extends StatelessWidget {
  const _LiveStat({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tile(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: Space.xs),
          Text(label, style: context.caption),
        ],
      ),
    );
  }
}
