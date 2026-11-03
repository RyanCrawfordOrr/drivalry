import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/feed_repo.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/friendly_error.dart';

class FeedState {
  const FeedState({
    this.filter = FeedFilter.all,
    this.posts = const [],
    this.loading = false,
    this.hasMore = true,
    this.page = 0,
    this.error,
  });

  final FeedFilter filter;
  final List<FeedPost> posts;
  final bool loading;
  final bool hasMore;
  final int page;
  final String? error;

  FeedState copyWith({
    FeedFilter? filter,
    List<FeedPost>? posts,
    bool? loading,
    bool? hasMore,
    int? page,
    String? error,
    bool clearError = false,
  }) => FeedState(
    filter: filter ?? this.filter,
    posts: posts ?? this.posts,
    loading: loading ?? this.loading,
    hasMore: hasMore ?? this.hasMore,
    page: page ?? this.page,
    error: clearError ? null : (error ?? this.error),
  );
}

/// The feed on screen: cached page first, then the network; pages of 20;
/// optimistic reactions (docs/03 §7).
class FeedController extends Notifier<FeedState> {
  FeedRepo get _repo => ref.read(feedRepoProvider);

  @override
  FeedState build() {
    // Re-run on sign-in and sign-out.
    final signedIn = ref.watch(currentUserIdProvider) != null;
    if (signedIn) Future.microtask(() => _load(fromCache: true));
    return const FeedState();
  }

  Future<void> _load({bool fromCache = false}) async {
    final filter = state.filter;
    state = state.copyWith(loading: true, clearError: true);
    if (fromCache) {
      final cached = await _repo.cachedPage(filter, 0);
      if (cached != null && state.filter == filter) {
        state = state.copyWith(posts: cached, page: 0);
      }
    }
    try {
      final fresh = await _repo.fetchPage(filter, 0);
      if (state.filter != filter) return;
      state = state.copyWith(
        posts: fresh,
        page: 0,
        hasMore: fresh.length >= FeedRepo.pageSize,
        loading: false,
        clearError: true,
      );
    } catch (e) {
      if (state.filter != filter) return;
      state = state.copyWith(
        loading: false,
        error: friendlyError(e, doing: 'refresh the feed'),
      );
    }
  }

  Future<void> refresh() => _load();

  Future<void> setFilter(FeedFilter filter) {
    if (filter == state.filter) return refresh();
    state = FeedState(filter: filter);
    return _load(fromCache: true);
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    final filter = state.filter;
    final next = state.page + 1;
    state = state.copyWith(loading: true);
    try {
      final more = await _repo.fetchPage(filter, next);
      if (state.filter != filter) return;
      final seen = {for (final p in state.posts) p.id};
      state = state.copyWith(
        posts: [
          ...state.posts,
          for (final p in more)
            if (!seen.contains(p.id)) p,
        ],
        page: next,
        hasMore: more.length >= FeedRepo.pageSize,
        loading: false,
      );
    } catch (e) {
      if (state.filter != filter) return;
      state = state.copyWith(
        loading: false,
        error: friendlyError(e, doing: 'load more'),
      );
    }
  }

  /// Flips a reaction locally at once and queues the write.
  Future<void> toggleReaction(String postId, String kind) async {
    final i = state.posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final post = state.posts[i];
    final posts = List<FeedPost>.of(state.posts)..[i] = post.toggled(kind);
    state = state.copyWith(posts: posts);
    await _repo.toggleReaction(post, kind);
  }

  /// A comment was added on the detail screen.
  void bumpCommentCount(String postId) {
    final i = state.posts.indexWhere((p) => p.id == postId);
    if (i < 0) return;
    final posts = List<FeedPost>.of(state.posts)
      ..[i] = state.posts[i].copyWith(
        commentCount: state.posts[i].commentCount + 1,
      );
    state = state.copyWith(posts: posts);
  }

  FeedPost? postById(String id) {
    for (final p in state.posts) {
      if (p.id == id) return p;
    }
    return null;
  }
}

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(
  FeedController.new,
);
