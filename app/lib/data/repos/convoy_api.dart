import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'convoy_models.dart';

/// Everything the convoy repo asks the cloud for. Faked in tests.
abstract class ConvoysApi {
  Future<List<Convoy>> myConvoys(String userId);
  Future<Convoy?> convoy(String id);
  Future<List<ConvoyMember>> members(String convoyId);
  Future<List<ConvoyStop>> stops(String convoyId);
  Future<List<ConvoyExpense>> expenses(String convoyId);
  Future<List<ConvoyPhoto>> photos(String convoyId);

  /// Returns the convoy id. Throws [ConvoyJoinException].
  Future<String> joinByCode(String code);

  Future<void> createConvoy({
    required String id,
    required String name,
    required String userId,
    Destination? destination,
  });
  Future<void> updateConvoy(String id, Map<String, Object?> fields);
  Future<void> setStatus(String id, ConvoyStatus status, DateTime at);
  Future<void> leave({required String convoyId, required String userId});

  Future<void> proposeStop(Map<String, Object?> row);
  Future<void> vote({
    required String stopId,
    required String userId,
    required int vote,
  });
  Future<void> removeVote({required String stopId, required String userId});
  Future<void> setStopStatus(String stopId, StopStatus status);

  Future<void> addExpense(Map<String, Object?> row);
  Future<void> deleteExpense(String id);

  Future<void> uploadPhoto(String path, Uint8List jpeg);
  Future<void> addPhoto(Map<String, Object?> row);
  Future<void> deletePhoto(String id, String storagePath);
  Future<String> signedPhotoUrl(String storagePath, {int seconds = 3600});

  Future<List<ConvoyTripSummary>> tripSummariesBetween(
    List<String> userIds,
    DateTime from,
    DateTime to,
  );
}

class SupabaseConvoysApi implements ConvoysApi {
  SupabaseConvoysApi(this.client);
  final SupabaseClient client;

  static const bucket = 'convoy-photos';
  static const _convoyColumns =
      'id, name, created_by, status, destination, invite_code, max_cars, '
      'created_at, started_at, ended_at';
  static const _memberColumns =
      'user_id, role, car_label, joined_at, left_at, '
      'profiles(handle, display_name, avatar_path)';

  @override
  Future<List<Convoy>> myConvoys(String userId) async {
    final rows = await client
        .from('convoy_members')
        .select('convoy_id, left_at, convoys($_convoyColumns)')
        .eq('user_id', userId)
        .isFilter('left_at', null);
    final memberships = [
      for (final r in rows)
        if (r['convoys'] != null) r,
    ];
    if (memberships.isEmpty) return const [];
    final ids = [for (final r in memberships) r['convoy_id'] as String];
    final counts = <String, int>{};
    final memberRows = await client
        .from('convoy_members')
        .select('convoy_id')
        .inFilter('convoy_id', ids)
        .isFilter('left_at', null);
    for (final r in memberRows) {
      final id = r['convoy_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final convoys = [
      for (final r in memberships)
        Convoy.fromMembershipRow(
          r,
          memberCount: counts[r['convoy_id'] as String] ?? 1,
        ),
    ];
    convoys.sort((a, b) {
      // Active first, then planning, then ended; newest first within.
      final sa = a.status == ConvoyStatus.ended ? 2 : (a.isActive ? 0 : 1);
      final sb = b.status == ConvoyStatus.ended ? 2 : (b.isActive ? 0 : 1);
      if (sa != sb) return sa.compareTo(sb);
      return b.createdAt.compareTo(a.createdAt);
    });
    return convoys;
  }

  @override
  Future<Convoy?> convoy(String id) async {
    final row = await client
        .from('convoys')
        .select(_convoyColumns)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Convoy.fromJson(row);
  }

  @override
  Future<List<ConvoyMember>> members(String convoyId) async {
    final rows = await client
        .from('convoy_members')
        .select(_memberColumns)
        .eq('convoy_id', convoyId)
        .order('joined_at', ascending: true);
    return [for (final r in rows) ConvoyMember.fromRow(r)];
  }

  @override
  Future<List<ConvoyStop>> stops(String convoyId) async {
    final rows = await client
        .from('convoy_stops')
        .select('*, convoy_stop_votes(user_id, vote)')
        .eq('convoy_id', convoyId)
        .order('created_at', ascending: true);
    return [for (final r in rows) ConvoyStop.fromRow(r)];
  }

  @override
  Future<List<ConvoyExpense>> expenses(String convoyId) async {
    final rows = await client
        .from('convoy_expenses')
        .select()
        .eq('convoy_id', convoyId)
        .order('created_at', ascending: true);
    return [for (final r in rows) ConvoyExpense.fromRow(r)];
  }

  @override
  Future<List<ConvoyPhoto>> photos(String convoyId) async {
    final rows = await client
        .from('convoy_photos')
        .select()
        .eq('convoy_id', convoyId)
        .order('taken_at', ascending: true);
    return [for (final r in rows) ConvoyPhoto.fromRow(r)];
  }

  @override
  Future<String> joinByCode(String code) async {
    try {
      final id = await client.rpc(
        'join_convoy',
        params: {'code': code.trim().toLowerCase()},
      );
      return id as String;
    } catch (e) {
      throw ConvoyJoinException(mapConvoyJoinError(e), e.toString());
    }
  }

  @override
  Future<void> createConvoy({
    required String id,
    required String name,
    required String userId,
    Destination? destination,
  }) async {
    await client
        .from('convoys')
        .upsert(
          {
            'id': id,
            'name': name,
            'created_by': userId,
            'destination': destination?.toJson(),
          },
          onConflict: 'id',
          ignoreDuplicates: true,
        );
    await client
        .from('convoy_members')
        .upsert(
          {'convoy_id': id, 'user_id': userId, 'role': 'leader'},
          onConflict: 'convoy_id,user_id',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> updateConvoy(String id, Map<String, Object?> fields) =>
      client.from('convoys').update(fields).eq('id', id);

  @override
  Future<void> setStatus(String id, ConvoyStatus status, DateTime at) {
    final fields = <String, Object?>{'status': status.wire};
    if (status == ConvoyStatus.active) {
      fields['started_at'] = at.toUtc().toIso8601String();
    }
    if (status == ConvoyStatus.ended) {
      fields['ended_at'] = at.toUtc().toIso8601String();
    }
    return client.from('convoys').update(fields).eq('id', id);
  }

  @override
  Future<void> leave({required String convoyId, required String userId}) =>
      client
          .from('convoy_members')
          .update({'left_at': DateTime.now().toUtc().toIso8601String()})
          .eq('convoy_id', convoyId)
          .eq('user_id', userId);

  @override
  Future<void> proposeStop(Map<String, Object?> row) => client
      .from('convoy_stops')
      .upsert(row, onConflict: 'id', ignoreDuplicates: true);

  @override
  Future<void> vote({
    required String stopId,
    required String userId,
    required int vote,
  }) => client.from('convoy_stop_votes').upsert({
    'stop_id': stopId,
    'user_id': userId,
    'vote': vote,
  }, onConflict: 'stop_id,user_id');

  @override
  Future<void> removeVote({required String stopId, required String userId}) =>
      client
          .from('convoy_stop_votes')
          .delete()
          .eq('stop_id', stopId)
          .eq('user_id', userId);

  @override
  Future<void> setStopStatus(String stopId, StopStatus status) => client
      .from('convoy_stops')
      .update({'status': status.wire})
      .eq('id', stopId);

  @override
  Future<void> addExpense(Map<String, Object?> row) => client
      .from('convoy_expenses')
      .upsert(row, onConflict: 'id', ignoreDuplicates: true);

  @override
  Future<void> deleteExpense(String id) =>
      client.from('convoy_expenses').delete().eq('id', id);

  @override
  Future<void> uploadPhoto(String path, Uint8List jpeg) => client.storage
      .from(bucket)
      .uploadBinary(
        path,
        jpeg,
        fileOptions: const FileOptions(
          upsert: true,
          contentType: 'image/jpeg',
          cacheControl: '3600',
        ),
      );

  @override
  Future<void> addPhoto(Map<String, Object?> row) => client
      .from('convoy_photos')
      .upsert(row, onConflict: 'id', ignoreDuplicates: true);

  @override
  Future<void> deletePhoto(String id, String storagePath) async {
    await client.from('convoy_photos').delete().eq('id', id);
    try {
      await client.storage.from(bucket).remove([storagePath]);
    } catch (_) {
      // The row is gone; an orphaned object ages out with the 30-day prune.
    }
  }

  @override
  Future<String> signedPhotoUrl(String storagePath, {int seconds = 3600}) =>
      client.storage.from(bucket).createSignedUrl(storagePath, seconds);

  @override
  Future<List<ConvoyTripSummary>> tripSummariesBetween(
    List<String> userIds,
    DateTime from,
    DateTime to,
  ) async {
    if (userIds.isEmpty) return const [];
    final rows = await client
        .from('trip_summaries')
        .select(
          'user_id, started_at, ended_at, distance_m, score, scored, '
          'is_passenger, trip_events(kind, duration_s)',
        )
        .inFilter('user_id', userIds)
        .gte('started_at', from.toUtc().toIso8601String())
        .lte('started_at', to.toUtc().toIso8601String());
    return [for (final r in rows) ConvoyTripSummary.fromRow(r)];
  }
}
