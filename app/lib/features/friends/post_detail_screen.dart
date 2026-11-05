import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/repos/feed_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/repos/moderation_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/relative_time.dart';
import '../../widgets/signed_in_scope.dart';
import 'feed_controller.dart';
import 'feed_post_card.dart';
import 'moderation_actions.dart';
import 'widgets/page_insets.dart';
import 'widgets/quiet_error_tile.dart';
import 'widgets/user_avatar.dart';

/// One post with its comments and a composer (docs/01 §4.9).
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _composer = TextEditingController();
  FeedPost? _post;
  List<FeedComment> _comments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(feedRepoProvider);
    setState(() {
      _loading = true;
      _error = null;
    });
    _post ??= ref.read(feedControllerProvider.notifier).postById(widget.postId);
    try {
      final results = await Future.wait([
        repo.fetchPost(widget.postId),
        repo.fetchComments(widget.postId),
      ]);
      if (!mounted) return;
      setState(() {
        _post = (results[0] as FeedPost?) ?? _post;
        _comments = results[1] as List<FeedComment>;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyError(e, doing: 'load the comments'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final post = _post;
    final text = _composer.text.trim();
    if (post == null || text.isEmpty) return;
    final added = await ref.read(feedRepoProvider).addComment(post.id, text);
    if (added == null || !mounted) return;
    Haptics.tap();
    _composer.clear();
    setState(() {
      _comments = [..._comments, added];
      _post = post.copyWith(commentCount: post.commentCount + 1);
    });
    ref.read(feedControllerProvider.notifier).bumpCommentCount(post.id);
  }

  /// Long-press on someone else's comment: report it or block them.
  Future<void> _commentActions(FeedComment c) async {
    final choice = await showDrivalrySheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ModerationActionTile(
            icon: Icons.flag_outlined,
            label: 'Report comment',
            onTap: () => Navigator.of(ctx).pop('report'),
          ),
          const SizedBox(height: Space.sm),
          ModerationActionTile(
            icon: Icons.block_outlined,
            label: 'Block ${c.author.name}',
            danger: true,
            onTap: () => Navigator.of(ctx).pop('block'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'report':
        await reportCommentFlow(context, ref, c);
      case 'block':
        await blockUserFlow(
          context,
          ref,
          BlockedUser(
            id: c.author.id,
            handle: c.author.handle,
            displayName: c.author.displayName,
            avatarPath: c.author.avatarPath,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(feedControllerProvider.notifier);
    // Keep reaction state in step with the feed when the post is there too.
    final fromFeed = ref.watch(
      feedControllerProvider.select(
        (s) => s.posts.where((p) => p.id == widget.postId).firstOrNull,
      ),
    );
    final post = fromFeed ?? _post;
    final now = DateTime.now().toUtc();
    final me = ref.watch(currentUserIdProvider);
    final moderation =
        ref.watch(moderationStateProvider).value ?? const ModerationState();
    final comments = [
      for (final c in _comments)
        if (moderation.showsComment(c.id, c.author.id)) c,
    ];
    final own = post == null || post.author.id == me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          if (!own)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                switch (v) {
                  case 'report':
                    await reportPostFlow(context, ref, post);
                    if (context.mounted) Navigator.of(context).maybePop();
                  case 'block':
                    final blocked = await blockUserFlow(
                      context,
                      ref,
                      BlockedUser(
                        id: post.author.id,
                        handle: post.author.handle,
                        displayName: post.author.displayName,
                        avatarPath: post.author.avatarPath,
                      ),
                    );
                    if (blocked && context.mounted) {
                      Navigator.of(context).maybePop();
                    }
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report post'),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Text('Block ${post.author.name}'),
                ),
              ],
            ),
        ],
      ),
      body: SignedInScope(
        message: 'Sign in to see posts.',
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  // The composer below carries the bottom inset when there
                  // is a post to comment on.
                  padding: EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.lg,
                    Space.gutter,
                    post == null ? pageBottomInset(context) : Space.xl,
                  ),
                  children: [
                    if (post == null)
                      if (_loading)
                        const SkeletonTile(height: 168)
                      else if (_error != null)
                        QuietErrorTile(message: _error!, onRetry: _load)
                      else
                        const EmptyState(
                          headline: 'Post not found.',
                          body: 'The author may have deleted it.',
                        )
                    else ...[
                      FeedPostCard(
                        post: post,
                        expanded: true,
                        onReact: (k) async {
                          if (fromFeed != null) {
                            await controller.toggleReaction(post.id, k);
                          } else {
                            setState(() => _post = post.toggled(k));
                            await ref
                                .read(feedRepoProvider)
                                .toggleReaction(post, k);
                          }
                        },
                      ),
                      const SizedBox(height: Space.section),
                      if (_error != null) ...[
                        QuietErrorTile(message: _error!, onRetry: _load),
                        const SizedBox(height: Space.lg),
                      ],
                      const Kicker('Comments'),
                      const SizedBox(height: Space.sm),
                      if (_loading && comments.isEmpty)
                        const SkeletonTile(height: 56)
                      else if (comments.isEmpty)
                        Text(
                          'Nothing yet. Say something about this drive.',
                          style: context.bodyMuted,
                        ),
                      for (final c in comments)
                        _CommentRow(
                          comment: c,
                          now: now,
                          onLongPress: c.author.id == me || c.pending
                              ? null
                              : () => _commentActions(c),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if (post != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.xs,
                    Space.gutter,
                    Space.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composer,
                          maxLength: 280,
                          decoration: const InputDecoration(
                            hintText: 'Say something',
                            counterText: '',
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.now,
    this.onLongPress,
  });
  final FeedComment comment;
  final DateTime now;

  /// Report or block, on someone else's comment.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final when = comment.pending
        ? 'sending…'
        : relativeTime(comment.createdAt, now);
    return InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              name: comment.author.name,
              avatarPath: comment.author.avatarPath,
              size: AvatarSize.sm,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(comment.body, style: context.body),
                  const SizedBox(height: Space.xs),
                  Text(
                    '${comment.author.name} · $when',
                    style: context.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
