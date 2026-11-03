import 'package:drivalry_scoring/drivalry_scoring.dart'
    show SpeedUnits, formatSaved;
import 'package:flutter/material.dart';

import '../../data/garage/fuel_math.dart' show formatVolume;
import '../../data/stats/stats_engine.dart';
import '../../widgets/units.dart';
import 'fun_facts.dart';

/// Every section of the Stats screen, in the order docs/01 §4.4 lists them.
List<FactSection> statsSections(DriverStats s, SpeedUnits units) {
  String dist(double m) => formatDistance(m, units);
  final t = s.totals;
  final r = s.records;
  final g = s.geography;
  final h = s.habits;
  final rc = s.reality;
  final so = s.social;
  final longest = r.longestTrip;
  return [
    FactSection(
      title: 'Totals',
      facts: [
        FunFact(
          label: 'Trips',
          value: '${t.trips}',
          hint: '${t.cleanTrips} clean',
          icon: Icons.route_outlined,
        ),
        FunFact(
          label: 'Distance',
          value: dist(t.distanceM),
          hint: 'Driver trips only',
          icon: Icons.straighten,
        ),
        FunFact(
          label: 'Behind the wheel',
          value: formatHours(t.movingS),
          hint: 'Moving time',
          icon: Icons.schedule,
        ),
        FunFact(
          label: 'Average score',
          value: scoreText(t.averageScore),
          hint: t.bestScore == null ? 'No scored trips' : 'Best ${t.bestScore}',
          icon: Icons.speed_outlined,
        ),
        FunFact(
          label: 'Fuel estimate',
          value: formatVolume(
            t.fuelLitres,
            useGallons: units == SpeedUnits.mph,
          ),
          hint: 'About ${formatMoney(t.fuelCost)}',
          icon: Icons.local_gas_station_outlined,
        ),
        FunFact(
          label: 'CO₂ estimate',
          value: '${t.co2Kg.round()} kg',
          hint: 'Tailpipe only',
          icon: Icons.co2,
        ),
        FunFact(
          label: 'XP',
          value: '${t.xp}',
          hint: 'Earned in this window',
          icon: Icons.stars_outlined,
        ),
      ],
    ),
    FactSection(
      title: 'Records',
      facts: [
        FunFact(
          label: 'Longest trip',
          value: longest == null ? '–' : dist(longest.trip.distanceM),
          hint: longest == null
              ? ''
              : formatDay(
                  DateTime.fromMillisecondsSinceEpoch(longest.trip.startedAt),
                ),
          icon: Icons.timeline,
        ),
        FunFact(
          label: 'Highest point',
          value: r.highestAltitudeM == null
              ? '–'
              : formatAltitude(r.highestAltitudeM!, units),
          hint: r.highestAltitudeM == null
              ? 'Needs GPS altitude'
              : 'Above sea level',
          icon: Icons.terrain_outlined,
        ),
        FunFact(
          label: 'Earliest start',
          value: r.earliestStart == null ? '–' : formatClock(r.earliestStart!),
          hint: 'Before 3 am counts as late',
          icon: Icons.wb_twilight_outlined,
        ),
        FunFact(
          label: 'Latest start',
          value: r.latestStart == null ? '–' : formatClock(r.latestStart!),
          hint: 'Night owl material',
          icon: Icons.nightlight_outlined,
        ),
        FunFact(
          label: 'Busiest day',
          value: '${r.mostTripsInDay} trips',
          hint: r.busiestDay == null ? '' : formatDay(r.busiestDay!),
          icon: Icons.calendar_today_outlined,
        ),
        FunFact(
          label: 'Longest clean streak',
          value: '${r.longestCleanStreak}',
          hint: 'Trips at 80+, none reckless',
          icon: Icons.verified_outlined,
        ),
      ],
    ),
    FactSection(
      title: 'Geography',
      facts: [
        FunFact(
          label: 'States visited',
          value: '${g.stateCodes.length}',
          hint: g.regions.length > g.stateCodes.length
              ? '+${g.regions.length - g.stateCodes.length} other regions'
              : 'From matched packs',
          icon: Icons.public,
        ),
        FunFact(
          label: 'Home radius',
          value: g.homeRadiusM == null ? '–' : dist(g.homeRadiusM!),
          hint: g.hasHome ? '90 % of distance within' : 'Save a Home place',
          icon: Icons.home_outlined,
        ),
        FunFact(
          label: 'Farthest from home',
          value: g.farthestFromHomeM == null ? '–' : dist(g.farthestFromHomeM!),
          hint: g.hasHome ? 'As the crow flies' : 'Save a Home place',
          icon: Icons.explore_outlined,
        ),
        FunFact(
          label: 'Most driven road',
          value: g.mostDrivenRoad ?? '–',
          hint: g.mostDrivenRoad == null
              ? 'Needs matched trips'
              : '${g.mostDrivenRoadTrips} trips',
          icon: Icons.signpost_outlined,
          shareable: false,
        ),
      ],
    ),
    FactSection(
      title: 'Habits',
      facts: [
        FunFact(
          label: 'Night Owl',
          value: '${h.nightPercent} %',
          hint: 'Of distance after dark',
          icon: Icons.dark_mode_outlined,
        ),
        FunFact(
          label: 'Weekend',
          value: '${h.weekendPercent} %',
          hint: '${h.weekendTrips} of ${h.weekendTrips + h.weekdayTrips} trips',
          icon: Icons.weekend_outlined,
        ),
        FunFact(
          label: 'Average trip',
          value: dist(h.averageDistanceM),
          hint: formatElapsed(Duration(seconds: h.averageMovingS.round())),
          icon: Icons.straighten,
        ),
        FunFact(
          label: 'Groundhog Route',
          value: h.groundhog == null ? '–' : '${h.groundhog!.count}×',
          hint: h.groundhog == null
              ? 'No repeated route yet'
              : h.groundhog!.label,
          icon: Icons.repeat,
          shareable: false,
        ),
        for (final p in h.topPlaces)
          FunFact(
            label: p.label,
            value: '${p.visits}',
            hint: 'Trips ending here',
            icon: Icons.place_outlined,
            shareable: false,
          ),
      ],
    ),
    FactSection(
      title: 'Reality checks',
      facts: [
        FunFact(
          label: 'Over the limit',
          value: RealityChecks.formatHoursOver(rc.secondsOverLimit),
          hint: rc.timeSavedLine == null
              ? 'Barely any'
              : 'Saved ${formatSaved(rc.timeSavedS)}',
          icon: Icons.hourglass_bottom_outlined,
        ),
        FunFact(
          label: 'Ticket-risk time',
          value: formatHours(rc.ticketRiskS),
          hint: '10+ over, or worse',
          icon: Icons.local_police_outlined,
        ),
        FunFact(
          label: 'Hard accelerations',
          value: '${rc.harshAccelCount}',
          hint: 'About ${formatMoney(rc.moneyBurned)} of fuel',
          icon: Icons.whatshot_outlined,
        ),
      ],
    ),
    FactSection(
      title: 'Social',
      facts: [
        FunFact(
          label: 'Convoys',
          value: '${so.convoysJoined}',
          hint: '${dist(so.convoyDistanceM)} in convoy',
          icon: Icons.groups_outlined,
        ),
        for (final c in so.topCompanions)
          FunFact(
            label: c.name,
            value: '${c.convoys}',
            hint: 'Convoys together',
            icon: Icons.person_outline,
            shareable: false,
          ),
        if (so.djTracks > 0)
          FunFact(
            label: 'DJ score',
            value: '${so.djTracks}',
            hint: 'Tracks played for the convoy',
            icon: Icons.headphones_outlined,
          ),
      ],
    ),
    if (s.vehicles.isNotEmpty)
      FactSection(
        title: 'Vehicles',
        facts: [
          for (final v in s.vehicles)
            FunFact(
              label: v.name,
              value: scoreText(v.averageScore),
              hint:
                  '${v.trips} trips · ${dist(v.distanceM)} · ${formatEconomyFor(v.lPer100km, units)}',
              icon: Icons.directions_car_outlined,
            ),
        ],
      ),
  ];
}
