import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import 'badge_defs.dart';

const _defsKey = 'badges:defs';

/// Badge definitions: cached cloud copy first, then the `badges` table, and
/// the built-in list when neither is available.
final badgeDefsProvider = FutureProvider<List<BadgeDef>>((ref) async {
  final db = ref.watch(databaseProvider);
  final cached = await db.cacheGet(_defsKey);
  if (cached != null) {
    try {
      final list = [
        for (final j in jsonDecode(cached) as List)
          BadgeDef.fromJson(j as Map<String, dynamic>),
      ];
      if (list.isNotEmpty) return list;
    } catch (_) {
      // fall through to a refresh
    }
  }
  final client = ref.watch(supabaseProvider);
  if (client != null) {
    try {
      final rows = await client
          .from('badges')
          .select('id, name, description, category');
      final list = [for (final r in rows) BadgeDef.fromJson(r)];
      if (list.isNotEmpty) {
        await db.cachePut(
          _defsKey,
          jsonEncode([for (final d in list) d.toJson()]),
          DateTime.now().millisecondsSinceEpoch,
        );
        return list;
      }
    } catch (e) {
      debugPrint('badge definitions fetch failed: $e');
    }
  }
  return fallbackBadgeDefs;
});

/// A definition plus whether and when this phone earned it.
class MyBadge {
  const MyBadge({required this.def, this.awardedAt});
  final BadgeDef def;
  final DateTime? awardedAt;
  bool get earned => awardedAt != null;
}

/// Every badge, earned ones first (newest award first), then locked ones in
/// seed order.
final myBadgesProvider = StreamProvider<List<MyBadge>>((ref) async* {
  final defs = await ref.watch(badgeDefsProvider.future);
  final db = ref.watch(databaseProvider);
  yield* db.watchAllBadgeAwards().map((awards) {
    final byId = {for (final a in awards) a.badgeId: a.awardedAt};
    final list = [
      for (final d in defs)
        MyBadge(
          def: d,
          awardedAt: byId[d.id] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(byId[d.id]!),
        ),
    ];
    list.sort((a, b) {
      if (a.earned != b.earned) return a.earned ? -1 : 1;
      if (a.earned && b.earned) return b.awardedAt!.compareTo(a.awardedAt!);
      return 0;
    });
    return list;
  });
});
