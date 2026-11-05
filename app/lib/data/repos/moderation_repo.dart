import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'friends_repo.dart' show initialsOf;

/// Why a post or comment was reported. The wire names are the
/// `content_reports.reason` check constraint (migration 0008).
enum ReportReason {
  abusive('abusive', 'Abusive or hateful'),
  notDriving('not_driving', 'Not about the drive'),
  spam('spam', 'Spam or a scam'),
  other('other', 'Something else');

  const ReportReason(this.wire, this.label);
  final String wire;
  final String label;
}

/// Someone the signed-in user blocked, as the Blocked people screen shows
/// them. Kept in the cache at block time so the screen needs no network.
class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarPath,
    this.blockedAt,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
    id: j['id'] as String,
    handle: j['handle'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    avatarPath: j['avatar_path'] as String?,
    blockedAt: DateTime.tryParse(j['blocked_at'] as String? ?? ''),
  );

  final String id;
  final String handle;
  final String displayName;
  final String? avatarPath;
  final DateTime? blockedAt;

  String get name => displayName.trim().isNotEmpty ? displayName : '@$handle';
  String get initials => initialsOf(name);

  Map<String, dynamic> toJson() => {
    'id': id,
    'handle': handle,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'blocked_at': blockedAt?.toUtc().toIso8601String(),
  };
}

/// Who is blocked and which posts the user reported, as one cacheable value.
class ModerationState {
  const ModerationState({
    this.blocked = const [],
    this.hiddenPostIds = const {},
    this.hiddenCommentIds = const {},
  });

  final List<BlockedUser> blocked;

  /// Posts the user reported: hidden for them from the moment they tap.
  final Set<String> hiddenPostIds;
  final Set<String> hiddenCommentIds;

  bool isBlocked(String userId) => blocked.any((b) => b.id == userId);
  bool isHiddenPost(String postId) => hiddenPostIds.contains(postId);
  bool isHiddenComment(String commentId) =>
      hiddenCommentIds.contains(commentId);

  /// Whether a post by [authorId] with id [postId] should be on screen.
  bool showsPost(String postId, String authorId) =>
      !isBlocked(authorId) && !isHiddenPost(postId);

  bool showsComment(String commentId, String authorId) =>
      !isBlocked(authorId) && !isHiddenComment(commentId);

  ModerationState copyWith({
    List<BlockedUser>? blocked,
    Set<String>? hiddenPostIds,
    Set<String>? hiddenCommentIds,
  }) => ModerationState(
    blocked: blocked ?? this.blocked,
    hiddenPostIds: hiddenPostIds ?? this.hiddenPostIds,
    hiddenCommentIds: hiddenCommentIds ?? this.hiddenCommentIds,
  );

  Map<String, dynamic> toJson() => {
    'blocked': [for (final b in blocked) b.toJson()],
    'hidden_posts': hiddenPostIds.toList(),
    'hidden_comments': hiddenCommentIds.toList(),
  };

  factory ModerationState.fromJson(Map<String, dynamic> j) => ModerationState(
    blocked: [
      for (final b in (j['blocked'] as List?) ?? const [])
        BlockedUser.fromJson((b as Map).cast<String, dynamic>()),
    ],
    hiddenPostIds: {
      for (final id in (j['hidden_posts'] as List?) ?? const []) id as String,
    },
    hiddenCommentIds: {
      for (final id in (j['hidden_comments'] as List?) ?? const [])
        id as String,
    },
  );
}

/// Blocking people and reporting content (docs/05 §1). Writes go through the
/// outbox so they survive being offline; the cache is updated first so the
/// feed reacts at once. Reads of `user_blocks` refresh the cached list.
class ModerationRepo {
  ModerationRepo({
    required this.clientOf,
    required this.db,
    required this.outbox,
    required this.me,
    this.now = _nowMs,
  });

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  static const _uuid = Uuid();

  /// The Supabase client, or null in an offline build.
  final SupabaseClient? Function() clientOf;
  final AppDatabase db;
  final OutboxWorker outbox;

  /// The signed-in user's id, or null.
  final String? Function() me;
  final int Function() now;

  static const cacheKey = 'moderation:state';

  // Outbox kinds and payloads.
  /// `{blocker_id, blocked_id}`
  static const kindBlock = 'user_block';

  /// `{blocker_id, blocked_id}`
  static const kindUnblock = 'user_unblock';

  /// `{id, reporter_id, reported_user_id, post_id, comment_id, reason,
  /// details, snapshot}`
  static const kindReport = 'content_report';

  static const _blockSelect =
      'blocked_id, created_at, '
      'profiles!user_blocks_blocked_id_fkey(handle, display_name, avatar_path)';

  SupabaseClient _online() {
    final c = clientOf();
    if (c == null || c.auth.currentSession == null) {
      throw const OutboxRetryLater('not signed in');
    }
    return c;
  }

  // ---------------------------------------------------------------- reads --

  Future<ModerationState> cached() async {
    final json = await db.cacheGet(cacheKey);
    return _decode(json);
  }

  Stream<ModerationState> watchCached() => db.watchCache(cacheKey).map(_decode);

  static ModerationState _decode(String? json) {
    if (json == null) return const ModerationState();
    try {
      return ModerationState.fromJson(
        (jsonDecode(json) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return const ModerationState();
    }
  }

  Future<void> _store(ModerationState s) =>
      db.cachePut(cacheKey, jsonEncode(s.toJson()), now());

  /// Pulls the block list from the server; hidden posts are local only.
  Future<ModerationState> refresh() async {
    final client = clientOf();
    final uid = me();
    if (client == null || uid == null) return cached();
    final rows = await client
        .from('user_blocks')
        .select(_blockSelect)
        .eq('blocker_id', uid)
        .order('created_at', ascending: false);
    final blocked = [
      for (final r in rows)
        BlockedUser(
          id: r['blocked_id'] as String,
          handle: (r['profiles'] as Map?)?['handle'] as String? ?? '',
          displayName:
              (r['profiles'] as Map?)?['display_name'] as String? ?? '',
          avatarPath: (r['profiles'] as Map?)?['avatar_path'] as String?,
          blockedAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        ),
    ];
    final current = await cached();
    // A block queued offline is not on the server yet; keep it.
    final pending = [
      for (final b in current.blocked)
        if (!blocked.any((x) => x.id == b.id) && await _blockQueued(b.id)) b,
    ];
    final next = current.copyWith(blocked: [...blocked, ...pending]);
    await _store(next);
    return next;
  }

  /// Whether the block of [blockedId] is still waiting in the outbox (the
  /// row id is deterministic, see [block]).
  Future<bool> _blockQueued(String blockedId) async {
    final uid = me();
    if (uid == null) return false;
    final row = await (db.select(
      db.outbox,
    )..where((o) => o.id.equals('block:$uid:$blockedId'))).getSingleOrNull();
    return row != null;
  }

  // --------------------------------------------------------------- writes --

  /// Blocks [user]. The server trigger ends the friendship; the caller drops
  /// the person from the friends cache (see [FriendsRepo.forgetLocal]).
  Future<void> block(BlockedUser user) async {
    final uid = me();
    if (uid == null || user.id == uid) return;
    await outbox.enqueue(kindBlock, {
      'blocker_id': uid,
      'blocked_id': user.id,
    }, id: 'block:$uid:${user.id}');
    final s = await cached();
    if (s.isBlocked(user.id)) return;
    await _store(
      s.copyWith(
        blocked: [
          BlockedUser(
            id: user.id,
            handle: user.handle,
            displayName: user.displayName,
            avatarPath: user.avatarPath,
            blockedAt: DateTime.fromMillisecondsSinceEpoch(now(), isUtc: true),
          ),
          ...s.blocked,
        ],
      ),
    );
  }

  Future<void> unblock(String userId) async {
    final uid = me();
    if (uid == null) return;
    await outbox.enqueue(kindUnblock, {
      'blocker_id': uid,
      'blocked_id': userId,
    }, id: 'unblock:$uid:$userId');
    final s = await cached();
    await _store(
      s.copyWith(
        blocked: [
          for (final b in s.blocked)
            if (b.id != userId) b,
        ],
      ),
    );
  }

  /// Reports a post. Hidden for the reporter at once.
  Future<void> reportPost({
    required String postId,
    required String authorId,
    required ReportReason reason,
    String? details,
    Map<String, dynamic> snapshot = const {},
  }) async {
    final uid = me();
    if (uid == null) return;
    await outbox.enqueue(
      kindReport,
      _reportPayload(
        uid,
        reportedUserId: authorId,
        postId: postId,
        reason: reason,
        details: details,
        snapshot: snapshot,
      ),
    );
    final s = await cached();
    await _store(s.copyWith(hiddenPostIds: {...s.hiddenPostIds, postId}));
  }

  /// Reports a comment. Hidden for the reporter at once.
  Future<void> reportComment({
    required String commentId,
    required String postId,
    required String authorId,
    required ReportReason reason,
    String? details,
    Map<String, dynamic> snapshot = const {},
  }) async {
    final uid = me();
    if (uid == null) return;
    await outbox.enqueue(
      kindReport,
      _reportPayload(
        uid,
        reportedUserId: authorId,
        postId: postId,
        commentId: commentId,
        reason: reason,
        details: details,
        snapshot: snapshot,
      ),
    );
    final s = await cached();
    await _store(
      s.copyWith(hiddenCommentIds: {...s.hiddenCommentIds, commentId}),
    );
  }

  Map<String, dynamic> _reportPayload(
    String uid, {
    required String reportedUserId,
    String? postId,
    String? commentId,
    required ReportReason reason,
    String? details,
    required Map<String, dynamic> snapshot,
  }) {
    final text = details?.trim();
    return {
      'id': _uuid.v4(),
      'reporter_id': uid,
      'reported_user_id': reportedUserId,
      'post_id': postId,
      'comment_id': commentId,
      'reason': reason.wire,
      'details': text == null || text.isEmpty
          ? null
          : (text.length > 500 ? text.substring(0, 500) : text),
      'snapshot': snapshot,
    };
  }

  // ----------------------------------------------------- outbox handlers --

  Future<void> handleBlock(Map<String, dynamic> p) async {
    final client = _online();
    if (p['blocker_id'] != me()) throw const OutboxSkip('another account');
    await client
        .from('user_blocks')
        .upsert(
          {'blocker_id': p['blocker_id'], 'blocked_id': p['blocked_id']},
          onConflict: 'blocker_id,blocked_id',
          ignoreDuplicates: true,
        );
  }

  Future<void> handleUnblock(Map<String, dynamic> p) async {
    final client = _online();
    if (p['blocker_id'] != me()) throw const OutboxSkip('another account');
    await client
        .from('user_blocks')
        .delete()
        .eq('blocker_id', p['blocker_id'] as String)
        .eq('blocked_id', p['blocked_id'] as String);
  }

  Future<void> handleReport(Map<String, dynamic> p) async {
    final client = _online();
    if (p['reporter_id'] != me()) throw const OutboxSkip('another account');
    await client
        .from('content_reports')
        .upsert(
          {
            'id': p['id'],
            'reporter_id': p['reporter_id'],
            'reported_user_id': p['reported_user_id'],
            'post_id': p['post_id'],
            'comment_id': p['comment_id'],
            'reason': p['reason'],
            'details': p['details'],
            'snapshot': p['snapshot'] ?? const {},
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        );
  }

  void registerHandlers(OutboxWorker worker) {
    worker.register(kindBlock, handleBlock);
    worker.register(kindUnblock, handleUnblock);
    worker.register(kindReport, handleReport);
  }
}

final moderationRepoProvider = Provider<ModerationRepo>(
  (ref) => ModerationRepo(
    clientOf: () => ref.read(supabaseProvider),
    db: ref.watch(databaseProvider),
    outbox: ref.watch(outboxWorkerProvider),
    me: () => ref.read(currentUserIdProvider),
  ),
);

/// Blocked people and hidden posts, live from the cache. Refreshed from the
/// server once per sign-in.
final moderationStateProvider = StreamProvider<ModerationState>((ref) {
  final repo = ref.watch(moderationRepoProvider);
  final me = ref.watch(currentUserIdProvider);
  if (me != null) {
    Future.microtask(() async {
      try {
        await repo.refresh();
      } catch (_) {
        // Offline: the cache stands.
      }
    });
  }
  return repo.watchCached();
});
