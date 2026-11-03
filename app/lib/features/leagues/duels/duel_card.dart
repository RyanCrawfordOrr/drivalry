import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repos/duels_repo.dart';
import '../widgets/standings_table.dart' show MemberAvatar;

/// One duel: both sides, the metric, who leads or won, time left. Pure: the
/// scoreboard comes in from outside so the card renders offline and in tests.
class DuelCard extends StatelessWidget {
  const DuelCard({
    super.key,
    required this.duel,
    required this.me,
    this.board,
    this.now,
    this.footer,
  });

  final Duel duel;
  final String? me;
  final DuelScoreboard? board;
  final DateTime? now;

  /// Buttons under the scoreboard (accept, decline, cancel, badge pick).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = now ?? DateTime.now();
    final meId = me;
    final mine = meId != null && !duel.isChallenger(meId)
        ? duel.opponent
        : duel.challenger;
    final other = mine == duel.challenger ? duel.opponent : duel.challenger;
    final status = duelStatusLine(duel, meId, board, n);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(duel.metric.label),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Side(
                    party: mine,
                    isMe: meId != null,
                    value: board?.valueFor(duel, mine.userId),
                    metric: duel.metric,
                    winner: duel.winnerId == mine.userId,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('vs', style: theme.textTheme.labelLarge),
                ),
                Expanded(
                  child: _Side(
                    party: other,
                    isMe: false,
                    value: board?.valueFor(duel, other.userId),
                    metric: duel.metric,
                    winner: duel.winnerId == other.userId,
                  ),
                ),
              ],
            ),
            if (footer != null) ...[const SizedBox(height: 8), footer!],
          ],
        ),
      ),
    );
  }
}

/// The one-line state of a duel from [me]'s point of view.
String duelStatusLine(
  Duel duel,
  String? me,
  DuelScoreboard? board,
  DateTime now,
) {
  final other = me == null ? duel.opponent : duel.other(me);
  switch (duel.status) {
    case DuelStatus.pending:
      if (me != null && duel.opponent.userId == me) {
        return 'Waiting for your answer';
      }
      return 'Waiting for @${other.handle} to answer';
    case DuelStatus.active:
      final ends = duel.endsAt;
      final left = ends == null ? '' : _timeLeft(ends, now);
      final leader = board?.leaderId(duel);
      final lead = board == null
          ? ''
          : leader == null
          ? 'Level'
          : (leader == me ? 'You lead' : '@${_handle(duel, leader)} leads');
      return [lead, left].where((s) => s.isNotEmpty).join(' · ');
    case DuelStatus.finished:
      if (duel.isDraw) return 'Draw';
      final won = duel.winnerId == me;
      var line = me == null
          ? '@${_handle(duel, duel.winnerId!)} won'
          : (won ? 'You won' : 'You lost');
      final badge = duel.loserBadgeId;
      if (badge != null && duel.finishedAt != null) {
        final until = DateFormat.MMMd().format(
          duel.finishedAt!.add(const Duration(days: 7)),
        );
        line += won
            ? ' · they wear ${duelBadgeName(badge)} until $until'
            : ' · you wear ${duelBadgeName(badge)} until $until';
      }
      return line;
    case DuelStatus.declined:
      return 'Declined';
    case DuelStatus.expired:
      return 'Expired unanswered';
  }
}

String _handle(Duel duel, String userId) => duel.challenger.userId == userId
    ? duel.challenger.handle
    : duel.opponent.handle;

String _timeLeft(DateTime ends, DateTime now) {
  final d = ends.difference(now);
  if (d.isNegative) return 'Ended, settling';
  if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h left';
  if (d.inHours >= 1) return '${d.inHours}h left';
  return '${d.inMinutes}m left';
}

class _Side extends StatelessWidget {
  const _Side({
    required this.party,
    required this.isMe,
    required this.value,
    required this.metric,
    required this.winner,
  });

  final DuelParty party;
  final bool isMe;
  final DuelValue? value;
  final DuelMetric metric;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    return Column(
      children: [
        MemberAvatar(handle: party.handle, url: party.avatarUrl, radius: 20),
        const SizedBox(height: 4),
        Text(
          isMe ? 'You' : '@${party.handle}',
          style: theme.textTheme.labelMedium,
          overflow: TextOverflow.ellipsis,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (winner)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.emoji_events,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
            Text(
              v == null ? '–' : metric.formatValue(v.value),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (v != null && metric == DuelMetric.scoreAvg)
          Text(
            v.trips < duelScoreAvgMinTrips
                ? '${v.trips} of $duelScoreAvgMinTrips trips'
                : '${v.trips} trips',
            style: theme.textTheme.labelSmall,
          ),
      ],
    );
  }
}
