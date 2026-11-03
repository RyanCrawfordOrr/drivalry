import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/friends_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/repos/presence_repo.dart';
import '../../widgets/relative_time.dart';
import 'widgets/user_avatar.dart';

/// Friends with where they are, incoming requests on top, sent requests at
/// the bottom.
class FriendsListView extends ConsumerWidget {
  const FriendsListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(friendsSnapshotProvider);
    final presence = ref.watch(visiblePresenceProvider).value ?? const [];
    final byUser = {for (final p in presence) p.userId: p};
    final repo = ref.read(friendsRepoProvider);
    final theme = Theme.of(context);
    final s = snapshot.value ?? const FriendsSnapshot();
    final now = DateTime.now().toUtc();

    return RefreshIndicator(
      onRefresh: () => ref.read(friendsSnapshotProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 88),
        children: [
          if (snapshot.isLoading && s.friends.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (s.incoming.isNotEmpty) ...[
            _Header('Requests'),
            for (final r in s.incoming)
              ListTile(
                leading: UserAvatar(
                  name: r.other.name,
                  avatarPath: r.other.avatarPath,
                ),
                title: Text(r.other.name),
                subtitle: Text('@${r.other.handle} wants to be friends'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Decline',
                      onPressed: () => repo.remove(r.other.id),
                      icon: const Icon(Icons.close),
                    ),
                    FilledButton(
                      onPressed: () => repo.accept(r),
                      child: const Text('Accept'),
                    ),
                  ],
                ),
              ),
            const Divider(),
          ],
          _Header('Friends'),
          if (s.friends.isEmpty && !snapshot.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text('No friends yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Friends see each other on the map, in the feed and in '
                    'leagues. Add one with their handle or your invite link.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          for (final f in s.friends)
            _FriendTile(
              friend: f,
              presence: byUser[f.id],
              now: now,
              onRemove: () => _confirmRemove(context, repo, f),
            ),
          if (s.outgoing.isNotEmpty) ...[
            const Divider(),
            _Header('Sent'),
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
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    FriendsRepo repo,
    FriendProfile f,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${f.name}?'),
        content: const Text(
          'You will stop seeing each other on the map and in the feed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await repo.remove(f.id);
  }
}

class _FriendTile extends StatelessWidget {
  const _FriendTile({
    required this.friend,
    required this.presence,
    required this.now,
    required this.onRemove,
  });

  final FriendProfile friend;
  final PresenceRow? presence;
  final DateTime now;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = presence;
    final driving =
        p != null &&
        p.driving &&
        now.difference(p.updatedAt) < const Duration(hours: 24);
    final String where;
    if (p == null) {
      where = 'Not sharing location';
    } else if (driving) {
      where = 'Driving now';
    } else {
      where = 'Parked · ${relativeTime(p.updatedAt, now)}';
    }
    final rating = friend.driverRating;
    return ListTile(
      leading: UserAvatar(
        name: friend.name,
        avatarPath: friend.avatarPath,
        highlighted: driving,
      ),
      title: Text(friend.name),
      subtitle: Text(
        rating == null ? where : '$where · rating ${rating.toStringAsFixed(0)}',
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'remove') onRemove();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'remove', child: Text('Remove friend')),
        ],
      ),
      onTap: () => context.push(Routes.userProfile(friend.id)),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
