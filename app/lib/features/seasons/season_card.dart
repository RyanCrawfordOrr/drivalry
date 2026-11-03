import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/seasons_repo.dart';
import '../leagues/widgets/live_numbers.dart';

/// All seasons, under the Leagues tab.
const String seasonsPath = '/leagues/seasons';

/// The running season as the hero of the Leagues tab: name, days left
/// counting up, a thin bar, this phone's numbers, and the Wrapped. Also
/// kicks the end-of-season upload.
class SeasonCard extends ConsumerWidget {
  const SeasonCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(seasonUploadProvider);
    final seasons = ref.watch(seasonsProvider).value ?? builtInSeasons;
    final now = DateTime.now();
    final season = seasonFor(seasons, now);
    if (season == null) {
      Season? next;
      for (final s in seasons) {
        if (!s.hasStarted(now) &&
            (next == null || s.startsOn.isBefore(next.startsOn))) {
          next = s;
        }
      }
      return _BetweenSeasons(next: next);
    }
    final stats = ref.watch(seasonStatsProvider(season.id)).value;
    return SeasonCardView(
      season: season,
      stats: stats ?? SeasonStats.none,
      now: now,
      onWrapped: () => context.push(Routes.wrapped),
      onAllSeasons: () => context.push(seasonsPath),
    );
  }
}

/// Pure hero tile, for tests and for the seasons list.
class SeasonCardView extends StatelessWidget {
  const SeasonCardView({
    super.key,
    required this.season,
    required this.stats,
    required this.now,
    this.onWrapped,
    this.onAllSeasons,
  });

  final Season season;
  final SeasonStats stats;
  final DateTime now;
  final VoidCallback? onWrapped;
  final VoidCallback? onAllSeasons;

  @override
  Widget build(BuildContext context) {
    final left = season.daysLeft(now);
    final over = season.isOver(now);
    final avg = stats.scoreAvg == null
        ? '–'
        : stats.scoreAvg!.toStringAsFixed(0);
    return Tile(
      onTap: onAllSeasons,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Kicker(season.name)),
              if (onWrapped != null)
                TextButton.icon(
                  onPressed: onWrapped,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    minimumSize: const Size(0, 36),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                  label: const Text('Wrapped'),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (over)
            Text('Over', style: context.displaySmall)
          else
            CountingHero(
              value: left,
              unit: left == 1 ? 'day left' : 'days left',
            ),
          const SizedBox(height: Space.md),
          GrowBar(fraction: season.progress(now)),
          const SizedBox(height: Space.md),
          Text(
            '${stats.trips} trip${stats.trips == 1 ? '' : 's'} · '
            '${stats.xp} XP · average $avg · '
            '${stats.phoneFreeTrips} phone-free',
            style: context.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _BetweenSeasons extends StatelessWidget {
  const _BetweenSeasons({required this.next});
  final Season? next;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = next;
    return Tile(
      onTap: () => context.push(seasonsPath),
      child: Row(
        children: [
          Icon(Icons.calendar_month_outlined, color: scheme.primary),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n == null
                      ? 'Between seasons'
                      : '${n.name} starts ${DateFormat.MMMd().format(n.startsOn)}',
                  style: context.title,
                ),
                Text(
                  'Keep driving. The next season counts it all.',
                  style: context.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
