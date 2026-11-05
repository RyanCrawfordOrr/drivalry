import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/ui/ui.dart';
import '../../tracking/tracking_controller.dart';
import '../../widgets/friendly_error.dart';

/// "See a sample drive": plays a pretend trip through the same recorder,
/// matcher and scoring as a real one, then opens it. For a new person (and
/// for App Review) it is the only way to see a scored trip without driving.
/// Sample drives stay on this phone: they never upload, never post to the
/// feed and never count for badges, streaks, stats or leagues
/// (`AppDatabase._realDrive`). The developer "Simulate a drive" sheet in
/// debug builds is the full-control version of this.
Future<void> showSampleDriveSheet(BuildContext context, WidgetRef ref) async {
  final choice = await showDrivalrySheet<_Sample>(
    context,
    title: 'See a sample drive',
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A pretend 20-minute commute, scored exactly like a real one. It '
          'stays on this phone and never counts for leagues or badges.',
          style: ctx.bodyMuted,
        ),
        const SizedBox(height: Space.lg),
        ListTile(
          key: const Key('sample-clean'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.sentiment_satisfied_alt),
          title: const Text('A smooth commute'),
          subtitle: const Text('Within the limit, gentle stops, phone down'),
          onTap: () => Navigator.pop(ctx, _Sample.clean),
        ),
        ListTile(
          key: const Key('sample-messy'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.local_fire_department_outlined),
          title: const Text('A messy commute'),
          subtitle: const Text('Speeding, a slam on the brakes, phone in hand'),
          onTap: () => Navigator.pop(ctx, _Sample.messy),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;

  final input = switch (choice) {
    _Sample.clean => cleanCommute('sample-clean'),
    _Sample.messy => messyCommute('sample-messy'),
  };
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    final id = await ref
        .read(trackingControllerProvider.notifier)
        .simulate(input, speedUp: 0);
    router.push(Routes.tripDetail(id));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(friendlyError(e, doing: 'play the sample drive'))),
    );
  }
}

enum _Sample { clean, messy }
