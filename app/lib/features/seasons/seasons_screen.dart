import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/seasons_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import 'season_card.dart';

/// Every season as an editorial list: the running one as the hero, past
/// ones with this phone's numbers and the uploaded result, future ones with
/// their dates.
class SeasonsScreen extends ConsumerWidget {
  const SeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasons = ref.watch(seasonsProvider).value ?? builtInSeasons;
    final results = ref.watch(mySeasonResultsProvider).value ?? const [];
    final signedIn = ref.watch(isSignedInProvider);
    final now = DateTime.now();
    final fmt = DateFormat.MMMd();
    // The running season leads as the hero; the rest follow newest first.
    final newestFirst = [...seasons]
      ..sort((a, b) => b.number.compareTo(a.number));
    final sorted = [
      for (final s in newestFirst)
        if (s.contains(now)) s,
      for (final s in newestFirst)
        if (!s.contains(now)) s,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Seasons')),
      body: ListView(
        // 16 under the app bar; the last tile clears the navigation bar or
        // home indicator.
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            'A season is one quarter. Wrapped is built from your drives, on '
            'this phone.',
            style: context.caption,
          ),
          const SizedBox(height: Space.xl),
          for (var i = 0; i < sorted.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.md),
            Reveal(
              delay: Reveal.stagger(i),
              child: sorted[i].contains(now)
                  ? Consumer(
                      builder: (ctx, ref, _) => SeasonCardView(
                        season: sorted[i],
                        stats:
                            ref
                                .watch(seasonStatsProvider(sorted[i].id))
                                .value ??
                            SeasonStats.none,
                        now: now,
                        onWrapped: () => ctx.push(Routes.wrapped),
                      ),
                    )
                  : _SeasonTile(
                      season: sorted[i],
                      now: now,
                      fmt: fmt,
                      result: results
                          .where((r) => r.seasonId == sorted[i].id)
                          .firstOrNull,
                      signedIn: signedIn,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SeasonTile extends ConsumerWidget {
  const _SeasonTile({
    required this.season,
    required this.now,
    required this.fmt,
    required this.result,
    required this.signedIn,
  });

  final Season season;
  final DateTime now;
  final DateFormat fmt;
  final SeasonResult? result;
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final over = season.isOver(now);
    final stats = over ? ref.watch(seasonStatsProvider(season.id)).value : null;
    final r = result;
    // A past season with no trips on this phone predates the driver here:
    // nothing is uploaded for it, and nothing is pending (docs/02 §12.3).
    final beforeMe = over && stats != null && stats.trips == 0;
    final lines = <String>[
      '${fmt.format(season.startsOn)} to ${fmt.format(season.endsOn)}',
      if (beforeMe) 'Over before you started',
      if (over && stats != null && !beforeMe)
        '${stats.trips} trips · ${stats.xp} XP · average '
            '${stats.scoreAvg?.toStringAsFixed(0) ?? '–'}',
      if (over && r != null && r.bestTier != null)
        'Best tier ${r.bestTier!.label}'
            '${r.duelsWon + r.duelsLost > 0 ? ' · duels ${r.duelsWon}–${r.duelsLost}' : ''}',
      if (over && signedIn && r == null && !beforeMe)
        'Saved to your account when you are next online',
    ];
    return Tile(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(season.name, style: context.title),
                const SizedBox(height: 2),
                for (final l in lines) Text(l, style: context.caption),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Pill(
            over ? 'Over' : 'Upcoming',
            tone: over ? PillTone.neutral : PillTone.primary,
            compact: true,
          ),
        ],
      ),
    );
  }
}
