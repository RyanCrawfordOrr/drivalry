import 'package:drivalry_scoring/drivalry_scoring.dart'
    show SpeedUnits, formatSaved;
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/stats/stats_engine.dart';
import '../../widgets/units.dart';
import 'fun_facts.dart';

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
      color: DrivalryTheme.ink,
    ),
    WrappedCardData(
      id: 'distance',
      kicker: 'You covered',
      value: dist(t.distanceM),
      caption: '${formatHours(t.movingS)} behind the wheel',
      color: const Color(0xFF604139),
    ),
    WrappedCardData(
      id: 'score',
      kicker: 'Average Drive Score',
      value: scoreText(t.averageScore),
      caption: t.bestScore == null
          ? 'No scored trips this season'
          : 'Best ${t.bestScore} · ${t.cleanTrips} clean trips',
      color: const Color(0xFF60434F),
    ),
    WrappedCardData(
      id: 'habits',
      kicker: 'Night Owl',
      value: '${h.nightPercent} %',
      caption:
          'of your distance after dark · ${h.weekendPercent} % on weekends',
      color: const Color(0xFF433244),
    ),
    WrappedCardData(
      id: 'states',
      kicker: 'States visited',
      value: '${g.stateCodes.length}',
      caption: g.stateCodes.isEmpty
          ? 'Nothing matched to a pack yet'
          : g.stateCodes.take(8).join(' · '),
      color: const Color(0xFF60464F),
      states: g.stateCodes,
    ),
    WrappedCardData(
      id: 'groundhog',
      kicker: 'Groundhog Route',
      value: groundhog == null ? '–' : '${groundhog.count}×',
      caption: groundhog == null
          ? 'No route repeated yet'
          : '${groundhog.label}, again and again',
      shareCaption: groundhog == null
          ? null
          : 'the same route, again and again',
      color: const Color(0xFF67453F),
    ),
    WrappedCardData(
      id: 'reality',
      kicker: 'Over the limit for',
      value: RealityChecks.formatHoursOver(rc.secondsOverLimit),
      caption: rc.secondsOverLimit < 60
          ? 'Barely at all. Respect.'
          : 'It saved you ${formatSaved(rc.timeSavedS)}.',
      color: const Color(0xFF814130),
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
      color: const Color(0xFF4C3744),
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
      color: const Color(0xFF604048),
    ),
    WrappedCardData(
      id: 'outro',
      kicker: 'XP earned',
      value: '${t.xp}',
      caption: 'Drive well. See you next season.',
      color: const Color(0xFF30212E),
    ),
  ];
}

/// One Wrapped page as a widget. With [forShare] the caption drops anything
/// that names a place or a person.
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: data.color,
        borderRadius: forShare ? null : BorderRadius.circular(24),
      ),
      child: Padding(
        padding: EdgeInsets.all(28 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DRIVALRY · ${rangeLabel.toUpperCase()}',
              style: TextStyle(
                color: DrivalryTheme.paper.withValues(alpha: 0.78),
                fontSize: 13 * scale,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              data.kicker,
              style: TextStyle(
                color: DrivalryTheme.paper,
                fontSize: 22 * scale,
              ),
            ),
            SizedBox(height: 8 * scale),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                data.value,
                style: TextStyle(
                  color: DrivalryTheme.paper,
                  fontSize: 64 * scale,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
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
                  color: DrivalryTheme.paper.withValues(alpha: 0.78),
                  fontSize: 13 * scale,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
