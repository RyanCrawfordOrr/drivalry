import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database.dart';
import '../sync/outbox.dart';

/// Another user as the friends screens show them.
class FriendProfile {
  const FriendProfile({
    required this.id,
    required this.handle,
    required this.displayName,
    this.avatarPath,
    this.driverRating,
  });

  factory FriendProfile.fromJson(Map<String, dynamic> j) => FriendProfile(
    id: j['id'] as String,
    handle: j['handle'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    avatarPath: j['avatar_path'] as String?,
    driverRating: (j['driver_rating'] as num?)?.toDouble(),
  );

  final String id;
  final String handle;
  final String displayName;
  final String? avatarPath;
  final double? driverRating;

  String get name => displayName.trim().isNotEmpty ? displayName : '@$handle';

  /// Up to two letters for an avatar placeholder.
  String get initials => initialsOf(name);

  Map<String, dynamic> toJson() => {
    'id': id,
    'handle': handle,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'driver_rating': driverRating,
  };
}

/// First letters of the first two words, upper-cased; `?` for nothing.
String initialsOf(String name) {
  final words = name
      .replaceAll('@', '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  final letters = words.take(2).map((w) => w[0].toUpperCase()).join();
  return letters;
}

enum FriendRequestDirection { incoming, outgoing }

/// A pending `friendships` row seen from the signed-in user's side.
class FriendRequest {
  const FriendRequest({
    required this.requesterId,
    required this.addresseeId,
    required this.other,
    required this.direction,
    required this.createdAt,
  });

  final String requesterId;
  final String addresseeId;
  final FriendProfile other;
  final FriendRequestDirection direction;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'requester_id': requesterId,
    'addressee_id': addresseeId,
    'other': other.toJson(),
    'direction': direction.name,
    'created_at': createdAt.toIso8601String(),
  };

  factory FriendRequest.fromJson(Map<String, dynamic> j) => FriendRequest(
    requesterId: j['requester_id'] as String,
    addresseeId: j['addressee_id'] as String,
    other: FriendProfile.fromJson((j['other'] as Map).cast<String, dynamic>()),
    direction: FriendRequestDirection.values.byName(j['direction'] as String),
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Friends plus both directions of pending requests, as one cacheable value.
class FriendsSnapshot {
  const FriendsSnapshot({
    this.friends = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.fetchedAt,
  });

  final List<FriendProfile> friends;
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;
  final DateTime? fetchedAt;

  bool isFriend(String userId) => friends.any((f) => f.id == userId);
  bool hasOutgoingTo(String userId) =>
      outgoing.any((r) => r.addresseeId == userId);
  bool hasIncomingFrom(String userId) =>
      incoming.any((r) => r.requesterId == userId);

  /// Whether the last fetch is older than [maxAge] at [now]. A snapshot that
  /// never came from the network (no [fetchedAt]) is always stale.
  bool isStale(DateTime now, Duration maxAge) {
    final at = fetchedAt;
    return at == null || now.difference(at) > maxAge;
  }

  /// Builds the snapshot from `friendships` rows embedded with both profiles
  /// (see [FriendsRepo.requestSelect]) as the signed-in user [me].
  static FriendsSnapshot fromRows(
    List<Map<String, dynamic>> rows,
    String me, {
    DateTime? fetchedAt,
  }) {
    final friends = <FriendProfile>[];
    final incoming = <FriendRequest>[];
    final outgoing = <FriendRequest>[];
    for (final r in rows) {
      final requesterId = r['requester_id'] as String;
      final addresseeId = r['addressee_id'] as String;
      final status = r['status'] as String? ?? 'pending';
      final requester = (r['requester'] as Map?)?.cast<String, dynamic>();
      final addressee = (r['addressee'] as Map?)?.cast<String, dynamic>();
      final otherJson = requesterId == me ? addressee : requester;
      if (otherJson == null) continue;
      final other = FriendProfile.fromJson(otherJson);
      final createdAt =
          DateTime.tryParse(r['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      switch (status) {
        case 'accepted':
          friends.add(other);
        case 'pending':
          final direction = requesterId == me
              ? FriendRequestDirection.outgoing
              : FriendRequestDirection.incoming;
          (direction == FriendRequestDirection.incoming ? incoming : outgoing)
              .add(
                FriendRequest(
                  requesterId: requesterId,
                  addresseeId: addresseeId,
                  other: other,
                  direction: direction,
                  createdAt: createdAt,
                ),
              );
        default:
          // blocked: shown nowhere
          break;
      }
    }
    friends.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    incoming.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    outgoing.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return FriendsSnapshot(
      friends: friends,
      incoming: incoming,
      outgoing: outgoing,
      fetchedAt: fetchedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'friends': [for (final f in friends) f.toJson()],
    'incoming': [for (final r in incoming) r.toJson()],
    'outgoing': [for (final r in outgoing) r.toJson()],
    'fetched_at': fetchedAt?.toIso8601String(),
  };

  factory FriendsSnapshot.fromJson(Map<String, dynamic> j) => FriendsSnapshot(
    friends: [
      for (final f in (j['friends'] as List?) ?? const [])
        FriendProfile.fromJson((f as Map).cast<String, dynamic>()),
    ],
    incoming: [
      for (final r in (j['incoming'] as List?) ?? const [])
        FriendRequest.fromJson((r as Map).cast<String, dynamic>()),
    ],
    outgoing: [
      for (final r in (j['outgoing'] as List?) ?? const [])
        FriendRequest.fromJson((r as Map).cast<String, dynamic>()),
    ],
    fetchedAt: j['fetched_at'] == null
        ? null
        : DateTime.tryParse(j['fetched_at'] as String),
  );

  FriendsSnapshot copyWith({
    List<FriendProfile>? friends,
    List<FriendRequest>? incoming,
    List<FriendRequest>? outgoing,
  }) => FriendsSnapshot(
    friends: friends ?? this.friends,
    incoming: incoming ?? this.incoming,
    outgoing: outgoing ?? this.outgoing,
    fetchedAt: fetchedAt,
  );
}

/// Friend requests, acceptance and the friends list (docs/01 §4.5, §4.9).
/// Reads hit Supabase and are cached in `RemoteCache`; writes go through the
/// outbox so they survive being offline, and the cache is updated
/// optimistically so the screen reacts at once.
class FriendsRepo {
  FriendsRepo({
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

  static const cacheKey = 'friends:snapshot';

  static const profileColumns =
      'id, handle, display_name, avatar_path, driver_rating';

  /// Both profiles embedded through the two foreign keys of `friendships`.
  static const requestSelect =
      'requester_id, addressee_id, status, created_at, '
      'requester:profiles!friendships_requester_id_fkey($profileColumns), '
      'addressee:profiles!friendships_addressee_id_fkey($profileColumns)';

  // Outbox kinds and their payloads (all idempotent server side).
  static const kindRequest = 'friend_request'; // {requester_id, addressee_id}
  static const kindRespond =
      'friend_respond'; // {requester_id, addressee_id, status}
  static const kindRemove = 'friend_remove'; // {a, b}

  SupabaseClient _online() {
    final c = clientOf();
    if (c == null || c.auth.currentSession == null) {
      throw const OutboxRetryLater('not signed in');
    }
    return c;
  }

  /// `drivalry://friend/<id>`: the link behind the QR code (docs/01 §4.5).
  static String inviteLink(String userId) => 'drivalry://friend/$userId';

  // ---------------------------------------------------------------- reads --

  /// Exact handle match, case-insensitive (handles are stored lower-case).
  Future<FriendProfile?> findByHandle(String handle) async {
    final client = clientOf();
    if (client == null) return null;
    final h = handle.trim().replaceFirst('@', '').toLowerCase();
    if (h.isEmpty) return null;
    final row = await client
        .from('profiles')
        .select(profileColumns)
        .eq('handle', h)
        .maybeSingle();
    return row == null ? null : FriendProfile.fromJson(row);
  }

  Future<FriendProfile?> profile(String userId) async {
    final client = clientOf();
    if (client == null) return null;
    final row = await client
        .from('profiles')
        .select(profileColumns)
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : FriendProfile.fromJson(row);
  }

  Future<FriendsSnapshot?> cached() async {
    final json = await db.cacheGet(cacheKey);
    if (json == null) return null;
    try {
      return FriendsSnapshot.fromJson(
        (jsonDecode(json) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Stream<FriendsSnapshot?> watchCached() => db.watchCache(cacheKey).map((json) {
    if (json == null) return null;
    try {
      return FriendsSnapshot.fromJson(
        (jsonDecode(json) as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  });

  /// Pulls every friendship involving me (RLS scopes the query) and caches it.
  Future<FriendsSnapshot> fetch() async {
    final client = clientOf();
    final uid = me();
    if (client == null || uid == null) return const FriendsSnapshot();
    final rows = await client
        .from('friendships')
        .select(requestSelect)
        .inFilter('status', ['accepted', 'pending'])
        .order('created_at', ascending: false);
    final snapshot = FriendsSnapshot.fromRows(
      rows,
      uid,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(now()),
    );
    await _store(snapshot);
    return snapshot;
  }

  Future<void> _store(FriendsSnapshot s) =>
      db.cachePut(cacheKey, jsonEncode(s.toJson()), now());

  // --------------------------------------------------------------- writes --

  Future<void> sendRequest(FriendProfile to) async {
    final uid = me();
    if (uid == null || uid == to.id) return;
    await outbox.enqueue(kindRequest, {
      'requester_id': uid,
      'addressee_id': to.id,
    }, id: 'friend_request:$uid:${to.id}');
    final s = await cached() ?? const FriendsSnapshot();
    if (!s.isFriend(to.id) && !s.hasOutgoingTo(to.id)) {
      await _store(
        s.copyWith(
          outgoing: [
            FriendRequest(
              requesterId: uid,
              addresseeId: to.id,
              other: to,
              direction: FriendRequestDirection.outgoing,
              createdAt: DateTime.fromMillisecondsSinceEpoch(now()),
            ),
            ...s.outgoing,
          ],
        ),
      );
    }
  }

  Future<void> accept(FriendRequest request) async {
    final uid = me();
    if (uid == null) return;
    await outbox.enqueue(kindRespond, {
      'requester_id': request.requesterId,
      'addressee_id': uid,
      'status': 'accepted',
    });
    final s = await cached() ?? const FriendsSnapshot();
    await _store(
      s.copyWith(
        incoming: [
          for (final r in s.incoming)
            if (r.requesterId != request.requesterId) r,
        ],
        friends: s.isFriend(request.other.id)
            ? s.friends
            : [...s.friends, request.other],
      ),
    );
  }

  Future<void> block(FriendRequest request) async {
    final uid = me();
    if (uid == null) return;
    await outbox.enqueue(kindRespond, {
      'requester_id': request.requesterId,
      'addressee_id': uid,
      'status': 'blocked',
    });
    await _dropLocal(request.other.id);
  }

  /// Decline an incoming request, cancel an outgoing one, or unfriend.
  Future<void> remove(String otherId) async {
    final uid = me();
    if (uid == null) return;
    await outbox.enqueue(kindRemove, {'a': uid, 'b': otherId});
    await _dropLocal(otherId);
  }

  Future<void> _dropLocal(String otherId) async {
    final s = await cached();
    if (s == null) return;
    await _store(
      FriendsSnapshot(
        friends: [
          for (final f in s.friends)
            if (f.id != otherId) f,
        ],
        incoming: [
          for (final r in s.incoming)
            if (r.other.id != otherId) r,
        ],
        outgoing: [
          for (final r in s.outgoing)
            if (r.other.id != otherId) r,
        ],
        fetchedAt: s.fetchedAt,
      ),
    );
  }

  // ----------------------------------------------------- outbox handlers --

  Future<void> handleRequest(Map<String, dynamic> p) async {
    final client = _online();
    if (p['requester_id'] != me()) throw const OutboxSkip('another account');
    await client
        .from('friendships')
        .upsert(
          {
            'requester_id': p['requester_id'],
            'addressee_id': p['addressee_id'],
            'status': 'pending',
          },
          onConflict: 'requester_id,addressee_id',
          ignoreDuplicates: true,
        );
  }

  Future<void> handleRespond(Map<String, dynamic> p) async {
    final client = _online();
    if (p['addressee_id'] != me()) throw const OutboxSkip('another account');
    await client
        .from('friendships')
        .update({
          'status': p['status'],
          'responded_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('requester_id', p['requester_id'] as String)
        .eq('addressee_id', p['addressee_id'] as String);
  }

  Future<void> handleRemove(Map<String, dynamic> p) async {
    final client = _online();
    final a = p['a'] as String;
    final b = p['b'] as String;
    final uid = me();
    if (a != uid && b != uid) throw const OutboxSkip('another account');
    await client
        .from('friendships')
        .delete()
        .or(
          'and(requester_id.eq.$a,addressee_id.eq.$b),'
          'and(requester_id.eq.$b,addressee_id.eq.$a)',
        );
  }

  void registerHandlers(OutboxWorker worker) {
    worker.register(kindRequest, handleRequest);
    worker.register(kindRespond, handleRespond);
    worker.register(kindRemove, handleRemove);
  }
}
