import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/crash/crash_monitor.dart';

/// Drive-sheet tile that stays until the driver deals with a crash: an alert
/// that went out and is unresolved, or a trip still flagged as a possible
/// crash (the app was dead during the countdown). Renders nothing otherwise.
/// Title and caption run the full width; the buttons sit under them in a
/// 48 px row, so the tile reads at 360 wide.
class CrashStatusCard extends ConsumerWidget {
  const CrashStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(crashMonitorProvider);
    final flagged = ref.watch(crashFlaggedTripsProvider).value ?? const [];
    final monitor = ref.read(crashMonitorProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    final unresolved = state.unresolved;
    if (unresolved != null) {
      final when = DateFormat.MMMd().add_jm().format(
        DateTime.fromMillisecondsSinceEpoch(unresolved.createdAt),
      );
      return _CrashTile(
        tone: TileTone.danger,
        icon: Icons.emergency_share,
        title: 'Help was requested',
        caption: 'Possible crash reported $when. Are you OK?',
        onTap: () => context.push(Routes.crash),
        actions: [
          Expanded(
            child: FilledButton(
              key: const Key('crash-card-resolve'),
              onPressed: monitor.resolveUnresolved,
              child: const Text("I'm OK"),
            ),
          ),
        ],
      );
    }

    final active = state.candidate;
    if (active != null && !state.testMode) {
      return _CrashTile(
        tone: TileTone.danger,
        icon: Icons.car_crash,
        title: 'Possible crash. Are you OK?',
        caption:
            "Your contacts are alerted when it ends unless you tap I'm OK.",
        actions: [
          Expanded(
            child: FilledButton(
              key: const Key('crash-card-im-ok'),
              onPressed: monitor.imOk,
              child: const Text("I'm OK"),
            ),
          ),
          const SizedBox(width: Space.sm),
          TextButton(
            key: const Key('crash-card-show'),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onErrorContainer,
            ),
            onPressed: () => context.push(Routes.crash),
            child: const Text('Show'),
          ),
        ],
      );
    }

    final pending = [
      for (final t in flagged)
        if (t.id != active?.tripId) t,
    ];
    if (pending.isEmpty) return const SizedBox.shrink();
    final trip = pending.first;
    final when = DateFormat.MMMd().add_jm().format(
      DateTime.fromMillisecondsSinceEpoch(trip.startedAt),
    );
    return _CrashTile(
      tone: TileTone.raised,
      icon: Icons.car_crash_outlined,
      iconColor: scheme.error,
      title: 'Possible crash recorded',
      caption:
          'On the trip of $when. It stays unscored until you confirm you '
          'were fine.',
      actions: [
        Expanded(
          child: FilledButton.tonal(
            key: const Key('crash-card-clear'),
            onPressed: () => monitor.clearFlag(trip.id),
            child: const Text('I was fine'),
          ),
        ),
      ],
    );
  }
}

class _CrashTile extends StatelessWidget {
  const _CrashTile({
    required this.tone,
    required this.icon,
    required this.title,
    required this.caption,
    required this.actions,
    this.iconColor,
    this.onTap,
  });

  final TileTone tone;
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String caption;
  final List<Widget> actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final danger = tone == TileTone.danger;
    final fg = danger ? scheme.onErrorContainer : scheme.onSurface;
    final muted = danger ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return Tile(
      tone: tone,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor ?? fg),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  title,
                  style: context.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(caption, style: context.caption.copyWith(color: muted)),
          const SizedBox(height: Space.md),
          SizedBox(
            height: Sizes.touch,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: actions,
            ),
          ),
        ],
      ),
    );
  }
}
