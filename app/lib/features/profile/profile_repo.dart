import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/db/database.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../data/sync/outbox.dart';
import 'profile_model.dart';

/// Thrown for a user-fixable profile error (handle taken, too big an image).
class ProfileError implements Exception {
  const ProfileError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Profiles, read through `RemoteCache` so every screen renders offline and
/// written through the outbox where a retry is harmless (docs/03 §7).
class ProfileRepo {
  ProfileRepo(this._db, this._client, this._outbox, {int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final SupabaseClient? _client;
  final OutboxWorker _outbox;
  final int Function() _now;

  static const int avatarMaxBytes = 100 * 1024;
  static const String avatarBucket = 'avatars';

  /// Outbox kind for `profiles` updates: `{user_id, fields: {...}}`.
  static const String kindProfileUpdate = 'profile_update';

  static String cacheKey(String userId) => 'profile:$userId';

  /// Registers the outbox handler. Called once from the sync bootstrap.
  void registerHandlers() {
    _outbox.register(kindProfileUpdate, (p) async {
      final c = _client;
      final uid = c?.auth.currentUser?.id;
      if (c == null || uid == null) throw const OutboxRetryLater('signed out');
      // Written by a previous account: leave it queued for them.
      if (p['user_id'] != uid) throw const OutboxSkip('another account');
      final fields = (p['fields'] as Map).cast<String, Object?>();
      await c.from('profiles').update(fields).eq('id', uid);
    });
  }

  /// Cached profile, if any.
  Future<Profile?> cached(String userId) async {
    final json = await _db.cacheGet(cacheKey(userId));
    if (json == null) return null;
    return Profile.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Live view of the cache; triggers a refresh when first listened to.
  Stream<Profile?> watch(String userId) {
    unawaited(refresh(userId));
    return _db
        .watchCache(cacheKey(userId))
        .map(
          (json) => json == null
              ? null
              : Profile.fromJson(jsonDecode(json) as Map<String, dynamic>),
        );
  }

  /// Fetches from the cloud and updates the cache. Returns the cached value
  /// on any failure.
  Future<Profile?> refresh(String userId) async {
    final c = _client;
    if (c == null) return cached(userId);
    try {
      final row = await c
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return cached(userId);
      final p = Profile.fromJson(row);
      await _put(p);
      return p;
    } catch (e) {
      debugPrint('profile refresh failed: $e');
      return cached(userId);
    }
  }

  /// Exact, case-insensitive handle lookup for "add friend by handle".
  Future<Profile?> byHandle(String handle) async {
    final c = _client;
    if (c == null) return null;
    final row = await c
        .from('profiles')
        .select()
        .ilike('handle', handle.trim().toLowerCase())
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<void> _put(Profile p) =>
      _db.cachePut(cacheKey(p.id), jsonEncode(p.toJson()), _now());

  /// Changes the handle now (uniqueness needs an immediate answer).
  Future<void> updateHandle(String userId, String handle) async {
    final h = handle.trim().toLowerCase();
    final err = Profile.validateHandle(h);
    if (err != null) throw ProfileError(err);
    final c = _client;
    if (c == null) throw const ProfileError('Offline build.');
    try {
      await c.from('profiles').update({'handle': h}).eq('id', userId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') throw const ProfileError('That handle is taken.');
      throw ProfileError(e.message);
    }
    final p = await cached(userId);
    if (p != null) await _put(p.copyWith(handle: h));
  }

  Future<void> updateDisplayName(String userId, String name) async {
    final n = name.trim();
    final err = Profile.validateDisplayName(n);
    if (err != null) throw ProfileError(err);
    final p = await cached(userId);
    if (p != null) await _put(p.copyWith(displayName: n));
    await _outbox.enqueue(kindProfileUpdate, {
      'user_id': userId,
      'fields': {'display_name': n},
    }, id: 'profile_update:$userId:display_name');
  }

  /// The global hide switch (ADR-018): optimistic, through the outbox.
  Future<void> setLocationHidden(String userId, bool hidden) async {
    final p = await cached(userId);
    if (p != null) await _put(p.copyWith(locationHidden: hidden));
    // The presence publisher reads this mirror so it stops publishing at once,
    // before the cloud row is updated.
    await _db.setSetting('location_hidden', hidden ? 'true' : 'false');
    await _outbox.enqueue(kindProfileUpdate, {
      'user_id': userId,
      'fields': {'location_hidden': hidden},
    }, id: 'profile_update:$userId:location_hidden');
  }

  /// Uploads a JPEG (already downscaled by the picker) and points the profile
  /// at it. Rejects anything over [avatarMaxBytes].
  Future<void> uploadAvatar(String userId, Uint8List jpeg) async {
    if (jpeg.length > avatarMaxBytes) {
      throw ProfileError(
        'That image is ${(jpeg.length / 1024).round()} KB; the limit is 100 KB.',
      );
    }
    final c = _client;
    if (c == null) throw const ProfileError('Offline build.');
    final path = '$userId/avatar.jpg';
    await c.storage
        .from(avatarBucket)
        .uploadBinary(
          path,
          jpeg,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
            cacheControl: '60',
          ),
        );
    await c.from('profiles').update({'avatar_path': path}).eq('id', userId);
    final p = await cached(userId);
    if (p != null) await _put(p.copyWith(avatarPath: path));
  }

  /// Public URL for an avatar path, cache-busted by the profile's own state
  /// (the path never changes, the bytes do).
  String? avatarUrl(String? path, {int? version}) {
    final c = _client;
    if (c == null || path == null) return null;
    final url = c.storage.from(avatarBucket).getPublicUrl(path);
    return version == null ? url : '$url?v=$version';
  }
}

final profileRepoProvider = Provider<ProfileRepo>(
  (ref) => ProfileRepo(
    ref.watch(databaseProvider),
    ref.watch(supabaseProvider),
    ref.watch(outboxWorkerProvider),
  ),
);

/// A profile by id, live from the cache.
final profileProvider = StreamProvider.family<Profile?, String>(
  (ref, userId) => ref.watch(profileRepoProvider).watch(userId),
);

/// The signed-in user's profile, or null when signed out.
final myProfileProvider = StreamProvider<Profile?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream<Profile?>.value(null);
  return ref.watch(profileRepoProvider).watch(uid);
});
