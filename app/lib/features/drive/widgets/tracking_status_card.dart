import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../features/cues/live_limit.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../tracking/tracking_models.dart';
import '../../../widgets/units.dart';

/// Top of the Drive tab: permissions, on/off, paused, watching, or the live
/// trip numbers.
class TrackingStatusCard extends StatelessWidget {
  const TrackingStatusCard({
    super.key,
    required this.state,
    required this.units,
    this.liveLimit,
    required this.onRequestPermissions,
    required this.onOpenSettings,
    required this.onSetEnabled,
    required this.onPause,
    required this.onPauseUntilTomorrow,
    required this.onResume,
    required this.onStartNow,
    required this.onEndNow,
  });

  final TrackingUiState state;
  final SpeedUnits units;

  /// The road under the car from the live matcher, when a pack covers it.
  final LiveLimitState? liveLimit;
  final VoidCallback onRequestPermissions;
  final VoidCallback onOpenSettings;
  final ValueChanged<bool> onSetEnabled;
  final ValueChanged<Duration> onPause;
  final VoidCallback onPauseUntilTomorrow;
  final VoidCallback onResume;
  final VoidCallback onStartNow;
  final VoidCallback onEndNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plugin = state.plugin;
    final now = DateTime.now().millisecondsSinceEpoch;

    Widget body;
    if (state.simulating) {
      body = _Section(
        icon: Icons.play_circle_outline,
        title: 'Simulating a drive…',
        subtitle: 'Replaying a trip through the recorder and scorer.',
        trailing: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    } else if (!plugin.pluginAvailable) {
      body = const _Section(
        icon: Icons.phonelink_off,
        title: 'Automatic tracking is not available here',
        subtitle:
            'This build has no native tracking plugin. Use "Simulate a drive" '
            'from the menu to exercise scoring.',
      );
    } else if (state.live != null) {
      final live = state.live!;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.fiber_manual_record,
                color: theme.colorScheme.error,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text('Recording', style: theme.textTheme.labelLarge),
              const Spacer(),
              TextButton(onPressed: onEndNow, child: const Text('End now')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatSpeed(live.speedMps, units, withUnit: false),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  unitLabel(units),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatDistance(live.distanceM, units),
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    formatElapsed(live.elapsedAt(now)),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ],
          ),
          if (liveLimit?.hasLimit == true) ...[
            const SizedBox(height: 6),
            _LiveLimitLine(limit: liveLimit!, theme: theme),
          ],
          const SizedBox(height: 4),
          Text(
            'Scored when you park. Nothing leaves the phone.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    } else if (!plugin.enabled) {
      body = _Section(
        icon: Icons.pause_circle_outline,
        title: 'Tracking is off',
        subtitle: 'Drives are not detected or recorded.',
        trailing: Switch(value: false, onChanged: onSetEnabled),
      );
    } else if (plugin.isPausedAt(now)) {
      final until = DateTime.fromMillisecondsSinceEpoch(plugin.pausedUntil);
      body = _Section(
        icon: Icons.snooze,
        title: 'Paused until ${DateFormat.jm().format(until)}',
        subtitle: 'Automatic detection resumes on its own.',
        trailing: TextButton(onPressed: onResume, child: const Text('Resume')),
      );
    } else if (plugin.phase == TrackingPhase.tentative) {
      body = const _Section(
        icon: Icons.directions_car_outlined,
        title: 'Looks like you are driving…',
        subtitle: 'Confirming before recording starts.',
      );
    } else if (!plugin.permissions.sufficientForAutoTracking) {
      final perms = plugin.permissions;
      final missing = <String>[
        if (perms.location == LocationPermission.denied)
          'Location: allow it, then pick "Allow all the time" (Android) or '
              '"Always" (iOS) so drives are noticed with the app closed.'
        else if (perms.location == LocationPermission.whileInUse)
          'Location is "while using the app". Automatic trips need '
              '"Allow all the time" (Android) or "Always" (iOS).',
        if (perms.location != LocationPermission.denied &&
            !perms.preciseLocation)
          'Precise location is off. Approximate fixes cannot be matched to a road.',
        if (perms.motion != SimplePermission.granted)
          'Physical activity (Android) or Motion & Fitness (iOS), to notice '
              'when you start driving.',
      ];
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Section(
            icon: Icons.location_on_outlined,
            title: 'Let Drivalry detect your drives',
            subtitle:
                'Trips start and stop on their own once these are set. '
                'Raw GPS never leaves this phone.',
          ),
          const SizedBox(height: 8),
          for (final m in missing)
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 4),
              child: Text('• $m', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: onRequestPermissions,
                child: const Text('Allow'),
              ),
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('Open settings'),
              ),
              if (perms.sufficientForManualTracking)
                OutlinedButton.icon(
                  onPressed: onStartNow,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Record a drive now'),
                ),
            ],
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section(
            icon: Icons.radar,
            title: 'Watching for a drive',
            subtitle:
                'Starts on its own when you drive. Nothing is recorded until then.',
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz),
              tooltip: 'Pause',
              onSelected: (v) {
                switch (v) {
                  case '1h':
                    onPause(const Duration(hours: 1));
                  case '4h':
                    onPause(const Duration(hours: 4));
                  case 'tomorrow':
                    onPauseUntilTomorrow();
                  case 'off':
                    onSetEnabled(false);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: '1h', child: Text('Pause for 1 hour')),
                PopupMenuItem(value: '4h', child: Text('Pause for 4 hours')),
                PopupMenuItem(
                  value: 'tomorrow',
                  child: Text('Pause until tomorrow'),
                ),
                PopupMenuItem(value: 'off', child: Text('Turn tracking off')),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onStartNow,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start now'),
              ),
            ],
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// "Limit 35 mph · Elm St" with "4 over" in the error colour when speeding.
class _LiveLimitLine extends StatelessWidget {
  const _LiveLimitLine({required this.limit, required this.theme});

  final LiveLimitState limit;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final over = limit.overByMps ?? 0;
    final mph = limit.unitLabel == 'mph';
    final overDisplay = (mph ? over / 0.44704 : over * 3.6).round();
    final road = limit.roadName;
    return Row(
      key: const Key('live-limit'),
      children: [
        Icon(Icons.speed, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Limit ${limit.posted} ${limit.unitLabel}'
            '${road == null || road.isEmpty ? '' : ' · $road'}',
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (overDisplay >= 1)
          Text(
            '$overDisplay over',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}
