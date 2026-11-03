import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../data/repos/seasons_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import 'season_card.dart';

/// Every season: the running one in full, past ones with this phone's
/// numbers and the uploaded result, future ones with their dates.
class SeasonsScreen extends ConsumerWidget {
  const SeasonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final seasons = ref.watch(seasonsProvider).value ?? builtInSeasons;
    final results = ref.watch(mySeasonResultsProvider).value ?? const [];
    final signedIn = ref.watch(isSignedInProvider);
    final now = DateTime.now();
    final fmt = DateFormat.MMMd();
    final sorted = [...seasons]..sort((a, b) => b.number.compareTo(a.number));
    return Scaffold(
      appBar: AppBar(title: const Text('Seasons')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'A season is a quarter. When it ends, your phone writes one '
            'summary row (trips, XP, average score, badges) and Season '
            'Wrapped is built from your own trips, on the phone.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final s in sorted) ...[
            if (s.contains(now))
              Consumer(
                builder: (ctx, ref, _) => SeasonCardView(
                  season: s,
                  stats:
                      ref.watch(seasonStatsProvider(s.id)).value ??
                      SeasonStats.none,
                  now: now,
                  onWrapped: () => ctx.push(Routes.wrapped),
                ),
              )
            else
              _SeasonTile(
                season: s,
                now: now,
                fmt: fmt,
                result: results.where((r) => r.seasonId == s.id).firstOrNull,
                signedIn: signedIn,
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
    final theme = Theme.of(context);
    final over = season.isOver(now);
    final stats = over ? ref.watch(seasonStatsProvider(season.id)).value : null;
    final r = result;
    // A past season with no trips on this phone predates the driver here:
    // nothing is uploaded for it, and nothing is pending (docs/02 §12.3).
    final beforeMe = over && stats != null && stats.trips == 0;
    final lines = <String>[
      '${fmt.format(season.startsOn)} to ${fmt.format(season.endsOn)}',
      if (beforeMe) 'Before you joined',
      if (over && stats != null && !beforeMe)
        '${stats.trips} trips · ${stats.xp} XP · avg '
            '${stats.scoreAvg?.toStringAsFixed(0) ?? '–'}',
      if (over && r != null && r.bestTier != null)
        'Best tier ${r.bestTier!.label}'
            '${r.duelsWon + r.duelsLost > 0 ? ' · duels ${r.duelsWon}–${r.duelsLost}' : ''}',
      if (over && signedIn && r == null && !beforeMe)
        'Result uploads on the next sync',
    ];
    return Card(
      child: ListTile(
        leading: Icon(
          over ? Icons.history : Icons.schedule_outlined,
          color: over ? theme.colorScheme.outline : theme.colorScheme.primary,
        ),
        title: Text(season.name),
        subtitle: Text(lines.join('\n')),
        isThreeLine: lines.length > 2,
        trailing: Chip(
          label: Text(over ? 'Over' : 'Upcoming'),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
