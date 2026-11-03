import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/db/database.dart';

/// Remembers which celebrations have been shown, so a badge, a duel win, a
/// met challenge or a promotion is one moment and never a replay (docs/12 §5).
///
/// Shown ids are persisted in Settings. An in-memory set makes two listeners
/// that see the same event in the same frame agree on who shows it, and
/// moments queue behind each other so two that land together never stack.
class MomentLedger {
  MomentLedger(this.db);

  final AppDatabase db;
  final Set<String> _claimed = {};
  Future<void> _queue = Future.value();

  static String keyFor(String id) => 'moment:$id';

  Future<bool> shown(String id) async =>
      _claimed.contains(id) || await db.getSetting(keyFor(id)) != null;

  /// Marks [id] as shown. True only for the first call that gets there.
  Future<bool> claim(String id) async {
    if (!_claimed.add(id)) return false;
    if (await db.getSetting(keyFor(id)) != null) return false;
    await db.setSetting(keyFor(id), '1');
    return true;
  }

  /// Shows a celebration after any that is already on screen.
  Future<void> show(
    BuildContext context, {
    required String title,
    String? verdict,
    List<String> badges = const [],
    int? xp,
    String dismissLabel = 'Nice',
  }) {
    final done = _queue.then((_) async {
      if (!context.mounted) return;
      // Heavy when a badge, win or promotion lands (docs/12 §5).
      Haptics.celebrate();
      await showCelebration(
        context,
        title: title,
        verdict: verdict,
        badges: badges,
        xp: xp,
        dismissLabel: dismissLabel,
      );
    });
    _queue = done.catchError((Object _) {});
    return done;
  }

  /// One celebration for [id], the first time only and only while the app is
  /// in the foreground. Returns whether it was shown.
  Future<bool> celebrateOnce(
    BuildContext context, {
    required String id,
    required String title,
    String? verdict,
    List<String> badges = const [],
    int? xp,
    String dismissLabel = 'Nice',
  }) async {
    if (!appInForeground() || !context.mounted) return false;
    if (!await claim(id)) return false;
    if (!context.mounted) return false;
    await show(
      context,
      title: title,
      verdict: verdict,
      badges: badges,
      xp: xp,
      dismissLabel: dismissLabel,
    );
    return true;
  }
}

/// Whether a moment may be shown now. Null is the state before the platform
/// has reported one (first frame, tests) and counts as foreground.
bool appInForeground() {
  final s = WidgetsBinding.instance.lifecycleState;
  return s == null || s == AppLifecycleState.resumed;
}

/// True when [at] is within [within] before [now] (an hour of clock skew into
/// the future is tolerated). Old events are not worth a moment.
bool recentlyAt(DateTime? at, DateTime now, Duration within) {
  if (at == null) return false;
  final age = now.difference(at);
  return age <= within && age >= const Duration(hours: -1);
}

final momentLedgerProvider = Provider<MomentLedger>(
  (ref) => MomentLedger(ref.watch(databaseProvider)),
);
