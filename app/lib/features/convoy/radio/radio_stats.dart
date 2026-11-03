import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';

/// Bytes that went through a TURN relay, per convoy, so the owner can watch
/// the Metered free allowance from the Diagnostics screen (docs/10 §7).
class RadioStats {
  RadioStats(this._db);
  final AppDatabase _db;

  static String key(String convoyId) => 'radio:$convoyId:relayed_bytes';
  static const totalKey = 'radio:total:relayed_bytes';

  Future<void> addRelayed(String convoyId, int bytes) async {
    if (bytes <= 0) return;
    for (final k in [key(convoyId), totalKey]) {
      final cur = int.tryParse(await _db.getSetting(k) ?? '0') ?? 0;
      await _db.setSetting(k, '${cur + bytes}');
    }
  }

  Future<int> relayed(String convoyId) async =>
      int.tryParse(await _db.getSetting(key(convoyId)) ?? '0') ?? 0;
}

final radioStatsProvider = Provider<RadioStats>(
  (ref) => RadioStats(ref.watch(databaseProvider)),
);

/// Relayed bytes for one convoy, live.
final relayedBytesProvider = StreamProvider.family<int, String>(
  (ref, convoyId) => ref
      .watch(databaseProvider)
      .watchSetting(RadioStats.key(convoyId))
      .map((v) => int.tryParse(v ?? '0') ?? 0),
);

/// Relayed bytes across every convoy on this phone, live.
final totalRelayedBytesProvider = StreamProvider<int>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(RadioStats.totalKey)
      .map((v) => int.tryParse(v ?? '0') ?? 0),
);
