import 'package:drivalry_scoring/drivalry_scoring.dart'
    show SpeedUnits, formatSaved;
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/ui/ui.dart';
import '../../data/stats/stats_engine.dart';
import '../../widgets/units.dart';
import 'fun_facts.dart';

/// The ten card colours, in card order, plus the intro's. Hard-coded on
/// purpose: these pages are also rendered off screen as share images, so
/// they must not follow the phone's theme.
// The Good Company palette: aubergine family, one card per shade.
const List<Color> wrappedPalette = [
  DrivalryTheme.ink, // cover
  Color(0xFF604139), // distance
  Color(0xFF60434F), // score
  Color(0xFF433244), // habits
  Color(0xFF60464F), // states
  Color(0xFF67453F), // repeat route
  Color(0xFF814130), // reality
  Color(0xFF4C3744), // records
  Color(0xFF604048), // social
  Color(0xFF30212E), // outro
];

/// One Wrapped page: a big number, a line of words, an accent colour.
class WrappedCardData {
  const WrappedCardData({
    required this.id,
    required this.kicker,
    required this.value,
    required this.caption,
    required this.color,
    this.shareCaption,
    this.states = const [],
  });

  final String id;
  final String kicker;
  final String value;

  /// Shown on screen. May name places or friends.
  final String caption;

  /// Used on the share image instead of [caption] when that would leak a
  /// place or a name; null means [caption] is safe.
  final String? shareCaption;
  final Color color;
  final List<String> states;

  String get captionForShare => shareCaption ?? caption;
}

/// Always ten cards, so the Wrapped has the same shape every season.
List<WrappedCardData> wrappedCards(DriverStats s, SpeedUnits units) {
  String dist(double m) => formatDistance(m, units);
  final t = s.totals;
  final r = s.records;
  final g = s.geography;
  final h = s.habits;
  final rc = s.reality;
  final so = s.social;
  final longest = r.longestTrip;
  final groundhog = h.groundhog;
  final companion = so.topCompanions.isEmpty ? null : so.topCompanions.first;
  return [
    WrappedCardData(
      id: 'cover',
      kicker: 'Your ${s.range.label}',
      value: '${t.trips}',
      caption: t.trips == 1 ? 'trip as the driver' : 'trips as the driver',
      color: wrappedPalette[0],
    ),
    WrappedCardData(
      id: 'distance',
      kicker: 'Distance driven',
      value: dist(t.distanceM),
      caption: '${formatHours(t.movingS)} behind the wheel',
      color: wrappedPalette[1],
    ),
    WrappedCardData(
      id: 'score',
      kicker: 'Average Drive Score',
      value: scoreText(t.averageScore),
      caption: t.bestScore == null
          ? 'No scored trips this season'
          : 'Best ${t.bestScore} · ${t.cleanTrips} clean trips',
      color: wrappedPalette[2],
    ),
    WrappedCardData(
      id: 'habits',
      kicker: 'Night Owl',
      value: '${h.nightPercent} %',
      caption: 'driven after dark · ${h.weekendPercent} % at weekends',
      color: wrappedPalette[3],
    ),
    WrappedCardData(
      id: 'states',
      kicker: 'States visited',
      value: '${g.stateCodes.length}',
      caption: g.stateCodes.isEmpty
          ? 'None yet. Drive somewhere new.'
          : g.stateCodes.take(8).join(' · '),
      color: wrappedPalette[4],
      states: g.stateCodes,
    ),
    WrappedCardData(
      id: 'groundhog',
      kicker: 'Your repeat route',
      value: groundhog == null ? '–' : '${groundhog.count}×',
      caption: groundhog == null
          ? 'No route repeated yet'
          : 'Usually ${groundhog.label}',
      shareCaption: groundhog == null ? null : 'The same route, over and over',
      color: wrappedPalette[5],
    ),
    WrappedCardData(
      id: 'reality',
      kicker: 'Time over the limit',
      value: RealityChecks.formatHoursOver(rc.secondsOverLimit),
      caption: rc.secondsOverLimit < 60
          ? 'Barely at all. Respect.'
          : 'It saved you ${formatSaved(rc.timeSavedS)}.',
      color: wrappedPalette[6],
    ),
    WrappedCardData(
      id: 'records',
      kicker: 'Longest trip',
      value: longest == null ? '–' : dist(longest.trip.distanceM),
      caption: [
        if (r.highestAltitudeM != null)
          'Highest point ${formatAltitude(r.highestAltitudeM!, units)}',
        'Busiest day ${r.mostTripsInDay} trips',
      ].join(' · '),
      color: wrappedPalette[7],
    ),
    WrappedCardData(
      id: 'social',
      kicker: 'Convoys',
      value: '${so.convoysJoined}',
      caption: so.convoysJoined == 0
          ? 'Start one from the Convoy tab'
          : '${dist(so.convoyDistanceM)} together'
                '${companion == null ? '' : ' · most with ${companion.name}'}',
      shareCaption: so.convoysJoined == 0
          ? null
          : '${dist(so.convoyDistanceM)} together',
      color: wrappedPalette[8],
    ),
    WrappedCardData(
      id: 'outro',
      kicker: 'XP earned',
      value: '${t.xp}',
      caption: 'Drive well. See you next season.',
      color: wrappedPalette[9],
    ),
  ];
}

/// The first page: the season's name arrives, then an invitation to swipe.
/// The kicker and title fade and slide in over 200 ms (docs/12 §5).
class WrappedIntroCard extends StatefulWidget {
  const WrappedIntroCard({super.key, required this.rangeLabel});
  final String rangeLabel;

  @override
  State<WrappedIntroCard> createState() => _WrappedIntroCardState();
}

class _WrappedIntroCardState extends State<WrappedIntroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.reveal,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    Widget enter(Widget child, double from) {
      if (reduce) return child;
      final a = CurvedAnimation(
        parent: _c,
        curve: Interval(from, 1, curve: Motion.enter),
      );
      return FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(a),
          child: child,
        ),
      );
    }

    final color = wrappedPalette.last;
    return _CardSurface(
      color: color,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Masthead(label: 'Season Wrapped', scale: 1),
            const Spacer(),
            enter(
              Text(
                'Your season',
                style: TextStyle(
                  color: DrivalryTheme.paper.withValues(alpha: 0.78),
                  fontSize: 13,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              0,
            ),
            const SizedBox(height: 8),
            enter(
              Text(
                widget.rangeLabel,
                style: const TextStyle(
                  color: DrivalryTheme.paper,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: -1,
                ),
              ),
              0.2,
            ),
            const SizedBox(height: 12),
            enter(
              const Text(
                'Swipe through your season.',
                style: TextStyle(color: DrivalryTheme.paper, fontSize: 18),
              ),
              0.4,
            ),
            const Spacer(),
            Icon(
              Icons.swipe_left_outlined,
              color: DrivalryTheme.paper.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// One Wrapped page as a widget. With [forShare] the caption drops anything
/// that names a place or a person. On screen the big number scales in.
class WrappedCard extends StatelessWidget {
  const WrappedCard({
    super.key,
    required this.data,
    required this.rangeLabel,
    this.forShare = false,
    this.handle,
  });

  final WrappedCardData data;
  final String rangeLabel;
  final bool forShare;
  final String? handle;

  @override
  Widget build(BuildContext context) {
    final scale = forShare ? 2.6 : 1.0;
    final value = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        data.value,
        style: TextStyle(
          color: DrivalryTheme.paper,
          fontSize: 64 * scale,
          fontWeight: FontWeight.w900,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return _CardSurface(
      color: data.color,
      radius: forShare ? null : 24,
      child: Padding(
        padding: EdgeInsets.all(28 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Masthead(label: 'Drivalry · $rangeLabel', scale: scale),
            const Spacer(),
            Text(
              data.kicker,
              style: TextStyle(
                color: DrivalryTheme.paper,
                fontSize: 22 * scale,
              ),
            ),
            SizedBox(height: 8 * scale),
            if (forShare || context.reduceMotion)
              value
            else
              TweenAnimationBuilder<double>(
                key: ValueKey(data.id),
                tween: Tween(begin: 0.8, end: 1),
                duration: Motion.screen,
                curve: Motion.enter,
                builder: (_, s, child) => Opacity(
                  opacity: ((s - 0.8) / 0.2).clamp(0, 1).toDouble(),
                  child: Transform.scale(
                    scale: s,
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                ),
                child: value,
              ),
            SizedBox(height: 12 * scale),
            Text(
              forShare ? data.captionForShare : data.caption,
              style: TextStyle(
                color: DrivalryTheme.paper,
                fontSize: 18 * scale,
                height: 1.3,
              ),
            ),
            const Spacer(),
            if (handle != null)
              Text(
                '@$handle',
                style: TextStyle(
                  color: DrivalryTheme.paper.withValues(alpha: 0.6),
                  fontSize: 13 * scale,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead({required this.label, required this.scale});
  final String label;
  final double scale;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: TextStyle(
      color: DrivalryTheme.paper.withValues(alpha: 0.78),
      fontSize: 13 * scale,
      letterSpacing: 2,
      fontWeight: FontWeight.w700,
    ),
  );
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.color,
    required this.child,
    required this.radius,
  });
  final Color color;
  final Widget child;
  final double? radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: radius == null ? null : BorderRadius.circular(radius!),
    ),
    child: child,
  );
}
