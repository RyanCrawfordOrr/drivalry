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
/// in `display` with the limit beside it.
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

  /// "7 pm" / "7:30 pm".
  static String clock(DateTime t) =>
      DateFormat.jm().format(t).replaceAll(':00', '').toLowerCase();

  /// The one-line status for every state but recording (null then).
  static String? statusText(TrackingUiState state, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final plugin = state.plugin;
    if (state.simulating) return 'Replaying a drive…';
    if (state.live != null) return null;
    if (!plugin.pluginAvailable) return 'Not available on this device';
    if (!plugin.enabled) return 'Auto-detect is off';
    if (plugin.isPausedAt(now)) {
      final until = DateTime.fromMillisecondsSinceEpoch(plugin.pausedUntil);
      return 'Paused until ${clock(until)}';
    }
    if (plugin.phase == TrackingPhase.tentative) return 'Looks like a drive…';
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
      child = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                formatSpeed(live.speedMps, units, withUnit: false),
                style: context.display,
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
      );
    } else {
      final busy =
          state.simulating || state.plugin.phase == TrackingPhase.tentative;
      final watching = text == 'Ready. Drives start on their own.';
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: watching ? scheme.primary : scheme.outline,
              ),
            ),
          const SizedBox(width: Space.sm),
          Text(text ?? '', style: context.label),
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
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
