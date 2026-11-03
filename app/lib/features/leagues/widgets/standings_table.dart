import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../app/ui/ui.dart';
import '../../../data/repos/leagues_repo.dart';
import 'tier_pill.dart';

/// Green for "moving up"; relegation uses the scheme's error colour.
Color promotionColor(ColorScheme scheme) => DrivalryTheme.scoreColor(100);

/// One week's table: rank, avatar, handle, trips, XP, tier and where the
/// row is heading. Rows sit flat on the page, twelve apart, arrive staggered
/// and count their XP up; the promotion and relegation zones are kickers,
/// not boxes (docs/12 §5b, §7).
class StandingsTable extends StatelessWidget {
  const StandingsTable({super.key, required this.week, required this.me});

  final WeekStandings week;
  final String? me;

  @override
  Widget build(BuildContext context) {
    final rows = week.rows;
    final total = rows.length;
    final zones = total > 5;
    // Ranks 1-5 promote even when they are also in the last five, so the
    // relegation zone starts after them.
    final relegationStart = math.max(total - 5, 5);
    final fmt = DateFormat.MMMd();
    final end = nextWeekStart(week.weekStart).subtract(const Duration(days: 1));
    final range = '${fmt.format(week.weekStart)} to ${fmt.format(end)}';

    final children = <Widget>[];
    var lastWasRow = false;
    for (var i = 0; i < rows.length; i++) {
      if (zones && i == 0) {
        children.add(const ZoneLabel('Promotion zone', up: true));
        lastWasRow = false;
      }
      if (zones && i == relegationStart) {
        children.add(
          const Padding(
            padding: EdgeInsets.only(top: Space.md),
            child: ZoneLabel('Relegation zone', up: false),
          ),
        );
        lastWasRow = false;
      }
      if (lastWasRow) children.add(const SizedBox(height: Space.md));
      children.add(
        Reveal(
          delay: Reveal.stagger(i),
          child: StandingRow(row: rows[i], isMe: rows[i].userId == me),
        ),
      );
      lastWasRow = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          week.finalized
              ? '$range · Final'
              : '$range · ends Sunday at midnight',
          style: context.caption,
        ),
        const SizedBox(height: Space.lg),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xl),
            child: Text(
              'Nobody here yet. Invite a friend.',
              style: context.bodyMuted,
            ),
          ),
        ...children,
        const SizedBox(height: Space.xl),
        Text(
          zones
              ? 'Top five move up on Sunday night, bottom five move down.'
              : 'With six or more members, the top five move up on Sunday '
                    'night.',
          style: context.caption,
        ),
      ],
    );
  }
}

/// "Promotion zone" / "Relegation zone" as a coloured kicker with an arrow.
class ZoneLabel extends StatelessWidget {
  const ZoneLabel(this.text, {super.key, required this.up});
  final String text;
  final bool up;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = up ? promotionColor(scheme) : scheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          Icon(
            up ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Kicker(text, color: color),
        ],
      ),
    );
  }
}

/// One member: rank, avatar, handle and trips, then XP over the tier pill
/// and the movement arrow. The signed-in user's row is tinted; tapping opens
/// the profile. The rank numeral slides when it changes and the XP counts
/// up.
class StandingRow extends StatelessWidget {
  const StandingRow({super.key, required this.row, required this.isMe});
  final Standing row;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final arrow = row.promotes
        ? Icon(Icons.arrow_upward, size: 20, color: promotionColor(scheme))
        : row.demotes
        ? Icon(Icons.arrow_downward, size: 20, color: scheme.error)
        : null;
    final trips = row.trips == 0
        ? "Didn't drive. The league didn't wait."
        : [
            '${row.trips} trip${row.trips == 1 ? '' : 's'}',
            if (row.rating != null)
              'Driver Rating ${row.rating!.toStringAsFixed(0)}',
          ].join(' · ');
    final name = row.displayName.isNotEmpty ? row.displayName : row.handle;
    final rankStyle = context.title.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Material(
      color: isMe
          ? scheme.primaryContainer.withValues(alpha: 0.4)
          : Colors.transparent,
      borderRadius: Radii.tileRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Haptics.tap();
          context.push(Routes.userProfile(row.userId));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: AnimatedSwitcher(
                  duration: Motion.reveal,
                  switchInCurve: Motion.enter,
                  switchOutCurve: Motion.exit,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.4),
                        end: Offset.zero,
                      ).animate(a),
                      child: child,
                    ),
                  ),
                  child: Text(
                    '${row.rank}',
                    key: ValueKey(row.rank),
                    style: rankStyle,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Hero(
                tag: 'avatar-${row.userId}',
                child: Avatar(name: name, isMe: isMe),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A long handle takes a second line rather than an
                    // ellipsis; the right-hand cluster stays narrow for it.
                    Text(
                      '@${row.handle}',
                      style: context.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Three lines: the no-drive line needs them beside a
                    // "Learner" pill at 360 px.
                    Text(
                      trips,
                      style: context.caption,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AnimatedNumber(
                    value: row.xp,
                    suffix: ' XP',
                    style: context.label,
                  ),
                  const SizedBox(height: Space.xs),
                  TierPill(tier: row.tier),
                ],
              ),
              const SizedBox(width: Space.sm),
              SizedBox(width: 20, height: 20, child: arrow),
            ],
          ),
        ),
      ),
    );
  }
}
