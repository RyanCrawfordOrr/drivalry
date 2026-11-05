import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/friends_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/repos/moderation_repo.dart';
import '../../data/repos/presence_repo.dart';
import 'moderation_actions.dart';
import 'widgets/decline_with_undo.dart';
import 'widgets/live_badge.dart';
import 'widgets/page_insets.dart';
import 'widgets/person_row.dart';
import 'widgets/tab_scroll_view.dart';

/// Friends as rows (avatar, name, handle and Driver rating), incoming
/// requests on top, sent requests at the bottom. A request can be swiped
/// away to decline, and declining gets an Undo. The Friends root wraps this
/// in pull to refresh.
class FriendsListView extends ConsumerStatefulWidget {
  const FriendsListView({super.key});

  @override
  ConsumerState<FriendsListView> createState() => _FriendsListViewState();
}

class _FriendsListViewState extends ConsumerState<FriendsListView> {
  /// Requests hidden while their Undo snackbar is up.
  final _declining = <String>{};

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(friendsSnapshotProvider);
    final presence = ref.watch(visiblePresenceProvider).value ?? const [];
    final byUser = {for (final p in presence) p.userId: p};
    final repo = ref.read(friendsRepoProvider);
    final s = snapshot.value ?? const FriendsSnapshot();
    final now = DateTime.now().toUtc();
    final incoming = [
      for (final r in s.incoming)
        if (!_declining.contains(r.other.id)) r,
    ];
    final skeletons =
        snapshot.isLoading && s.friends.isEmpty && s.incoming.isEmpty;

    return TabScrollView(
      slivers: [
        SliverPadding(
          // The empty state brings its own 48 on top; a list starts 16 under
          // the tabs.
          padding: EdgeInsets.only(
            top: incoming.isEmpty && s.friends.isEmpty && !skeletons
                ? 0
                : Space.lg,
            bottom: pageBottomInset(context),
          ),
          sliver: SliverToBoxAdapter(
            child: StateSwitcher(
              child: skeletons
                  ? Column(
                      key: const ValueKey('skeleton'),
                      children: [
                        for (var i = 0; i < 3; i++)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(
                              Space.gutter,
                              0,
                              Space.gutter,
                              Space.md,
                            ),
                            child: SkeletonTile(height: 56),
                          ),
                      ],
                    )
                  : Column(
                      key: const ValueKey('list'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (incoming.isNotEmpty)
                          EditorialSection(
                            kicker: 'Requests',
                            child: Column(
                              children: [
                                for (var i = 0; i < incoming.length; i++)
                                  Reveal(
                                    delay: Reveal.stagger(i),
                                    child: _RequestRow(
                                      request: incoming[i],
                                      onAccept: () {
                                        Haptics.success();
                                        repo.accept(incoming[i]);
                                      },
                                      onDecline: () =>
                                          _decline(repo, incoming[i]),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (s.friends.isEmpty)
                          EmptyState(
                            kicker: 'Friends',
                            headline: 'No friends yet.',
                            body: 'Add one by handle or share your link.',
                            actionLabel: 'Add friend',
                            onAction: () => context.push(Routes.addFriend),
                          )
                        else
                          EditorialSection(
                            kicker: 'Friends',
                            child: Column(
                              children: [
                                for (var i = 0; i < s.friends.length; i++)
                                  Reveal(
                                    delay: Reveal.stagger(i),
                                    child: _FriendRow(
                                      friend: s.friends[i],
                                      presence: byUser[s.friends[i].id],
                                      now: now,
                                      onRemove: () => _confirmRemove(
                                        context,
                                        repo,
                                        s.friends[i],
                                      ),
                                      onBlock: () => blockUserFlow(
                                        context,
                                        ref,
                                        BlockedUser(
                                          id: s.friends[i].id,
                                          handle: s.friends[i].handle,
                                          displayName: s.friends[i].displayName,
                                          avatarPath: s.friends[i].avatarPath,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        if (s.outgoing.isNotEmpty)
                          EditorialSection(
                            kicker: 'Sent',
                            child: Column(
                              children: [
                                for (final r in s.outgoing)
                                  PersonRow(
                                    name: r.other.name,
                                    avatarPath: r.other.avatarPath,
                                    caption:
                                        '@${r.other.handle} · not answered yet',
                                    trailing: TextButton(
                                      onPressed: () => repo.remove(r.other.id),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  void _decline(FriendsRepo repo, FriendRequest r) {
    declineWithUndo(
      context,
      request: r,
      repo: repo,
      onHidden: (hidden) {
        if (!mounted) return;
        setState(() {
          if (hidden) {
            _declining.add(r.other.id);
          } else {
            _declining.remove(r.other.id);
          }
        });
      },
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
          'You stop seeing each other on the map and in the feed.',
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

/// An incoming request: swipe left to decline, or use the buttons.
class _RequestRow extends StatelessWidget {
  const _RequestRow({
    required this.request,
    required this.onAccept,
    required this.onDecline,
  });

  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Dismissible(
      key: ValueKey('request-${r.other.id}'),
      direction: DismissDirection.endToStart,
      background: const DeclineBackground(),
      onDismissed: (_) => onDecline(),
      child: PersonRow(
        name: r.other.name,
        avatarPath: r.other.avatarPath,
        caption: '@${r.other.handle}',
        heroTag: 'avatar-${r.other.id}',
        onTap: () => context.push(Routes.userProfile(r.other.id)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Decline',
              onPressed: onDecline,
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: Space.sm),
            FilledButton.tonal(
              onPressed: onAccept,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, Sizes.touch),
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              ),
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What shows behind a request as it is swiped away.
class DeclineBackground extends StatelessWidget {
  const DeclineBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: Radii.tileRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.close, color: scheme.onErrorContainer),
          const SizedBox(width: Space.sm),
          Text(
            'Decline',
            style: context.label.copyWith(color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({
    required this.friend,
    required this.presence,
    required this.now,
    required this.onRemove,
    required this.onBlock,
  });

  final FriendProfile friend;
  final PresenceRow? presence;
  final DateTime now;
  final VoidCallback onRemove;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final p = presence;
    final driving =
        p != null &&
        p.driving &&
        now.difference(p.updatedAt) < const Duration(hours: 24);
    final rating = friend.driverRating;
    final caption = [
      '@${friend.handle}',
      if (rating != null) 'Driver rating ${rating.toStringAsFixed(0)}',
    ].join(' · ');
    return PersonRow(
      name: friend.name,
      avatarPath: friend.avatarPath,
      caption: caption,
      highlighted: driving,
      heroTag: 'avatar-${friend.id}',
      badge: driving ? const LiveBadge('Driving') : null,
      trailing: PopupMenuButton<String>(
        tooltip: 'More',
        onSelected: (v) {
          if (v == 'remove') onRemove();
          if (v == 'block') onBlock();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'remove', child: Text('Remove friend')),
          PopupMenuItem(value: 'block', child: Text('Block')),
        ],
      ),
      onTap: () => context.push(Routes.userProfile(friend.id)),
    );
  }
}
