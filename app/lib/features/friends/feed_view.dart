import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/feed_repo.dart';
import '../../data/repos/friends_sync.dart';
import 'feed_controller.dart';
import 'feed_post_card.dart';
import 'post_actions_sheet.dart';
import 'widgets/person_row.dart';
import 'widgets/quiet_error_tile.dart';
import 'widgets/tab_scroll_view.dart';

/// Room under a list for the extended FAB (docs/12 §2: tokens only).
const double fabClearance = Space.xxxl * 2;

const _cardPadding = EdgeInsets.fromLTRB(
  Space.gutter,
  0,
  Space.gutter,
  Space.xl,
);

/// The feed segment of the Friends tab: filters, posts 24 apart that arrive
/// staggered, load more near the end. Loading shimmers, an empty feed shows
/// one Add friend button, and a failure is a quiet tile with Retry. The
/// Friends root wraps it in pull to refresh.
class FeedView extends ConsumerWidget {
  const FeedView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);
    final error = feed.error;
    final skeletons = feed.loading && feed.posts.isEmpty;
    final empty = !skeletons && feed.posts.isEmpty;
    final mode = skeletons
        ? 'skeleton'
        : empty
        ? 'empty'
        : 'posts';
    // Hero tags must be unique on a screen: only an author's first post
    // carries the avatar hero.
    final firstByAuthor = <String, int>{};
    for (var i = 0; i < feed.posts.length; i++) {
      firstByAuthor.putIfAbsent(feed.posts[i].author.id, () => i);
    }

    return TabScrollView(
      onScroll: (m) {
        if (m.extentAfter < 600) controller.loadMore();
      },
      slivers: [
        SliverToBoxAdapter(
          child: _FilterBar(current: feed.filter, onPick: controller.setFilter),
        ),
        if (error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: _cardPadding,
              child: QuietErrorTile(
                message: error,
                onRetry: controller.refresh,
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: StateSwitcher(
            child: switch (mode) {
              'skeleton' => Column(
                key: const ValueKey('skeleton'),
                children: [
                  for (var i = 0; i < 3; i++)
                    const Padding(
                      padding: _cardPadding,
                      child: SkeletonTile(height: 168),
                    ),
                ],
              ),
              'empty' => EmptyState(
                key: const ValueKey('empty'),
                kicker: 'Feed',
                headline: 'Nothing yet.',
                body: 'Add a friend and the roasts start.',
                actionLabel: 'Add friend',
                onAction: () => context.push(Routes.addFriend),
              ),
              _ => const SizedBox.shrink(key: ValueKey('posts')),
            },
          ),
        ),
        if (mode == 'posts')
          SliverPadding(
            padding: const EdgeInsets.only(bottom: fabClearance),
            sliver: SliverList.builder(
              itemCount: feed.posts.length + (feed.hasMore ? 1 : 0),
              itemBuilder: (context, j) {
                if (j >= feed.posts.length) {
                  return const Padding(
                    padding: _cardPadding,
                    child: SkeletonTile(),
                  );
                }
                final post = feed.posts[j];
                void react(String k) => controller.toggleReaction(post.id, k);
                void open() => context.push(Routes.post(post.id));
                return Padding(
                  padding: _cardPadding,
                  child: Reveal(
                    delay: Reveal.stagger(j),
                    child: FeedPostCard(
                      post: post,
                      heroAvatar: firstByAuthor[post.author.id] == j,
                      onReact: react,
                      onOpen: open,
                      onLongPress: () => showPostActions(
                        context,
                        post: post,
                        onReact: react,
                        onComment: open,
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: fabClearance)),
      ],
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.current, required this.onPick});
  final FeedFilter current;
  final void Function(FeedFilter) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendFilterActive = current.friendId != null;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.xs,
      ),
      child: Row(
        children: [
          for (final f in [FeedFilter.all, FeedFilter.fame, FeedFilter.shame])
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: ChoiceChip(
                label: Text(f.label),
                selected: current == f,
                onSelected: (_) {
                  Haptics.select();
                  onPick(f);
                },
              ),
            ),
          ChoiceChip(
            avatar: friendFilterActive
                ? null
                : const Icon(Icons.person_search_outlined, size: 18),
            label: Text(friendFilterActive ? current.label : 'A friend'),
            selected: friendFilterActive,
            onSelected: (_) => _pickFriend(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFriend(BuildContext context, WidgetRef ref) async {
    final friends =
        ref.read(friendsSnapshotProvider).value?.friends ?? const [];
    if (friends.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add a friend first.')));
      return;
    }
    final picked = await showDrivalrySheet<FeedFilter>(
      context,
      title: 'Whose drives?',
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final f in friends)
              PersonRow(
                name: f.name,
                avatarPath: f.avatarPath,
                caption: '@${f.handle}',
                onTap: () =>
                    Navigator.of(ctx).pop(FeedFilter.friend(f.id, f.name)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) onPick(picked);
  }
}
