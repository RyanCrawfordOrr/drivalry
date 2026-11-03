import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';

/// Per-device daily soft caps for the two paid-tier Google APIs.
///
/// The hard caps live in Google Cloud (Places 150/day, Routes 300/day for the
/// whole project; docs/03 §10). These local caps spread that budget across
/// devices and make the fallbacks kick in before the project quota does.
/// Counters are stored in `Settings` under `quota:<api>:<yyyy-mm-dd>`.
class GoogleQuota {
  GoogleQuota(
    this._db, {
    int Function()? now,
    this.placesPerDay = 20,
    this.routesPerDay = 40,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final int Function() _now;
  final int placesPerDay;
  final int routesPerDay;

  static const places = 'places';
  static const routes = 'routes';

  String _key(String api) {
    final d = DateTime.fromMillisecondsSinceEpoch(_now(), isUtc: true);
    final day =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return 'quota:$api:$day';
  }

  int _limit(String api) => api == places ? placesPerDay : routesPerDay;

  Future<int> used(String api) async =>
      int.tryParse(await _db.getSetting(_key(api)) ?? '0') ?? 0;

  Future<int> remaining(String api) async => _limit(api) - await used(api);

  /// Reserves one call. Returns false (and reserves nothing) when today's
  /// local cap is spent; callers then use their degraded path.
  Future<bool> tryConsume(String api) async {
    final n = await used(api);
    if (n >= _limit(api)) return false;
    await _db.setSetting(_key(api), '${n + 1}');
    return true;
  }

  /// Marks the cap as spent for today (called on HTTP 429 / RESOURCE_EXHAUSTED,
  /// which means the project-wide quota is gone).
  Future<void> exhaust(String api) =>
      _db.setSetting(_key(api), '${_limit(api)}');
}

final googleQuotaProvider = Provider<GoogleQuota>(
  (ref) => GoogleQuota(ref.watch(databaseProvider)),
);
