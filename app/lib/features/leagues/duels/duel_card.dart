import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/duels_repo.dart';
import '../widgets/live_numbers.dart';

/// One duel as a tile: both avatars, who against whom, the one-line state,
/// the metric (and the result) as pills under it, the two values when there
/// is a scoreboard. Pure: the scoreboard comes in from outside so the card
/// renders offline and in tests.
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
    final n = now ?? DateTime.now();
    final meId = me;
    final mine = meId != null && !duel.isChallenger(meId)
        ? duel.opponent
        : duel.challenger;
    final other = mine == duel.challenger ? duel.opponent : duel.challenger;
    final status = duelStatusLine(duel, meId, board, n);
    final outcome = duelOutcome(duel, meId);
    final b = board;
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Pair(mine: mine, other: other, isMe: meId != null),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meId != null
                          ? 'You vs @${other.handle}'
                          : '@${mine.handle} vs @${other.handle}',
                      style: context.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(status, style: context.caption),
                    const SizedBox(height: Space.sm),
                    // The metric, and how it ended, under the words rather
                    // than beside them, so the title keeps its width at
                    // 360 px.
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      children: [
                        if (outcome == DuelOutcome.won)
                          const Pill(
                            'You won',
                            tone: PillTone.positive,
                            compact: true,
                          )
                        else if (outcome == DuelOutcome.lost)
                          const Pill('You lost', compact: true),
                        Pill(duel.metric.label, compact: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (b != null) ...[
            const SizedBox(height: Space.lg),
            // How the week is split between the two of us; level is half.
            GrowBar(fraction: _share(b, duel, mine.userId)),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: _Score(
                    name: meId != null ? 'You' : '@${mine.handle}',
                    value: b.valueFor(duel, mine.userId),
                    metric: duel.metric,
                    leads: b.leaderId(duel) == mine.userId,
                  ),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: _Score(
                    name: '@${other.handle}',
                    value: b.valueFor(duel, other.userId),
                    metric: duel.metric,
                    leads: b.leaderId(duel) == other.userId,
                  ),
                ),
              ],
            ),
          ],
          if (footer != null) ...[const SizedBox(height: Space.lg), footer!],
        ],
      ),
    );
  }
}

/// [userId]'s share of the two values, 0.5 when both are zero.
double _share(DuelScoreboard b, Duel duel, String userId) {
  final mine = b.valueFor(duel, userId).value;
  final other =
      (duel.challenger.userId == userId ? b.opponent : b.challenger).value;
  final total = mine + other;
  return total <= 0 ? 0.5 : mine / total;
}

enum DuelOutcome { won, lost, draw }

/// How a finished duel went for [me]; null while it runs or for a stranger.
DuelOutcome? duelOutcome(Duel duel, String? me) {
  if (!duel.isFinished || me == null) return null;
  if (duel.isDraw) return DuelOutcome.draw;
  return duel.winnerId == me ? DuelOutcome.won : DuelOutcome.lost;
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
      if (me == null) return '@${_handle(duel, duel.winnerId!)} won';
      final won = duel.winnerId == me;
      final badge = duel.loserBadgeId;
      if (badge == null || duel.finishedAt == null) {
        return won
            ? 'Pick a badge for @${other.handle}'
            : 'Waiting for @${other.handle} to pick your badge';
      }
      final until = DateFormat.MMMd().format(
        duel.finishedAt!.add(const Duration(days: 7)),
      );
      return won
          ? 'They wear ${duelBadgeName(badge)} until $until'
          : 'You wear ${duelBadgeName(badge)} until $until';
    case DuelStatus.declined:
      return 'Declined';
    case DuelStatus.expired:
      return 'Never answered. It lapsed.';
  }
}

/// "You beat @sam on phone-free trips", for the celebration.
String duelWinLine(Duel duel, String me) =>
    'You beat @${duel.other(me).handle} on ${duelMetricPhrase(duel.metric)}';

String duelMetricPhrase(DuelMetric metric) => switch (metric) {
  DuelMetric.xp => 'XP',
  DuelMetric.scoreAvg => 'Drive Score',
  DuelMetric.phoneFree => 'phone-free trips',
};

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

/// The two avatars, overlapping; mine first with the ring.
class _Pair extends StatelessWidget {
  const _Pair({required this.mine, required this.other, required this.isMe});
  final DuelParty mine;
  final DuelParty other;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).colorScheme.surfaceContainerLow;
    Widget ring(Widget child) => Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: child,
    );
    String name(DuelParty p) =>
        p.displayName.isNotEmpty ? p.displayName : p.handle;
    return SizedBox(
      width: 72,
      height: 48,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 2,
            child: ring(Avatar(name: name(mine), isMe: isMe)),
          ),
          Positioned(left: 24, top: 2, child: ring(Avatar(name: name(other)))),
        ],
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({
    required this.name,
    required this.value,
    required this.metric,
    required this.leads,
  });

  final String name;
  final DuelValue value;
  final DuelMetric metric;
  final bool leads;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric.formatValue(value.value),
          style: context.title.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: leads ? scheme.primary : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          metric == DuelMetric.scoreAvg && value.trips < duelScoreAvgMinTrips
              ? '$name · needs $duelScoreAvgMinTrips trips, has ${value.trips}'
              : name,
          style: context.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
