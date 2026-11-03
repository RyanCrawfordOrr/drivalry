import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/ui/ui.dart';
import '../../../features/cues/live_limit.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../tracking/tracking_models.dart';
import '../../../widgets/units.dart';
import 'live_drive_block.dart';

/// The status capsule floating over the map (docs/12 §7 Drive). One line
/// that reads the state at a glance; while recording it is the live speed
/// in `display` with the limit beside it. Idle and recording cross-fade
/// through a [StateSwitcher]; the recording dot breathes.
class DriveStatusCapsule extends StatelessWidget {
  const DriveStatusCapsule({
    super.key,
    required this.state,
    required this.units,
    this.liveLimit,
    this.onTap,
    this.nowMs,
  });

  final TrackingUiState state;
  final SpeedUnits units;
  final LiveLimitState? liveLimit;
  final VoidCallback? onTap;
  final int? nowMs;

  /// "7 pm" / "7:30 pm". Plain spaces: the locale's narrow no-break space
  /// before "pm" renders unevenly in some fonts.
  static String clock(DateTime t) => DateFormat.jm()
      .format(t)
      .replaceAll(':00', '')
      .replaceAll(RegExp(r'[  ]'), ' ')
      .toLowerCase();

  /// The one-line status for every state but recording (null then).
  static String? statusText(TrackingUiState state, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final plugin = state.plugin;
    if (state.simulating) return 'Replaying a drive…';
    if (state.live != null) return null;
    if (!plugin.pluginAvailable) {
      return 'Auto-detect is not available on this device';
    }
    if (!plugin.enabled) return 'Auto-detect is off';
    if (plugin.isPausedAt(now)) {
      final until = DateTime.fromMillisecondsSinceEpoch(plugin.pausedUntil);
      return 'Paused until ${clock(until)}';
    }
    if (plugin.phase == TrackingPhase.tentative) {
      return 'Checking if you are driving…';
    }
    if (!plugin.permissions.sufficientForAutoTracking) {
      return 'Finish setting up auto-detect';
    }
    return 'Ready. Drives start on their own.';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = state.live;
    final text = statusText(state, nowMs: nowMs);

    final Widget child;
    if (text == null && live != null) {
      final limit = liveLimit;
      final hasLimit = limit != null && limit.hasLimit;
      final over = hasLimit ? LiveDriveBlock.overBy(limit) : 0;
      // Scales down rather than clipping when a three-digit speed and the
      // limit pill meet a narrow phone.
      child = FittedBox(
        key: const Key('capsule-recording'),
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PulsingDot(color: scheme.primary, size: 8),
            const SizedBox(width: Space.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedNumber(
                  value: speedValue(live.speedMps, units),
                  style: context.display,
                  duration: Motion.celebrate,
                ),
                const SizedBox(width: Space.sm),
                Text(unitLabel(units), style: context.label),
              ],
            ),
            if (hasLimit) ...[
              const SizedBox(width: Space.md),
              Pill(
                'Limit ${limit.posted}',
                tone: over >= 1 ? PillTone.danger : PillTone.primary,
              ),
            ],
          ],
        ),
      );
    } else {
      final busy =
          state.simulating || state.plugin.phase == TrackingPhase.tentative;
      final watching = text == 'Ready. Drives start on their own.';
      child = Row(
        key: Key('capsule-$text'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (watching)
            PulsingDot(color: scheme.primary, size: 8)
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.outline,
              ),
            ),
          const SizedBox(width: Space.sm),
          Flexible(
            child: Text(
              text ?? '',
              style: context.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  Haptics.tap();
                  onTap!();
                },
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.touch),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: StateSwitcher(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
