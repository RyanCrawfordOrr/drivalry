import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/feed_repo.dart';
import '../../data/repos/friends_sync.dart';
import 'feed_controller.dart';
import 'feed_post_card.dart';

/// The feed segment of the Friends tab: filters, posts, pull to refresh,
/// load more near the end.
class FeedView extends ConsumerStatefulWidget {
  const FeedView({super.key});

  @override
  ConsumerState<FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends ConsumerState<FeedView> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(feedControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);
    final theme = Theme.of(context);
    return Column(
      children: [
        _FilterBar(current: feed.filter, onPick: controller.setFilter),
        if (feed.error != null)
          MaterialBanner(
            content: Text(feed.error!),
            actions: [
              TextButton(
                onPressed: controller.refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            child: feed.posts.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 48,
                        ),
                        child: Column(
                          children: [
                            if (feed.loading)
                              const CircularProgressIndicator()
                            else
                              Icon(
                                Icons.dynamic_feed_outlined,
                                size: 48,
                                color: theme.colorScheme.outline,
                              ),
                            const SizedBox(height: 12),
                            Text(
                              feed.loading ? 'Loading…' : 'Nothing here yet',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Trips your friends finish show up here with the '
                              'score and the roast. Add a friend to get started.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                    itemCount: feed.posts.length + (feed.hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= feed.posts.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final post = feed.posts[i];
                      return FeedPostCard(
                        post: post,
                        onReact: (k) => controller.toggleReaction(post.id, k),
                        onOpen: () => context.push(Routes.post(post.id)),
                      );
                    },
                  ),
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (final f in [FeedFilter.all, FeedFilter.fame, FeedFilter.shame])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.label),
                selected: current == f,
                onSelected: (_) => onPick(f),
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
    final picked = await showModalBottomSheet<FeedFilter>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final f in friends)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(f.name),
              subtitle: Text('@${f.handle}'),
              onTap: () =>
                  Navigator.of(ctx).pop(FeedFilter.friend(f.id, f.name)),
            ),
        ],
      ),
    );
    if (picked != null) onPick(picked);
  }
}
