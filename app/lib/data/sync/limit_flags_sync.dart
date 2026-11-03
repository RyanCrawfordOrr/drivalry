import 'dart:async';
import 'dart:convert';

import 'package:drivalry_packs/drivalry_packs.dart' show LimitOverride;
import 'package:drivalry_scoring/drivalry_scoring.dart'
    show SpeedUnits, mpsToKmh, mpsToMph;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/units.dart';
import '../badges/badges_sync.dart';
import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import 'outbox.dart';

/// Confidence the shared cache gives a two-flag override (docs/03 §4.4).
const double cloudOverrideConfidence = 0.85;

/// Cache key for the overrides of one pack region.
String overridesCacheKey(String region) => 'overrides:$region';

/// Reads the cached cloud overrides for [region]. Pure data access, usable
/// from the finalizer which has a database but no `ref`.
Future<Map<int, LimitOverride>> cachedOverrides(
  AppDatabase db,
  String region,
) async {
  final json = await db.cacheGet(overridesCacheKey(region));
  if (json == null) return const {};
  return decodeOverrides(json);
}

/// `{ "<wayId>": {"limit_mps": 15.6, "confidence": 0.85}, ... }`.
Map<int, LimitOverride> decodeOverrides(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final out = <int, LimitOverride>{};
  map.forEach((k, v) {
    final id = int.tryParse(k);
    if (id == null || v is! Map) return;
    out[id] = LimitOverride(
      wayId: id,
      limitMps: (v['limit_mps'] as num).toDouble(),
      confidence:
          (v['confidence'] as num?)?.toDouble() ?? cloudOverrideConfidence,
    );
  });
  return out;
}

/// Where overrides come from: rows of `speed_limit_overrides` with
/// `way_id, limit_mps, confidence, updated_at`, optionally only those updated
/// after [since] (ISO-8601 UTC).
abstract class OverridesSource {
  Future<List<Map<String, dynamic>>> fetch(String region, {String? since});
}

class SupabaseOverridesSource implements OverridesSource {
  SupabaseOverridesSource(this._c);
  final SupabaseClient _c;

  @override
  Future<List<Map<String, dynamic>>> fetch(
    String region, {
    String? since,
  }) async {
    var q = _c
        .from('speed_limit_overrides')
        .select('way_id, limit_mps, confidence, updated_at')
        .eq('region', region);
    if (since != null) q = q.gt('updated_at', since);
    final rows = await q;
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }
}

/// Uploads "limit is wrong here" flags and pulls the shared overrides
/// (docs/03 §4.4, docs/06 M2.8).
class LimitFlagsSync {
  LimitFlagsSync(
    this._db,
    this._outbox,
    this._client, {
    int Function()? now,
    OverridesSource? overrides,
    this.onConfirmedFlags,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _overrides =
           overrides ??
           (_client == null ? null : SupabaseOverridesSource(_client));

  final AppDatabase _db;
  final OutboxWorker _outbox;
  final SupabaseClient? _client;
  final OverridesSource? _overrides;
  final int Function() _now;
  StreamSubscription<List<LimitFlag>>? _sub;

  /// Called with the running total whenever a pull confirms more of this
  /// phone's flags (docs/02: Snitch at [snitchConfirmations]).
  final Future<void> Function(int confirmed)? onConfirmedFlags;

  /// Flags of yours the shared cache has confirmed before Snitch is earned
  /// (docs/02 §"Badges").
  static const int snitchConfirmations = 10;

  /// Settings key: JSON list of confirmed local flag ids, so a flag counts
  /// once however many pulls return its override.
  static const String confirmedFlagsKey = 'snitch:confirmed_flag_ids';

  /// Outbox kind `limit_flag`: `{flag_id, way_id, region, suggested_value,
  /// suggested_mph, suggested_mps}`.
  static const String kindFlag = 'limit_flag';

  /// How often the overrides are pulled per region.
  static const Duration pullInterval = Duration(hours: 24);

  /// How often the whole region is re-fetched instead of just the changes,
  /// so overrides retracted on the server leave the phone too.
  static const Duration fullRefreshInterval = Duration(days: 7);

  /// Slack subtracted from the server watermark so a row committed just
  /// after the previous pull read is never skipped.
  static const Duration watermarkSlack = Duration(seconds: 60);

  void start() {
    _sub ??= _db.watchUnsyncedLimitFlags().listen(_onFlags);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _onFlags(List<LimitFlag> flags) async {
    for (final f in flags) {
      final wayId = int.tryParse(f.wayId);
      if (wayId == null) {
        await _db.markLimitFlagSynced(f.id); // nothing the cloud can use
        continue;
      }
      final mph =
          resolveUnits(UnitsSetting.auto, packRegion: f.region) ==
          SpeedUnits.mph;
      final value = (mph ? mpsToMph(f.suggestedMps) : mpsToKmh(f.suggestedMps))
          .round();
      await _outbox.enqueue(kindFlag, {
        'flag_id': f.id,
        'way_id': wayId,
        'region': f.region ?? 'unknown',
        'suggested_value': value,
        'suggested_mph': mph,
        'suggested_mps': f.suggestedMps,
      }, id: '$kindFlag:${f.id}');
    }
  }

  void registerHandlers() {
    _outbox.register(kindFlag, (p) async {
      final c = _client;
      final uid = c?.auth.currentUser?.id;
      if (c == null || uid == null) throw const OutboxRetryLater('signed out');
      final value = (p['suggested_value'] as num).toInt().clamp(5, 160);
      await c
          .from('speed_limit_flags')
          .upsert(
            {
              'way_id': p['way_id'],
              'region': p['region'],
              'suggested_value': value,
              'suggested_mph': p['suggested_mph'],
              'suggested_mps': p['suggested_mps'],
              'user_id': uid,
            },
            onConflict: 'way_id,user_id',
            ignoreDuplicates: true,
          );
      await _db.markLimitFlagSynced((p['flag_id'] as num).toInt());
    });
  }

  static String _pulledAtKey(String region) => 'overrides_pulled_at:$region';
  static String _sinceKey(String region) => 'overrides_since:$region';
  static String _fullAtKey(String region) => 'overrides_full_at:$region';

  /// Pulls overrides for every installed region whose last pull is older
  /// than [pullInterval]. Incremental pulls use the newest server
  /// `updated_at` seen so far (minus [watermarkSlack]) as the watermark, never
  /// the phone clock; every [fullRefreshInterval] (or with [force]) the whole
  /// region is fetched and the cache replaced. Returns the regions refreshed.
  Future<List<String>> pullIfDue({bool force = false}) async {
    final source = _overrides;
    if (source == null) return const [];
    final regions = (await _db.installedPacks()).map((p) => p.region);
    final done = <String>[];
    for (final region in regions) {
      final last =
          int.tryParse(await _db.getSetting(_pulledAtKey(region)) ?? '') ?? 0;
      if (!force && _now() - last < pullInterval.inMilliseconds) continue;
      try {
        final since = await _db.getSetting(_sinceKey(region));
        final lastFull =
            int.tryParse(await _db.getSetting(_fullAtKey(region)) ?? '') ?? 0;
        final full =
            force ||
            since == null ||
            _now() - lastFull >= fullRefreshInterval.inMilliseconds;
        final rows = await source.fetch(region, since: full ? null : since);

        final merged = full
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(
                jsonDecode(
                      await _db.cacheGet(overridesCacheKey(region)) ?? '{}',
                    )
                    as Map,
              );
        DateTime? newest;
        for (final r in rows) {
          merged['${r['way_id']}'] = {
            'limit_mps': r['limit_mps'],
            'confidence': r['confidence'] ?? cloudOverrideConfidence,
          };
          final u = DateTime.tryParse('${r['updated_at'] ?? ''}');
          if (u != null && (newest == null || u.isAfter(newest))) newest = u;
        }
        await _db.cachePut(
          overridesCacheKey(region),
          jsonEncode(merged),
          _now(),
        );
        await noteConfirmedFlags(region, rows);
        if (newest != null) {
          await _db.setSetting(
            _sinceKey(region),
            newest.toUtc().subtract(watermarkSlack).toIso8601String(),
          );
        }
        if (full) await _db.setSetting(_fullAtKey(region), '${_now()}');
        await _db.setSetting(_pulledAtKey(region), '${_now()}');
        done.add(region);
      } catch (e) {
        debugPrint('overrides pull failed for $region: $e');
      }
    }
    return done;
  }

  /// Confirmed local flag ids read from settings.
  Future<Set<int>> confirmedFlagIds() async {
    final raw = await _db.getSetting(confirmedFlagsKey);
    if (raw == null) return {};
    try {
      return {for (final v in jsonDecode(raw) as List) (v as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  /// An override for a way this phone flagged, committed after the flag, is
  /// a confirmation of that flag. Each flag counts once. Fires
  /// [onConfirmedFlags] with the new total when anything was added.
  Future<int> noteConfirmedFlags(
    String region,
    List<Map<String, dynamic>> rows,
  ) async {
    final confirmed = await confirmedFlagIds();
    if (rows.isEmpty) return confirmed.length;
    final flags = await _db.limitFlagsInRegion(region);
    if (flags.isEmpty) return confirmed.length;
    var added = false;
    for (final r in rows) {
      final wayId = '${r['way_id']}';
      final updated = DateTime.tryParse(
        '${r['updated_at'] ?? ''}',
      )?.millisecondsSinceEpoch;
      for (final f in flags) {
        if (f.wayId != wayId || confirmed.contains(f.id)) continue;
        if (updated != null && f.createdAt > updated) continue;
        confirmed.add(f.id);
        added = true;
      }
    }
    if (added) {
      await _db.setSetting(
        confirmedFlagsKey,
        jsonEncode(confirmed.toList()..sort()),
      );
      await onConfirmedFlags?.call(confirmed.length);
    }
    return confirmed.length;
  }
}

final limitFlagsSyncProvider = Provider<LimitFlagsSync>((ref) {
  final sync = LimitFlagsSync(
    ref.watch(databaseProvider),
    ref.watch(outboxWorkerProvider),
    ref.watch(supabaseProvider),
    onConfirmedFlags: (confirmed) async {
      if (confirmed < LimitFlagsSync.snitchConfirmations) return;
      // Through the shared engine so the award uploads and posts like any
      // other badge.
      await ref.read(badgesSyncProvider).engine.award('snitch');
    },
  );
  sync.registerHandlers();
  ref.onDispose(sync.stop);
  return sync;
});

/// Cached cloud overrides for one region.
final overridesForRegionProvider =
    FutureProvider.family<Map<int, LimitOverride>, String>(
      (ref, region) => cachedOverrides(ref.watch(databaseProvider), region),
    );
