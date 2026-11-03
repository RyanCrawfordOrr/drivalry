import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/friends_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../widgets/signed_in_scope.dart';
import 'widgets/user_avatar.dart';

/// Incoming and outgoing friend requests.
class FriendRequestsScreen extends ConsumerWidget {
  const FriendRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s =
        ref.watch(friendsSnapshotProvider).value ?? const FriendsSnapshot();
    final repo = ref.read(friendsRepoProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friend requests'),
        actions: [
          IconButton(
            tooltip: 'Add friend',
            onPressed: () => context.push(Routes.addFriend),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: SignedInScope(
        message: 'Sign in to see friend requests.',
        child: RefreshIndicator(
          onRefresh: () => ref.read(friendsSnapshotProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (s.incoming.isEmpty && s.outgoing.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No requests right now.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (s.incoming.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Incoming', style: theme.textTheme.titleSmall),
                ),
              for (final r in s.incoming)
                ListTile(
                  leading: UserAvatar(
                    name: r.other.name,
                    avatarPath: r.other.avatarPath,
                  ),
                  title: Text(r.other.name),
                  subtitle: Text('@${r.other.handle}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'decline') repo.remove(r.other.id);
                          if (v == 'block') repo.block(r);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'decline',
                            child: Text('Decline'),
                          ),
                          PopupMenuItem(value: 'block', child: Text('Block')),
                        ],
                      ),
                      FilledButton(
                        onPressed: () => repo.accept(r),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                  onTap: () => context.push(Routes.userProfile(r.other.id)),
                ),
              if (s.outgoing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Sent', style: theme.textTheme.titleSmall),
                ),
              for (final r in s.outgoing)
                ListTile(
                  leading: UserAvatar(
                    name: r.other.name,
                    avatarPath: r.other.avatarPath,
                  ),
                  title: Text(r.other.name),
                  subtitle: Text('Waiting for @${r.other.handle}'),
                  trailing: TextButton(
                    onPressed: () => repo.remove(r.other.id),
                    child: const Text('Cancel'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
