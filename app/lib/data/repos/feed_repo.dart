import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../sync/outbox.dart';
import 'friends_repo.dart' show initialsOf;

/// Which slice of the feed is on screen (docs/01 §4.9).
class FeedFilter {
  const FeedFilter._(this.key, this.label, {this.friendId});

  static const all = FeedFilter._('all', 'All');

  /// Trip posts scored 90 or better.
  static const fame = FeedFilter._('fame', 'Wall of Fame');

  /// Reckless trips and shame posts.
  static const shame = FeedFilter._('shame', 'Wall of Shame');

  /// One friend's posts.
  factory FeedFilter.friend(String id, String name) =>
      FeedFilter._('friend:$id', name, friendId: id);

  final String key;
  final String label;
  final String? friendId;

  @override
  bool operator ==(Object other) => other is FeedFilter && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'FeedFilter($key)';
}

class FeedAuthor {
  const FeedAuthor({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarPath,
  });

  factory FeedAuthor.fromJson(String id, Map<String, dynamic>? j) => FeedAuthor(
    id: id,
    handle: j?['handle'] as String? ?? '',
    displayName: j?['display_name'] as String? ?? '',
    avatarPath: j?['avatar_path'] as String?,
  );

  final String id;
  final String handle;
  final String displayName;
  final String? avatarPath;

  String get name => displayName.trim().isNotEmpty ? displayName : '@$handle';
  String get initials => initialsOf(name);

  Map<String, dynamic> toJson() => {
    'handle': handle,
    'display_name': displayName,
    'avatar_path': avatarPath,
  };
}

/// One `feed_posts` row with its reactions and comment count.
class FeedPost {
  const FeedPost({
    required this.id,
    required this.author,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.tripId,
    this.reactions = const {},
    this.myReactions = const {},
    this.commentCount = 0,
  });

  /// From a `feed_posts` row selected with [FeedRepo.postSelect], seen by [me].
  factory FeedPost.fromRow(Map<String, dynamic> r, String? me) {
    final counts = <String, int>{};
    final mine = <String>{};
    for (final x in (r['feed_reactions'] as List?) ?? const []) {
      final m = (x as Map).cast<String, dynamic>();
      final kind = m['kind'] as String;
      counts[kind] = (counts[kind] ?? 0) + 1;
      if (m['user_id'] == me) mine.add(kind);
    }
    var comments = 0;
    final c = r['feed_comments'];
    if (c is List && c.isNotEmpty) {
      comments = ((c.first as Map)['count'] as num?)?.toInt() ?? 0;
    } else if (c is num) {
      comments = c.toInt();
    }
    final authorId = r['author_id'] as String;
    return FeedPost(
      id: r['id'] as String,
      author: FeedAuthor.fromJson(
        authorId,
        (r['profiles'] as Map?)?.cast<String, dynamic>(),
      ),
      kind: r['kind'] as String? ?? 'trip',
      tripId: r['trip_id'] as String?,
      body: (r['body'] as Map?)?.cast<String, dynamic>() ?? const {},
      createdAt: DateTime.parse(r['created_at'] as String).toUtc(),
      reactions: counts,
      myReactions: mine,
      commentCount: comments,
    );
  }

  final String id;
  final FeedAuthor author;

  /// trip | badge | league | convoy | shame
  final String kind;
  final String? tripId;
  final Map<String, dynamic> body;
  final DateTime createdAt;
  final Map<String, int> reactions;
  final Set<String> myReactions;
  final int commentCount;

  int? get score => (body['score'] as num?)?.toInt();

  String? get roastText {
    final r = body['roast'];
    if (r is String) return r;
    if (r is Map) return r['text'] as String?;
    return null;
  }

  bool get reckless => body['reckless'] == true || kind == 'shame';

  /// Whether the trip behind this post had a speeding event, which is what
  /// makes the Snitch reaction available.
  bool get hasSpeeding {
    if (body['speeding'] == true) return true;
    final events = body['events'];
    if (events is List) {
      return events.any((e) => e is Map && e['kind'] == 'speeding');
    }
    return false;
  }

  Map<String, dynamic>? get components =>
      (body['components'] as Map?)?.cast<String, dynamic>();

  FeedPost copyWith({
    Map<String, int>? reactions,
    Set<String>? myReactions,
    int? commentCount,
  }) => FeedPost(
    id: id,
    author: author,
    kind: kind,
    tripId: tripId,
    body: body,
    createdAt: createdAt,
    reactions: reactions ?? this.reactions,
    myReactions: myReactions ?? this.myReactions,
    commentCount: commentCount ?? this.commentCount,
  );

  /// Flips [kind] for the signed-in user, adjusting the count.
  FeedPost toggled(String kind) {
    final mine = Set<String>.of(myReactions);
    final counts = Map<String, int>.of(reactions);
    if (mine.remove(kind)) {
      final n = (counts[kind] ?? 1) - 1;
      if (n <= 0) {
        counts.remove(kind);
      } else {
        counts[kind] = n;
      }
    } else {
      mine.add(kind);
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    return copyWith(reactions: counts, myReactions: mine);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'author_id': author.id,
    'profiles': author.toJson(),
    'kind': kind,
    'trip_id': tripId,
    'body': body,
    'created_at': createdAt.toIso8601String(),
    'reactions': reactions,
    'my_reactions': myReactions.toList(),
    'comment_count': commentCount,
  };

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
    id: j['id'] as String,
    author: FeedAuthor.fromJson(
      j['author_id'] as String,
      (j['profiles'] as Map?)?.cast<String, dynamic>(),
    ),
    kind: j['kind'] as String,
    tripId: j['trip_id'] as String?,
    body: (j['body'] as Map?)?.cast<String, dynamic>() ?? const {},
    createdAt: DateTime.parse(j['created_at'] as String),
    reactions: ((j['reactions'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, (v as num).toInt()),
    ),
    myReactions: {
      for (final k in (j['my_reactions'] as List?) ?? const []) k as String,
    },
    commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
  );
}

class FeedComment {
  const FeedComment({
    required this.id,
    required this.postId,
    required this.author,
    required this.body,
    required this.createdAt,
    this.pending = false,
  });

  factory FeedComment.fromRow(Map<String, dynamic> r) => FeedComment(
    id: r['id'] as String,
    postId: r['post_id'] as String,
    author: FeedAuthor.fromJson(
      r['author_id'] as String,
      (r['profiles'] as Map?)?.cast<String, dynamic>(),
    ),
    body: r['body'] as String? ?? '',
    createdAt: DateTime.parse(r['created_at'] as String).toUtc(),
  );

  final String id;
  final String postId;
  final FeedAuthor author;
  final String body;
  final DateTime createdAt;

  /// Written locally, not yet confirmed by the server.
  final bool pending;
}

/// Reaction kinds in display order (docs/01 §4.9). Snitch is only offered on
/// posts with a speeding event.
const reactionKinds = ['fire', 'clap', 'laugh', 'skull', 'clown', 'snitch'];

String reactionEmoji(String kind) => switch (kind) {
  'fire' => '🔥',
  'clap' => '👏',
  'laugh' => '😂',
  'skull' => '💀',
  'clown' => '🤡',
  'snitch' => '🚨',
  _ => '👍',
};

String reactionLabel(String kind) =>
    kind == 'snitch' ? 'Snitch' : kind[0].toUpperCase() + kind.substring(1);

/// The public feed (docs/01 §4.2, §4.9). Pages of 20, cached per filter and
/// page; reactions and comments go through the outbox with optimistic local
/// state so the UI never waits on the network.
class FeedRepo {
  FeedRepo({
    required this.clientOf,
    required this.db,
    required this.outbox,
    required this.me,
    this.now = _nowMs,
  });

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// The Supabase client, or null in an offline build.
  final SupabaseClient? Function() clientOf;
  final AppDatabase db;
  final OutboxWorker outbox;

  /// The signed-in user's id, or null.
  final String? Function() me;
  final int Function() now;

  static const pageSize = 20;
  static const _uuid = Uuid();

  static const postSelect =
      '*, profiles!feed_posts_author_id_fkey(handle, display_name, avatar_path), '
      'feed_reactions(kind, user_id), feed_comments(count)';
  static const commentSelect =
      'id, post_id, author_id, body, created_at, '
      'profiles!feed_comments_author_id_fkey(handle, display_name, avatar_path)';

  // Outbox kinds.
  static const kindReaction =
      'reaction'; // {post_id, user_id, kind, op: add|remove}
  static const kindComment = 'comment'; // {id, post_id, author_id, body}

  static String cacheKey(FeedFilter filter, int page) =>
      'feed:${filter.key}:$page';

  SupabaseClient _online() {
    final c = clientOf();
    if (c == null || c.auth.currentSession == null) {
      throw const OutboxRetryLater('not signed in');
    }
    return c;
  }

  // ---------------------------------------------------------------- reads --

  Future<List<FeedPost>?> cachedPage(FeedFilter filter, int page) async {
    final json = await db.cacheGet(cacheKey(filter, page));
    if (json == null) return null;
    try {
      return [
        for (final p in jsonDecode(json) as List)
          FeedPost.fromJson((p as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }

  /// One page from the server, newest first, cached on success.
  Future<List<FeedPost>> fetchPage(FeedFilter filter, int page) async {
    final client = clientOf();
    if (client == null) return const [];
    var q = client.from('feed_posts').select(postSelect);
    if (filter == FeedFilter.fame) {
      q = q.eq('kind', 'trip').gte('body->score', 90);
    } else if (filter == FeedFilter.shame) {
      q = q.or('kind.eq.shame,body->reckless.eq.true');
    } else if (filter.friendId != null) {
      q = q.eq('author_id', filter.friendId!);
    }
    final rows = await q
        .order('created_at', ascending: false)
        .range(page * pageSize, page * pageSize + pageSize - 1);
    final uid = me();
    final posts = [for (final r in rows) FeedPost.fromRow(r, uid)];
    await db.cachePut(
      cacheKey(filter, page),
      jsonEncode([for (final p in posts) p.toJson()]),
      now(),
    );
    return posts;
  }

  Future<FeedPost?> fetchPost(String id) async {
    final client = clientOf();
    if (client == null) return null;
    final row = await client
        .from('feed_posts')
        .select(postSelect)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : FeedPost.fromRow(row, me());
  }

  Future<List<FeedComment>> fetchComments(String postId) async {
    final client = clientOf();
    if (client == null) return const [];
    final rows = await client
        .from('feed_comments')
        .select(commentSelect)
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return [for (final r in rows) FeedComment.fromRow(r)];
  }

  // --------------------------------------------------------------- writes --

  /// Queues the flip; the caller updates its own state with [FeedPost.toggled].
  Future<void> toggleReaction(FeedPost post, String kind) async {
    final uid = me();
    if (uid == null) return;
    final adding = !post.myReactions.contains(kind);
    await outbox.enqueue(kindReaction, {
      'post_id': post.id,
      'user_id': uid,
      'kind': kind,
      'op': adding ? 'add' : 'remove',
    });
  }

  /// Queues a comment and returns it as a pending [FeedComment].
  Future<FeedComment?> addComment(
    String postId,
    String body, {
    FeedAuthor? author,
  }) async {
    final uid = me();
    final text = body.trim();
    if (uid == null || text.isEmpty) return null;
    final clipped = text.length > 280 ? text.substring(0, 280) : text;
    final id = _uuid.v4();
    await outbox.enqueue(kindComment, {
      'id': id,
      'post_id': postId,
      'author_id': uid,
      'body': clipped,
    }, id: 'comment:$id');
    return FeedComment(
      id: id,
      postId: postId,
      author: author ?? FeedAuthor(id: uid, handle: '', displayName: 'You'),
      body: clipped,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now()),
      pending: true,
    );
  }

  // ----------------------------------------------------- outbox handlers --

  Future<void> handleReaction(Map<String, dynamic> p) async {
    final client = _online();
    if (p['user_id'] != me()) throw const OutboxSkip('another account');
    final row = <String, Object>{
      'post_id': p['post_id'] as Object,
      'user_id': p['user_id'] as Object,
      'kind': p['kind'] as Object,
    };
    if (p['op'] == 'remove') {
      await client.from('feed_reactions').delete().match(row);
    } else {
      await client
          .from('feed_reactions')
          .upsert(
            row,
            onConflict: 'post_id,user_id,kind',
            ignoreDuplicates: true,
          );
    }
  }

  Future<void> handleComment(Map<String, dynamic> p) async {
    final client = _online();
    if (p['author_id'] != me()) throw const OutboxSkip('another account');
    await client
        .from('feed_comments')
        .upsert(
          {
            'id': p['id'],
            'post_id': p['post_id'],
            'author_id': p['author_id'],
            'body': p['body'],
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        );
  }

  void registerHandlers(OutboxWorker worker) {
    worker.register(kindReaction, handleReaction);
    worker.register(kindComment, handleComment);
  }
}
