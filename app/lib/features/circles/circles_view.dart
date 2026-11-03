import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/circles_repo.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/presence_repo.dart';
import 'checkin_sheet.dart';

/// The Circles segment of the Friends tab: check-in, places, my circles,
/// create or join (docs/01 §4.5).
class CirclesView extends ConsumerWidget {
  const CirclesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final circles = ref.watch(myCirclesProvider);
    final membership = ref.watch(circleMembershipProvider);
    final presence = ref.watch(visiblePresenceProvider).value ?? const [];
    final now = DateTime.now().toUtc();
    final drivingNow = {
      for (final p in presence)
        if (p.driving &&
            now.difference(p.updatedAt) < const Duration(hours: 24))
          p.userId,
    };
    final list = circles.value ?? const <Circle>[];

    return RefreshIndicator(
      onRefresh: () => ref.read(myCirclesProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('checkin-button'),
                  onPressed: () => showCheckinSheet(context),
                  icon: const Icon(Icons.home_outlined),
                  label: const Text('I got home'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push(Routes.places),
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('Places'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (circles.isLoading && list.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (!circles.isLoading && list.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No circles yet', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'A circle is a group that always sees each other on the '
                      'map: family, roommates, the crew. Everyone is precise; '
                      'anyone can hide, and the circle sees that they are.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          for (final c in list)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  child: const Icon(Icons.groups_outlined),
                ),
                title: Text(c.name),
                subtitle: Text(_subtitle(c, membership[c.id], drivingNow)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.circle(c.id)),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.push(Routes.createCircle),
                  icon: const Icon(Icons.add),
                  label: const Text('New circle'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _joinByCode(context, ref),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Join with code'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _subtitle(
    Circle c,
    Set<String>? members,
    Set<String> drivingNow,
  ) {
    final count = c.memberCount == 0 ? (members?.length ?? 0) : c.memberCount;
    final driving = members == null
        ? 0
        : members.where(drivingNow.contains).length;
    final parts = <String>[
      '$count member${count == 1 ? '' : 's'}',
      if (driving > 0) '$driving driving now',
      if (c.myHiding) 'you are hiding',
    ];
    return parts.join(' · ');
  }

  Future<void> _joinByCode(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a circle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Invite code'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    context.push(Routes.joinCircle(code.trim().toLowerCase()));
  }
}
