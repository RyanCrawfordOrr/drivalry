import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/deep_links.dart';
import '../../app/routes.dart';
import '../../data/repos/convoy_repo.dart';
import '../../data/repos/convoy_sync.dart';
import '../../widgets/relative_time.dart';
import '../../widgets/signed_in_scope.dart';

/// The Convoy tab: the convoy I am in now, the ones being planned, and past
/// trips with their recaps (docs/01 §4.6).
class ConvoyScreen extends ConsumerWidget {
  const ConvoyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(convoySyncProvider);
    ref.watch(deepLinksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Convoy')),
      body: const SignedInScope(
        message: 'Sign in to drive with friends in a convoy.',
        icon: Icons.route_outlined,
        child: _ConvoyList(),
      ),
    );
  }
}

class _ConvoyList extends ConsumerWidget {
  const _ConvoyList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final convoys = ref.watch(myConvoysProvider);
    final list = convoys.value ?? const <Convoy>[];
    final active = [
      for (final c in list)
        if (c.status != ConvoyStatus.ended) c,
    ];
    final past = [
      for (final c in list)
        if (c.status == ConvoyStatus.ended) c,
    ];
    final now = DateTime.now().toUtc();

    return RefreshIndicator(
      onRefresh: () => ref.read(myConvoysProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Two to six cars, one trip. Everyone sees everyone, and the radio '
            'is one button away.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('new-convoy'),
                  onPressed: () => context.push(Routes.createConvoy),
                  icon: const Icon(Icons.add_road_outlined),
                  label: const Text('New convoy'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _joinByCode(context),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text('Join with code'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (convoys.isLoading && list.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (!convoys.isLoading && list.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No convoys yet', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Start one before a road trip and share the code. '
                      'While the trip is on, every car sees the others, hears '
                      'the radio, votes on stops and splits the costs. '
                      'Positions stay between the cars and never leave your '
                      'phones in detail.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          for (final c in active) _ConvoyCard(convoy: c, now: now),
          if (past.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Past trips', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final c in past) _ConvoyCard(convoy: c, now: now),
          ],
        ],
      ),
    );
  }

  Future<void> _joinByCode(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a convoy'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
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
    context.push(Routes.joinConvoy(code.trim().toLowerCase()));
  }
}

class _ConvoyCard extends StatelessWidget {
  const _ConvoyCard({required this.convoy, required this.now});
  final Convoy convoy;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = convoy;
    final (icon, label, color) = switch (c.status) {
      ConvoyStatus.active => (
        Icons.directions_car,
        'On the road',
        theme.colorScheme.primary,
      ),
      ConvoyStatus.planning => (
        Icons.edit_road_outlined,
        'Planning',
        theme.colorScheme.secondary,
      ),
      ConvoyStatus.ended => (
        Icons.flag_outlined,
        'Ended ${relativeTime(c.endedAt ?? c.createdAt, now)}',
        theme.colorScheme.outline,
      ),
    };
    final cars = '${c.memberCount} ${c.memberCount == 1 ? 'car' : 'cars'}';
    final dest = c.destination?.name;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(c.name),
        subtitle: Text(
          dest == null ? '$label · $cars' : '$label · $cars · to $dest',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(
          c.isEnded ? Routes.convoyRecap(c.id) : Routes.convoyDetail(c.id),
        ),
      ),
    );
  }
}
