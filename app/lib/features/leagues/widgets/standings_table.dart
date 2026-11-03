import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../data/repos/leagues_repo.dart';
import 'tier_chip.dart';

/// One week's table: rank, handle, XP, trips, tier and where it is heading.
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.week, required this.me});

  final WeekStandings week;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = week.rows;
    final total = rows.length;
    final zones = total > 5;
    // Ranks 1-5 promote even when they are also in the last five, so the
    // relegation zone starts after them.
    final relegationStart = math.max(total - 5, 5);
    final ends = week.finalized
        ? 'Final.'
        : 'Ends ${DateFormat.MMMEd().format(nextWeekStart(week.weekStart).subtract(const Duration(days: 1)))} at midnight.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${DateFormat.MMMd().format(week.weekStart)} to '
          '${DateFormat.MMMd().format(nextWeekStart(week.weekStart).subtract(const Duration(days: 1)))} · $ends',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nobody here yet. Invite a friend.'),
          ),
        for (var i = 0; i < rows.length; i++) ...[
          if (zones && i == 0) const ZoneLabel('Promotion zone', up: true),
          if (zones && i == relegationStart)
            const ZoneLabel('Relegation zone', up: false),
          StandingRow(row: rows[i], isMe: rows[i].userId == me),
        ],
        const SizedBox(height: 12),
        Text(
          zones
              ? 'Top five move up a tier on Sunday night, bottom five move '
                    'down. A week with no scored trips moves down regardless.'
              : 'With more than five members, the top five promote and the '
                    'bottom five demote on Sunday night.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class ZoneLabel extends StatelessWidget {
  const ZoneLabel(this.text, {super.key, required this.up});
  final String text;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = up ? const Color(0xFF2ECC71) : theme.colorScheme.error;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(
            up ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class StandingRow extends StatelessWidget {
  const StandingRow({super.key, required this.row, required this.isMe});
  final Standing row;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final arrow = row.promotes
        ? Icon(Icons.arrow_upward, size: 18, color: const Color(0xFF2ECC71))
        : row.demotes
        ? Icon(Icons.arrow_downward, size: 18, color: theme.colorScheme.error)
        : const SizedBox(width: 18);
    return Card(
      color: isMe
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : null,
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        onTap: () => context.push(Routes.userProfile(row.userId)),
        leading: SizedBox(
          width: 56,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '${row.rank}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              MemberAvatar(handle: row.handle, url: null, radius: 14),
            ],
          ),
        ),
        title: Text(
          '@${row.handle}${isMe ? ' (you)' : ''}',
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: row.trips == 0
            ? Text(
                "Didn't drive? That's fine. The league didn't wait.",
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              )
            : Text(
                '${row.trips} trip${row.trips == 1 ? '' : 's'}'
                '${row.rating != null ? ' · rating ${row.rating!.toStringAsFixed(0)}' : ''}',
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${row.xp} XP',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            TierChip(tier: row.tier, dense: true),
            const SizedBox(width: 4),
            arrow,
          ],
        ),
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.handle,
    required this.url,
    this.radius = 18,
  });
  final String handle;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = handle.isEmpty ? '?' : handle[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.secondaryContainer,
      foregroundImage: url == null ? null : NetworkImage(url!),
      child: Text(
        initial,
        style: TextStyle(
          color: theme.colorScheme.onSecondaryContainer,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}
