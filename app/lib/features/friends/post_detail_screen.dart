import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/feed_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../widgets/relative_time.dart';
import '../../widgets/signed_in_scope.dart';
import 'feed_controller.dart';
import 'feed_post_card.dart';
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
      if (mounted) setState(() => _error = 'Could not load: $e');
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
    _composer.clear();
    setState(() {
      _comments = [..._comments, added];
      _post = post.copyWith(commentCount: post.commentCount + 1);
    });
    ref.read(feedControllerProvider.notifier).bumpCommentCount(post.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = ref.read(feedControllerProvider.notifier);
    // Keep reaction state in step with the feed when the post is there too.
    final fromFeed = ref.watch(
      feedControllerProvider.select(
        (s) => s.posts.where((p) => p.id == widget.postId).firstOrNull,
      ),
    );
    final post = fromFeed ?? _post;
    final now = DateTime.now().toUtc();
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: SignedInScope(
        message: 'Sign in to see posts.',
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    if (post == null)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: _loading
                              ? const CircularProgressIndicator()
                              : Text(_error ?? 'Post not found.'),
                        ),
                      )
                    else
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
                    if (_error != null && post != null)
                      Text(_error!, style: theme.textTheme.bodySmall),
                    if (post != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                        child: Text(
                          _comments.isEmpty
                              ? 'No comments yet'
                              : '${_comments.length} comment${_comments.length == 1 ? '' : 's'}',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    for (final c in _comments)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: UserAvatar(
                          name: c.author.name,
                          avatarPath: c.author.avatarPath,
                          radius: 16,
                        ),
                        title: Text(c.body),
                        subtitle: Text(
                          '${c.author.name} · ${c.pending ? 'sending…' : relativeTime(c.createdAt, now)}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (post != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _composer,
                          maxLength: 280,
                          decoration: const InputDecoration(
                            hintText: 'Say something about this drive',
                            border: OutlineInputBorder(),
                            counterText: '',
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 8),
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
