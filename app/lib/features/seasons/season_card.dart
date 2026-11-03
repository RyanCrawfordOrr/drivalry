import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../data/repos/seasons_repo.dart';

/// All seasons, under the Leagues tab.
const String seasonsPath = '/leagues/seasons';

/// The running season on the Leagues tab: days left, this phone's numbers,
/// and the Season Wrapped link. Also kicks the end-of-season upload.
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

/// Pure card body, for tests and for the seasons list.
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
    final theme = Theme.of(context);
    final left = season.daysLeft(now);
    final over = season.isOver(now);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_month_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(season.name, style: theme.textTheme.titleMedium),
                ),
                Text(
                  over ? 'Over' : '$left day${left == 1 ? '' : 's'} left',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: season.progress(now),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Stat(label: 'Trips', value: '${stats.trips}'),
                _Stat(label: 'XP', value: '${stats.xp}'),
                _Stat(
                  label: 'Avg score',
                  value: stats.scoreAvg == null
                      ? '–'
                      : stats.scoreAvg!.toStringAsFixed(0),
                ),
                _Stat(label: 'Phone-free', value: '${stats.phoneFreeTrips}'),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onAllSeasons != null)
                  TextButton(
                    onPressed: onAllSeasons,
                    child: const Text('All seasons'),
                  ),
                if (onWrapped != null)
                  TextButton.icon(
                    onPressed: onWrapped,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Season Wrapped'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: theme.textTheme.labelSmall),
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
    final theme = Theme.of(context);
    final n = next;
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.calendar_month_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          n == null
              ? 'Between seasons'
              : '${n.name} starts ${DateFormat.MMMd().format(n.startsOn)}',
        ),
        subtitle: const Text(
          'Trips still count; the next season picks them up.',
        ),
        onTap: () => context.push(seasonsPath),
      ),
    );
  }
}
