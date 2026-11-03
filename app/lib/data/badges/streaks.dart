import 'package:drivalry_scoring/drivalry_scoring.dart' show Xp;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'badge_engine.dart';

/// The two streaks the product keeps (docs/01 §4.3). There is deliberately no
/// "drove today" streak.
class Streaks {
  const Streaks({required this.clean, required this.phoneFree});

  static const none = Streaks(clean: 0, phoneFree: 0);

  /// Consecutive scored trips at 80 or better, none reckless.
  final int clean;

  /// Consecutive scored trips with no phone handling.
  final int phoneFree;

  /// Streak XP added to the next trip (docs/02 §5): +5 from five clean trips,
  /// +10 from twenty.
  int get bonusXp {
    if (clean >= Xp.streak.tier2) return Xp.streak.tier2Xp.round();
    if (clean >= Xp.streak.tier1) return Xp.streak.tier1Xp.round();
    return 0;
  }

  /// Short caption for a card, or null when there is nothing to say.
  String? get label {
    if (clean == 0 && phoneFree == 0) return null;
    final parts = <String>[];
    if (clean > 0) parts.add('$clean clean');
    if (phoneFree > 0) parts.add('$phoneFree phone-free');
    final bonus = bonusXp > 0 ? ' · +$bonusXp XP' : '';
    return '${parts.join(' · ')}$bonus';
  }
}

/// Streaks over the newest-first scored trips.
Streaks computeStreaks(List<ScoredTrip> newestFirst) => Streaks(
  clean: streakLength(newestFirst, (t) => t.clean),
  phoneFree: streakLength(newestFirst, (t) => t.phoneFree),
);

/// Live streaks from the local database.
final streaksProvider = StreamProvider<Streaks>((ref) {
  final parser = ScoredTripParser();
  return ref
      .watch(databaseProvider)
      .watchScoredTripsWithScores(limit: 100)
      .map((rows) => computeStreaks(parser.parse(rows)));
});
