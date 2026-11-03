import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../data/crash/crash_monitor.dart';

/// Drive-tab card that stays until the driver deals with a crash: an alert
/// that went out and is unresolved, or a trip still flagged as a possible
/// crash (the app was dead during the countdown). Renders nothing otherwise.
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
      return Card(
        color: scheme.errorContainer,
        child: ListTile(
          leading: Icon(Icons.emergency_share, color: scheme.onErrorContainer),
          title: const Text('Help was requested'),
          subtitle: Text('Possible crash reported $when. Are you OK?'),
          trailing: FilledButton(
            key: const Key('crash-card-resolve'),
            onPressed: monitor.resolveUnresolved,
            child: const Text("I'm OK"),
          ),
          onTap: () => context.push(Routes.crash),
        ),
      );
    }

    final active = state.candidate;
    if (active != null && !state.testMode) {
      return Card(
        color: scheme.errorContainer,
        child: ListTile(
          leading: Icon(Icons.car_crash, color: scheme.onErrorContainer),
          title: const Text('Possible crash. Are you OK?'),
          subtitle: const Text(
            "Your contacts are alerted when it ends unless you tap I'm OK.",
          ),
          trailing: Wrap(
            spacing: 8,
            children: [
              FilledButton(
                key: const Key('crash-card-im-ok'),
                onPressed: monitor.imOk,
                child: const Text("I'm OK"),
              ),
              TextButton(
                key: const Key('crash-card-show'),
                onPressed: () => context.push(Routes.crash),
                child: const Text('Show'),
              ),
            ],
          ),
        ),
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
    return Card(
      child: ListTile(
        leading: Icon(Icons.car_crash_outlined, color: scheme.error),
        title: const Text('Possible crash recorded'),
        subtitle: Text(
          'On the trip of $when. It stays unscored until you confirm you '
          'were fine.',
        ),
        trailing: FilledButton.tonal(
          key: const Key('crash-card-clear'),
          onPressed: () => monitor.clearFlag(trip.id),
          child: const Text('I was fine'),
        ),
      ),
    );
  }
}
