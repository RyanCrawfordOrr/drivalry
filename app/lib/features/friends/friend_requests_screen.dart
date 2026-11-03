import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/friends_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../widgets/signed_in_scope.dart';
import 'friends_list_view.dart' show DeclineBackground;
import 'widgets/decline_with_undo.dart';
import 'widgets/person_row.dart';

/// Incoming and sent friend requests. Accept is the row's button; swipe left
/// or the overflow declines (with Undo); Block lives in the overflow.
class FriendRequestsScreen extends ConsumerStatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  ConsumerState<FriendRequestsScreen> createState() =>
      _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends ConsumerState<FriendRequestsScreen> {
  final _declining = <String>{};

  @override
  Widget build(BuildContext context) {
    final s =
        ref.watch(friendsSnapshotProvider).value ?? const FriendsSnapshot();
    final repo = ref.read(friendsRepoProvider);
    final incoming = [
      for (final r in s.incoming)
        if (!_declining.contains(r.other.id)) r,
    ];
    final empty = incoming.isEmpty && s.outgoing.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Friend requests')),
      body: SignedInScope(
        message: 'Sign in to see friend requests.',
        child: RefreshIndicator(
          onRefresh: () => ref.read(friendsSnapshotProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
            children: [
              StateSwitcher(
                child: empty
                    ? EmptyState(
                        key: const ValueKey('empty'),
                        kicker: 'Requests',
                        headline: 'No requests right now.',
                        body: 'When someone adds you, they show up here.',
                        actionLabel: 'Add friend',
                        onAction: () => context.push(Routes.addFriend),
                      )
                    : Column(
                        key: const ValueKey('list'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (incoming.isNotEmpty)
                            EditorialSection(
                              kicker: 'Incoming',
                              child: Column(
                                children: [
                                  for (var i = 0; i < incoming.length; i++)
                                    Reveal(
                                      delay: Reveal.stagger(i),
                                      child: _IncomingRow(
                                        request: incoming[i],
                                        onAccept: () {
                                          Haptics.success();
                                          repo.accept(incoming[i]);
                                        },
                                        onDecline: () =>
                                            _decline(repo, incoming[i]),
                                        onBlock: () => repo.block(incoming[i]),
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
                                          '@${r.other.handle} · '
                                          'not answered yet',
                                      trailing: TextButton(
                                        onPressed: () =>
                                            repo.remove(r.other.id),
                                        child: const Text('Cancel'),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
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
}

class _IncomingRow extends StatelessWidget {
  const _IncomingRow({
    required this.request,
    required this.onAccept,
    required this.onDecline,
    required this.onBlock,
  });

  final FriendRequest request;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onBlock;

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
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'decline') onDecline();
                if (v == 'block') onBlock();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'decline', child: Text('Decline')),
                PopupMenuItem(value: 'block', child: Text('Block')),
              ],
            ),
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
