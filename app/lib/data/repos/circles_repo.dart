import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../sync/outbox.dart';
import 'friends_repo.dart' show initialsOf;

/// A Life360-style group (docs/01 §4.5). Membership is what makes positions
/// and posts visible; the only per-member control is [myHiding].
class Circle {
  const Circle({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.inviteCode,
    required this.createdAt,
    this.memberCount = 0,
    this.myHiding = false,
  });

  /// From a `circle_members` row with the `circles` row embedded.
  factory Circle.fromMembershipRow(
    Map<String, dynamic> r, {
    int memberCount = 0,
  }) {
    final c = (r['circles'] as Map).cast<String, dynamic>();
    return Circle(
      id: c['id'] as String,
      name: c['name'] as String? ?? '',
      createdBy: c['created_by'] as String? ?? '',
      inviteCode: c['invite_code'] as String? ?? '',
      createdAt:
          DateTime.tryParse(c['created_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      memberCount: memberCount,
      myHiding: r['hiding'] as bool? ?? false,
    );
  }

  factory Circle.fromJson(Map<String, dynamic> j) => Circle(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    createdBy: j['created_by'] as String? ?? '',
    inviteCode: j['invite_code'] as String? ?? '',
    createdAt:
        DateTime.tryParse(j['created_at'] as String? ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    memberCount: (j['member_count'] as num?)?.toInt() ?? 0,
    myHiding: j['my_hiding'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String createdBy;

  /// Empty until the first fetch after creation (the server generates it).
  final String inviteCode;
  final DateTime createdAt;
  final int memberCount;
  final bool myHiding;

  /// `drivalry://join/circle/<code>`: the link behind the QR code.
  String get inviteLink => CirclesRepo.inviteLink(inviteCode);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'created_by': createdBy,
    'invite_code': inviteCode,
    'created_at': createdAt.toIso8601String(),
    'member_count': memberCount,
    'my_hiding': myHiding,
  };

  Circle copyWith({
    String? name,
    String? inviteCode,
    int? memberCount,
    bool? myHiding,
  }) => Circle(
    id: id,
    name: name ?? this.name,
    createdBy: createdBy,
    inviteCode: inviteCode ?? this.inviteCode,
    createdAt: createdAt,
    memberCount: memberCount ?? this.memberCount,
    myHiding: myHiding ?? this.myHiding,
  );
}

/// One member of a circle with the public bits of their profile.
class CircleMember {
  const CircleMember({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.hiding,
    required this.joinedAt,
    this.avatarPath,
  });

  /// From a `circle_members` row with `profiles` embedded.
  factory CircleMember.fromRow(Map<String, dynamic> r) {
    final p = (r['profiles'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CircleMember(
      userId: r['user_id'] as String,
      handle: p['handle'] as String? ?? r['handle'] as String? ?? '',
      displayName:
          p['display_name'] as String? ?? r['display_name'] as String? ?? '',
      avatarPath: p['avatar_path'] as String? ?? r['avatar_path'] as String?,
      hiding: r['hiding'] as bool? ?? false,
      joinedAt:
          DateTime.tryParse(r['joined_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String userId;
  final String handle;
  final String displayName;
  final String? avatarPath;

  /// Visible to the whole circle: "hiding" means no position, no posts here.
  final bool hiding;
  final DateTime joinedAt;

  String get name => displayName.trim().isNotEmpty ? displayName : '@$handle';
  String get initials => initialsOf(name);

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'handle': handle,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'hiding': hiding,
    'joined_at': joinedAt.toIso8601String(),
  };

  CircleMember copyWith({bool? hiding}) => CircleMember(
    userId: userId,
    handle: handle,
    displayName: displayName,
    avatarPath: avatarPath,
    hiding: hiding ?? this.hiding,
    joinedAt: joinedAt,
  );
}

enum CircleJoinError { invalidCode, notSignedIn, unavailable }

class CircleJoinException implements Exception {
  const CircleJoinException(this.error, [this.detail]);
  final CircleJoinError error;
  final String? detail;

  String get message => switch (error) {
    CircleJoinError.invalidCode => 'That invite code is not valid.',
    CircleJoinError.notSignedIn => 'Sign in first.',
    CircleJoinError.unavailable => 'Could not reach Drivalry. Try again.',
  };

  @override
  String toString() => 'CircleJoinException($error, $detail)';
}

/// Maps the error `join_circle` raises (`0001_init.sql`: P0001 invalid code).
CircleJoinError mapCircleJoinError(Object e) {
  if (e is PostgrestException) {
    if (e.code == 'P0001') return CircleJoinError.invalidCode;
    if (e.message.toLowerCase().contains('invalid invite code')) {
      return CircleJoinError.invalidCode;
    }
  }
  return CircleJoinError.unavailable;
}

/// Everything the repo asks the cloud for. Faked in tests.
abstract class CirclesApi {
  Future<List<Circle>> myCircles(String userId);
  Future<List<CircleMember>> members(String circleId);

  /// Returns the circle id. Throws [CircleJoinException].
  Future<String> joinByCode(String code);
  Future<void> createCircle({
    required String id,
    required String name,
    required String userId,
  });
  Future<void> setHiding({
    required String circleId,
    required String userId,
    required bool hiding,
  });
  Future<void> leave({required String circleId, required String userId});
  Future<void> postCheckin({
    required String id,
    required String userId,
    required String label,
    required DateTime createdAt,
  });
}

class SupabaseCirclesApi implements CirclesApi {
  SupabaseCirclesApi(this.client);
  final SupabaseClient client;

  static const _circleColumns = 'id, name, created_by, invite_code, created_at';
  static const _memberColumns =
      'user_id, hiding, joined_at, profiles(handle, display_name, avatar_path)';

  @override
  Future<List<Circle>> myCircles(String userId) async {
    final rows = await client
        .from('circle_members')
        .select('circle_id, hiding, joined_at, circles($_circleColumns)')
        .eq('user_id', userId);
    final memberships = [
      for (final r in rows)
        if (r['circles'] != null) r,
    ];
    if (memberships.isEmpty) return const [];
    final ids = [for (final r in memberships) r['circle_id'] as String];
    final counts = <String, int>{};
    final memberRows = await client
        .from('circle_members')
        .select('circle_id')
        .inFilter('circle_id', ids);
    for (final r in memberRows) {
      final id = r['circle_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final circles = [
      for (final r in memberships)
        Circle.fromMembershipRow(
          r,
          memberCount: counts[r['circle_id'] as String] ?? 1,
        ),
    ];
    circles.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return circles;
  }

  @override
  Future<List<CircleMember>> members(String circleId) async {
    final rows = await client
        .from('circle_members')
        .select(_memberColumns)
        .eq('circle_id', circleId)
        .order('joined_at', ascending: true);
    return [for (final r in rows) CircleMember.fromRow(r)];
  }

  @override
  Future<String> joinByCode(String code) async {
    try {
      final id = await client.rpc(
        'join_circle',
        params: {'code': code.trim().toLowerCase()},
      );
      return id as String;
    } catch (e) {
      throw CircleJoinException(mapCircleJoinError(e), e.toString());
    }
  }

  @override
  Future<void> createCircle({
    required String id,
    required String name,
    required String userId,
  }) async {
    await client
        .from('circles')
        .upsert(
          {'id': id, 'name': name, 'created_by': userId},
          onConflict: 'id',
          ignoreDuplicates: true,
        );
    await client
        .from('circle_members')
        .upsert(
          {'circle_id': id, 'user_id': userId},
          onConflict: 'circle_id,user_id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> setHiding({
    required String circleId,
    required String userId,
    required bool hiding,
  }) => client
      .from('circle_members')
      .update({'hiding': hiding})
      .eq('circle_id', circleId)
      .eq('user_id', userId);

  @override
  Future<void> leave({required String circleId, required String userId}) =>
      client
          .from('circle_members')
          .delete()
          .eq('circle_id', circleId)
          .eq('user_id', userId);

  @override
  Future<void> postCheckin({
    required String id,
    required String userId,
    required String label,
    required DateTime createdAt,
  }) => client
      .from('feed_posts')
      .upsert(
        {
          'id': id,
          'author_id': userId,
          'kind': 'checkin',
          'body': {'label': label},
          'created_at': createdAt.toUtc().toIso8601String(),
        },
        onConflict: 'id',
        ignoreDuplicates: true,
      );
}

/// Circles: membership, per-circle hiding, invites and check-ins
/// (docs/01 §4.5). Reads are cached in `RemoteCache`; writes go through the
/// outbox with an optimistic cache update, except joining by code, which
/// needs the server's answer right away.
class CirclesRepo {
  CirclesRepo({
    required this.apiOf,
    required this.db,
    required this.outbox,
    required this.me,
    this.now = _nowMs,
  });

  static int _nowMs() => DateTime.now().millisecondsSinceEpoch;
  static const _uuid = Uuid();

  /// The cloud, or null when offline-only or signed out.
  final CirclesApi? Function() apiOf;
  final AppDatabase db;
  final OutboxWorker outbox;

  /// The signed-in user's id, or null.
  final String? Function() me;
  final int Function() now;

  static const cacheKey = 'circles:mine';
  static String membersKey(String circleId) => 'circle:$circleId:members';

  /// Local mirror of my hiding flag per circle, so presence code can honour
  /// it without a network read.
  static String hidingSettingKey(String circleId) => 'hiding:circle:$circleId';

  // Outbox kinds and payloads (idempotent server side).
  static const kindCreate = 'circle_create'; // {id, name, user_id}
  static const kindHiding = 'circle_hiding'; // {circle_id, user_id, hiding}
  static const kindLeave = 'circle_leave'; // {circle_id, user_id}
  static const kindCheckin = 'checkin'; // {id, user_id, label, created_at}

  static String inviteLink(String code) => 'drivalry://join/circle/$code';

  CirclesApi _online() {
    final api = apiOf();
    if (api == null) throw const OutboxRetryLater('not signed in');
    return api;
  }

  // ---------------------------------------------------------------- reads --

  Future<List<Circle>?> cached() async =>
      _decodeCircles(await db.cacheGet(cacheKey));

  Stream<List<Circle>?> watchCached() =>
      db.watchCache(cacheKey).map(_decodeCircles);

  List<Circle>? _decodeCircles(String? json) {
    if (json == null) return null;
    try {
      return [
        for (final c in jsonDecode(json) as List)
          Circle.fromJson((c as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<List<Circle>> fetch() async {
    final api = apiOf();
    final uid = me();
    if (api == null || uid == null) return const [];
    final circles = await api.myCircles(uid);
    await _store(circles);
    for (final c in circles) {
      await db.setSetting(hidingSettingKey(c.id), c.myHiding.toString());
    }
    return circles;
  }

  Future<void> _store(List<Circle> circles) => db.cachePut(
    cacheKey,
    jsonEncode([for (final c in circles) c.toJson()]),
    now(),
  );

  Future<List<CircleMember>?> cachedMembers(String circleId) async {
    final json = await db.cacheGet(membersKey(circleId));
    if (json == null) return null;
    try {
      return [
        for (final m in jsonDecode(json) as List)
          CircleMember.fromRow((m as Map).cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<List<CircleMember>> fetchMembers(String circleId) async {
    final api = apiOf();
    if (api == null) return await cachedMembers(circleId) ?? const [];
    final members = await api.members(circleId);
    await db.cachePut(
      membersKey(circleId),
      jsonEncode([for (final m in members) m.toJson()]),
      now(),
    );
    return members;
  }

  /// Cache first, network when the cache is empty.
  Future<List<CircleMember>> members(String circleId) async =>
      await cachedMembers(circleId) ?? await fetchMembers(circleId);

  // --------------------------------------------------------------- writes --

  /// Creates a circle locally and queues the cloud write. The invite code
  /// appears after the next [fetch]. Returns the new id.
  Future<String> create(String name) async {
    final uid = me();
    final trimmed = name.trim();
    if (uid == null || trimmed.isEmpty) {
      throw ArgumentError('sign in and give the circle a name');
    }
    final id = _uuid.v4();
    await outbox.enqueue(kindCreate, {
      'id': id,
      'name': trimmed,
      'user_id': uid,
    }, id: 'circle_create:$id');
    final current = await cached() ?? const <Circle>[];
    await _store([
      ...current,
      Circle(
        id: id,
        name: trimmed,
        createdBy: uid,
        inviteCode: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(now(), isUtc: true),
        memberCount: 1,
      ),
    ]);
    return id;
  }

  /// Joins through the `join_circle` RPC and refreshes the list. Throws
  /// [CircleJoinException].
  Future<String> join(String code) async {
    final api = apiOf();
    if (api == null || me() == null) {
      throw const CircleJoinException(CircleJoinError.notSignedIn);
    }
    final id = await api.joinByCode(code);
    try {
      await fetch();
    } catch (_) {
      // The join succeeded; the list refreshes on the next screen open.
    }
    return id;
  }

  Future<void> setHiding(String circleId, bool hiding) async {
    final uid = me();
    if (uid == null) return;
    await db.setSetting(hidingSettingKey(circleId), hiding.toString());
    final current = await cached();
    if (current != null) {
      await _store([
        for (final c in current)
          if (c.id == circleId) c.copyWith(myHiding: hiding) else c,
      ]);
    }
    final members = await cachedMembers(circleId);
    if (members != null) {
      await db.cachePut(
        membersKey(circleId),
        jsonEncode([
          for (final m in members)
            if (m.userId == uid)
              m.copyWith(hiding: hiding).toJson()
            else
              m.toJson(),
        ]),
        now(),
      );
    }
    await outbox.enqueue(kindHiding, {
      'circle_id': circleId,
      'user_id': uid,
      'hiding': hiding,
    }, id: 'circle_hiding:$circleId:$uid');
  }

  Future<void> leave(String circleId) async {
    final uid = me();
    if (uid == null) return;
    final current = await cached();
    if (current != null) {
      await _store([
        for (final c in current)
          if (c.id != circleId) c,
      ]);
    }
    await db.cacheDeletePrefix(membersKey(circleId));
    await outbox.enqueue(kindLeave, {
      'circle_id': circleId,
      'user_id': uid,
    }, id: 'circle_leave:$circleId:$uid');
  }

  /// "I got home": a feed post carrying only the place label.
  Future<String?> checkIn(String label) async {
    final uid = me();
    final trimmed = label.trim();
    if (uid == null || trimmed.isEmpty) return null;
    final id = _uuid.v4();
    await outbox.enqueue(kindCheckin, {
      'id': id,
      'user_id': uid,
      'label': trimmed,
      'created_at': DateTime.fromMillisecondsSinceEpoch(
        now(),
        isUtc: true,
      ).toIso8601String(),
    }, id: 'checkin:$id');
    return id;
  }

  // ----------------------------------------------------- outbox handlers --

  Future<void> handleCreate(Map<String, dynamic> p) async {
    final api = _online();
    if (p['user_id'] != me()) throw const OutboxSkip('another account');
    await api.createCircle(
      id: p['id'] as String,
      name: p['name'] as String,
      userId: p['user_id'] as String,
    );
  }

  Future<void> handleHiding(Map<String, dynamic> p) async {
    final api = _online();
    if (p['user_id'] != me()) throw const OutboxSkip('another account');
    await api.setHiding(
      circleId: p['circle_id'] as String,
      userId: p['user_id'] as String,
      hiding: p['hiding'] == true,
    );
  }

  Future<void> handleLeave(Map<String, dynamic> p) async {
    final api = _online();
    if (p['user_id'] != me()) throw const OutboxSkip('another account');
    await api.leave(
      circleId: p['circle_id'] as String,
      userId: p['user_id'] as String,
    );
  }

  Future<void> handleCheckin(Map<String, dynamic> p) async {
    final api = _online();
    if (p['user_id'] != me()) throw const OutboxSkip('another account');
    await api.postCheckin(
      id: p['id'] as String,
      userId: p['user_id'] as String,
      label: p['label'] as String,
      createdAt:
          DateTime.tryParse(p['created_at'] as String? ?? '') ??
          DateTime.now().toUtc(),
    );
  }

  void registerHandlers(OutboxWorker worker) {
    worker.register(kindCreate, handleCreate);
    worker.register(kindHiding, handleHiding);
    worker.register(kindLeave, handleLeave);
    worker.register(kindCheckin, handleCheckin);
  }
}
