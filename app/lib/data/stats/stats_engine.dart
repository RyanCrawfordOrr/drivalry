import 'dart:math' as math;

import 'package:drivalry_scoring/drivalry_scoring.dart'
    show EventKind, Severity, formatSaved, haversine;

import '../badges/badge_engine.dart' show ScoredTrip, streakLength;
import '../db/database.dart';
import '../garage/fuel_math.dart';
import '../repos/convoy_models.dart' show ConvoyMember;

/// Stats and fun facts (docs/01 §4.4), computed on the phone from the trips
/// in a time window. Everything here is a pure function of [StatsInput];
/// the providers in `stats_providers.dart` gather the input from drift.
///
/// Deliberately never surfaces top speed or any speed record: the product
/// never rewards speed, so none of these numbers can be gamed by driving
/// faster.

/// Default petrol price used for the fuel-cost estimate until the user sets
/// one (`stats_fuel_price_per_litre`): about US$3.50 a gallon.
const double defaultFuelPricePerLitre = 0.92;

/// Default economy for cars without fill-up data
/// (`stats_default_l_per_100km`): about 25 mpg (US).
const double defaultLitresPer100km = 9.4;

/// Kilograms of CO₂ per litre of petrol burned (tailpipe only).
const double co2KgPerLitre = 2.31;

/// Extra fuel one hard acceleration costs over a smooth one, a rough
/// engineering estimate used for the "money burned" line.
const double litresPerHarshAccel = 0.03;

/// Speed over the posted limit (m/s) from which a speeding event counts as
/// ticket risk: 10 mph.
const double ticketRiskOverMps = 4.4704;

/// Grid used to decide two trips ran the same route (about 550 m).
const double _routeGridDeg = 0.005;

/// Extra slack added to a saved place's radius when matching trip ends.
const double _placeSlackM = 100;

/// Time-of-day cut: starts before this hour count as "late", not "early".
const int _lateNightCutHour = 3;

enum StatsWindow {
  month('This month'),
  season('This season'),
  allTime('All time');

  const StatsWindow(this.label);
  final String label;
}

/// A half-open local time range `[start, end)`; null bounds are open.
class StatsRange {
  const StatsRange({required this.label, this.start, this.end});

  factory StatsRange.forWindow(StatsWindow window, DateTime now) =>
      switch (window) {
        StatsWindow.month => StatsRange.month(now),
        StatsWindow.season => StatsRange.season(now),
        StatsWindow.allTime => const StatsRange(label: 'All time'),
      };

  factory StatsRange.month(DateTime now) {
    final start = DateTime(now.year, now.month);
    return StatsRange(
      label: '${_monthName(start.month)} ${start.year}',
      start: start,
      end: DateTime(now.year, now.month + 1),
    );
  }

  /// A season is a calendar quarter, named by its months so it reads the
  /// same in both hemispheres ("Oct–Dec 2026").
  factory StatsRange.season(DateTime now) {
    final q = (now.month - 1) ~/ 3;
    final start = DateTime(now.year, q * 3 + 1);
    final end = DateTime(now.year, q * 3 + 4);
    return StatsRange(label: seasonLabel(start), start: start, end: end);
  }

  factory StatsRange.previousSeason(DateTime now) {
    final q = (now.month - 1) ~/ 3;
    return StatsRange.season(
      DateTime(now.year, q * 3 + 1).subtract(const Duration(days: 1)),
    );
  }

  static String seasonLabel(DateTime start) =>
      '${_monthName(start.month)}–${_monthName(start.month + 2)} ${start.year}';

  final String label;
  final DateTime? start;
  final DateTime? end;

  bool get isAllTime => start == null && end == null;

  bool contains(int epochMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    if (start != null && t.isBefore(start!)) return false;
    if (end != null && !t.isBefore(end!)) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is StatsRange &&
      other.label == label &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(label, start, end);
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _monthName(int month) => _months[(month - 1) % 12];

/// Everything the engine reads. Every collection may be empty; the engine
/// degrades to nulls and zeros rather than throwing.
class StatsInput {
  const StatsInput({
    required this.trips,
    this.extents = const {},
    this.endpoints = const {},
    this.roadsByTrip = const {},
    this.places = const [],
    this.vehicles = const [],
    this.fuelStats = const {},
    this.convoys = const [],
    this.convoyMembers = const {},
    this.djTracksByConvoy = const {},
    this.myUserId,
    this.fuelPricePerLitre = defaultFuelPricePerLitre,
    this.defaultLPer100km = defaultLitresPer100km,
  });

  /// Scored driver trips, newest first (as `watchScoredTripsWithScores`).
  final List<ScoredTrip> trips;
  final Map<String, TripExtent> extents;
  final Map<String, TripEndpoints> endpoints;
  final Map<String, Set<String>> roadsByTrip;
  final List<Place> places;
  final List<Vehicle> vehicles;

  /// Measured economy per vehicle id, from fill-ups.
  final Map<String, FuelStats> fuelStats;
  final List<ConvoyLocalData> convoys;
  final Map<String, List<ConvoyMember>> convoyMembers;

  /// Tracks this user played as Convoy DJ, per convoy (from stored recaps).
  final Map<String, int> djTracksByConvoy;
  final String? myUserId;
  final double fuelPricePerLitre;
  final double defaultLPer100km;
}

// ------------------------------------------------------------- output --

class Totals {
  const Totals({
    required this.trips,
    required this.distanceM,
    required this.movingS,
    required this.fuelLitres,
    required this.fuelCost,
    required this.co2Kg,
    required this.averageScore,
    required this.bestScore,
    required this.cleanTrips,
    required this.xp,
  });

  static const empty = Totals(
    trips: 0,
    distanceM: 0,
    movingS: 0,
    fuelLitres: 0,
    fuelCost: 0,
    co2Kg: 0,
    averageScore: null,
    bestScore: null,
    cleanTrips: 0,
    xp: 0,
  );

  final int trips;
  final double distanceM;
  final double movingS;

  /// Estimated from distance and economy (measured per car when fill-ups
  /// exist, else [StatsInput.defaultLPer100km]).
  final double fuelLitres;

  /// [fuelLitres] × the fuel price setting, in the user's currency.
  final double fuelCost;
  final double co2Kg;
  final double? averageScore;
  final int? bestScore;
  final int cleanTrips;
  final int xp;
}

class Records {
  const Records({
    this.longestTrip,
    this.highestAltitudeM,
    this.earliestStart,
    this.latestStart,
    this.mostTripsInDay = 0,
    this.busiestDay,
    this.longestCleanStreak = 0,
    this.currentCleanStreak = 0,
  });

  static const empty = Records();

  final ScoredTrip? longestTrip;
  final double? highestAltitudeM;

  /// Trip starts as local times of day; "earliest" ignores starts before
  /// 3 am, which count as late instead.
  final DateTime? earliestStart;
  final DateTime? latestStart;
  final int mostTripsInDay;
  final DateTime? busiestDay;
  final int longestCleanStreak;

  /// Consecutive clean trips ending with the newest one in the window.
  final int currentCleanStreak;
}

class Geography {
  const Geography({
    this.regions = const [],
    this.homeRadiusM,
    this.farthestFromHomeM,
    this.mostDrivenRoad,
    this.mostDrivenRoadTrips = 0,
    this.hasHome = false,
  });

  static const empty = Geography();

  /// Pack regions the trips were matched against (`us-tx`), most trips first.
  final List<String> regions;

  /// US state codes among [regions], upper case ("TX"), same order.
  List<String> get stateCodes => [
    for (final r in regions)
      if (r.startsWith('us-')) r.substring(3).toUpperCase(),
  ];

  /// Radius around Home that holds 90 % of the distance driven.
  final double? homeRadiusM;
  final double? farthestFromHomeM;

  /// Road name that appears in the most trips. Stays on the phone: it is
  /// never put on a share card.
  final String? mostDrivenRoad;
  final int mostDrivenRoadTrips;
  final bool hasHome;
}

class PlaceVisits {
  const PlaceVisits({required this.label, required this.visits});
  final String label;
  final int visits;
}

/// The most repeated start→end pair. Labels come from saved places and are
/// null when neither end is one; share cards show only the count.
class GroundhogRoute {
  const GroundhogRoute({required this.count, this.fromLabel, this.toLabel});
  final int count;
  final String? fromLabel;
  final String? toLabel;

  String get label => fromLabel != null && toLabel != null
      ? '$fromLabel → $toLabel'
      : 'your usual route';
}

class Habits {
  const Habits({
    this.nightFraction = 0,
    this.weekdayTrips = 0,
    this.weekendTrips = 0,
    this.averageDistanceM = 0,
    this.averageMovingS = 0,
    this.topPlaces = const [],
    this.groundhog,
  });

  static const empty = Habits();

  /// Distance-weighted share of driving after dark, 0..1.
  final double nightFraction;
  final int weekdayTrips;
  final int weekendTrips;
  final double averageDistanceM;
  final double averageMovingS;
  final List<PlaceVisits> topPlaces;
  final GroundhogRoute? groundhog;

  int get nightPercent => (nightFraction * 100).round();
  int get weekendPercent {
    final n = weekdayTrips + weekendTrips;
    return n == 0 ? 0 : (weekendTrips * 100 / n).round();
  }
}

class RealityChecks {
  const RealityChecks({
    this.secondsOverLimit = 0,
    this.timeSavedS = 0,
    this.ticketRiskS = 0,
    this.harshAccelCount = 0,
    this.moneyBurned = 0,
  });

  static const empty = RealityChecks();

  final double secondsOverLimit;

  /// Seconds the speeding actually saved versus driving at the limit, from
  /// the scoring engine's per-trip figure.
  final double timeSavedS;

  /// Seconds spent 10+ mph over the limit or in a major-or-worse event.
  final double ticketRiskS;
  final int harshAccelCount;

  /// Hard accelerations × [litresPerHarshAccel] × fuel price.
  final double moneyBurned;

  /// "You drove over the limit for 4.2 h. It saved you 11 minutes."
  String? get timeSavedLine {
    if (secondsOverLimit < 60) return null;
    return 'You drove over the limit for ${formatHoursOver(secondsOverLimit)}. '
        'It saved you ${formatSaved(timeSavedS)}.';
  }

  static String formatHoursOver(double s) {
    if (s >= 3600) {
      final h = s / 3600;
      return h >= 10 ? '${h.round()} h' : '${h.toStringAsFixed(1)} h';
    }
    return '${(s / 60).round()} min';
  }
}

class Companion {
  const Companion({
    required this.userId,
    required this.name,
    required this.convoys,
  });
  final String userId;
  final String name;
  final int convoys;
}

class Social {
  const Social({
    this.convoysJoined = 0,
    this.convoyDistanceM = 0,
    this.topCompanions = const [],
    this.djTracks = 0,
  });

  static const empty = Social();

  final int convoysJoined;

  /// Distance of own trips driven while a convoy member.
  final double convoyDistanceM;
  final List<Companion> topCompanions;
  final int djTracks;
}

class VehicleStatLine {
  const VehicleStatLine({
    required this.vehicleId,
    required this.name,
    required this.trips,
    required this.distanceM,
    this.averageScore,
    this.lPer100km,
    this.fuelLitres = 0,
  });

  final String vehicleId;
  final String name;
  final int trips;
  final double distanceM;
  final double? averageScore;

  /// Measured from fill-ups when available, else null (the estimate below
  /// then uses the default economy).
  final double? lPer100km;
  final double fuelLitres;
}

class DriverStats {
  const DriverStats({
    required this.range,
    required this.totals,
    required this.records,
    required this.geography,
    required this.habits,
    required this.reality,
    required this.social,
    required this.vehicles,
  });

  factory DriverStats.empty(StatsRange range) => DriverStats(
    range: range,
    totals: Totals.empty,
    records: Records.empty,
    geography: Geography.empty,
    habits: Habits.empty,
    reality: RealityChecks.empty,
    social: Social.empty,
    vehicles: const [],
  );

  final StatsRange range;
  final Totals totals;
  final Records records;
  final Geography geography;
  final Habits habits;
  final RealityChecks reality;
  final Social social;
  final List<VehicleStatLine> vehicles;

  bool get isEmpty => totals.trips == 0;
}

// ------------------------------------------------------------ compute --

/// Computes every section for the trips of [input] that start inside
/// [range]. Pure and synchronous; a few thousand trips take milliseconds.
DriverStats computeDriverStats(StatsInput input, StatsRange range) {
  final trips = [
    for (final t in input.trips)
      if (range.contains(t.trip.startedAt)) t,
  ];
  if (trips.isEmpty) return DriverStats.empty(range);
  final econ = _EconomyLookup(input);
  return DriverStats(
    range: range,
    totals: _totals(trips, input, econ),
    records: _records(trips, input),
    geography: _geography(trips, input),
    habits: _habits(trips, input),
    reality: _reality(trips, input),
    social: _social(trips, input, range),
    vehicles: _vehicles(trips, input, econ),
  );
}

class _EconomyLookup {
  _EconomyLookup(this.input);
  final StatsInput input;

  /// Litres per 100 km for a trip: the car's measured figure when it has one.
  double forTrip(ScoredTrip t) =>
      measured(t.trip.vehicleId) ?? input.defaultLPer100km;

  double? measured(String? vehicleId) {
    if (vehicleId == null) return null;
    final v = input.fuelStats[vehicleId]?.lPer100km;
    if (v == null || v.isNaN || !v.isFinite || v <= 0) return null;
    return v;
  }

  double litres(ScoredTrip t) => t.trip.distanceM / 1000 * forTrip(t) / 100;
}

Totals _totals(List<ScoredTrip> trips, StatsInput input, _EconomyLookup econ) {
  var distance = 0.0;
  var moving = 0.0;
  var litres = 0.0;
  var scoreSum = 0;
  var scored = 0;
  int? best;
  var clean = 0;
  var xp = 0;
  for (final t in trips) {
    distance += t.trip.distanceM;
    moving += t.trip.movingS > 0 ? t.trip.movingS : t.score.summary.movingTimeS;
    litres += econ.litres(t);
    xp += t.score.xp;
    if (t.score.scored) {
      scored++;
      scoreSum += t.score.score;
      if (best == null || t.score.score > best) best = t.score.score;
    }
    if (t.clean) clean++;
  }
  return Totals(
    trips: trips.length,
    distanceM: distance,
    movingS: moving,
    fuelLitres: litres,
    fuelCost: litres * input.fuelPricePerLitre,
    co2Kg: litres * co2KgPerLitre,
    averageScore: scored == 0 ? null : scoreSum / scored,
    bestScore: best,
    cleanTrips: clean,
    xp: xp,
  );
}

Records _records(List<ScoredTrip> trips, StatsInput input) {
  ScoredTrip? longest;
  double? altitude;
  DateTime? earliest;
  DateTime? latest;
  final perDay = <DateTime, int>{};
  for (final t in trips) {
    if (longest == null || t.trip.distanceM > longest.trip.distanceM) {
      longest = t;
    }
    final alt = input.extents[t.trip.id]?.maxAltitudeM;
    if (alt != null && (altitude == null || alt > altitude)) altitude = alt;
    final start = DateTime.fromMillisecondsSinceEpoch(t.trip.startedAt);
    final minutes = _lateAwareMinutes(start);
    if (minutes >= _lateNightCutHour * 60 &&
        (earliest == null || minutes < _lateAwareMinutes(earliest))) {
      earliest = start;
    }
    if (latest == null || minutes > _lateAwareMinutes(latest)) latest = start;
    final day = DateTime(start.year, start.month, start.day);
    perDay[day] = (perDay[day] ?? 0) + 1;
  }
  DateTime? busiest;
  var most = 0;
  for (final e in perDay.entries) {
    if (e.value > most ||
        (e.value == most && busiest != null && e.key.isAfter(busiest))) {
      most = e.value;
      busiest = e.key;
    }
  }
  // Oldest first for the longest run; newest first for the current one.
  var longestClean = 0;
  var run = 0;
  for (final t in trips.reversed) {
    run = t.clean ? run + 1 : 0;
    if (run > longestClean) longestClean = run;
  }
  return Records(
    longestTrip: longest,
    highestAltitudeM: altitude,
    earliestStart: earliest,
    latestStart: latest,
    mostTripsInDay: most,
    busiestDay: busiest,
    longestCleanStreak: longestClean,
    currentCleanStreak: streakLength(trips, (t) => t.clean),
  );
}

/// Minutes since midnight, with the small hours moved past midnight so that
/// a 1 am start ranks later than an 11 pm one.
int _lateAwareMinutes(DateTime t) {
  final m = t.hour * 60 + t.minute;
  return m < _lateNightCutHour * 60 ? m + 24 * 60 : m;
}

Geography _geography(List<ScoredTrip> trips, StatsInput input) {
  final regionCounts = <String, int>{};
  final roadCounts = <String, int>{};
  for (final t in trips) {
    final r = t.trip.packRegion?.toLowerCase();
    if (r != null && r.isNotEmpty) regionCounts[r] = (regionCounts[r] ?? 0) + 1;
    for (final road in input.roadsByTrip[t.trip.id] ?? const <String>{}) {
      roadCounts[road] = (roadCounts[road] ?? 0) + 1;
    }
  }
  final regions = regionCounts.keys.toList()
    ..sort((a, b) {
      final c = regionCounts[b]!.compareTo(regionCounts[a]!);
      return c != 0 ? c : a.compareTo(b);
    });
  String? road;
  var roadTrips = 0;
  for (final e in roadCounts.entries) {
    if (e.value > roadTrips ||
        (e.value == roadTrips && road != null && e.key.compareTo(road) < 0)) {
      road = e.key;
      roadTrips = e.value;
    }
  }
  final home = _home(input.places);
  double? radius;
  double? farthest;
  if (home != null) {
    // Farthest corner of each trip's bounding box from Home, weighted by the
    // trip's distance; the 90th weighted percentile is the home radius.
    final rows = <({double d, double w})>[];
    var total = 0.0;
    for (final t in trips) {
      final e = input.extents[t.trip.id];
      if (e == null) continue;
      final d = [
        haversine(home.lat, home.lon, e.minLat, e.minLon),
        haversine(home.lat, home.lon, e.minLat, e.maxLon),
        haversine(home.lat, home.lon, e.maxLat, e.minLon),
        haversine(home.lat, home.lon, e.maxLat, e.maxLon),
      ].reduce(math.max);
      final w = t.trip.distanceM > 0 ? t.trip.distanceM : 1.0;
      rows.add((d: d, w: w));
      total += w;
      if (farthest == null || d > farthest) farthest = d;
    }
    if (rows.isNotEmpty) {
      rows.sort((a, b) => a.d.compareTo(b.d));
      var acc = 0.0;
      for (final r in rows) {
        acc += r.w;
        radius = r.d;
        if (acc >= total * 0.9) break;
      }
    }
  }
  return Geography(
    regions: regions,
    homeRadiusM: radius,
    farthestFromHomeM: farthest,
    mostDrivenRoad: road,
    mostDrivenRoadTrips: roadTrips,
    hasHome: home != null,
  );
}

Place? _home(List<Place> places) {
  for (final p in places) {
    if (p.kind == 'home') return p;
  }
  return null;
}

Place? _placeAt(List<Place> places, double lat, double lon) {
  Place? best;
  double? bestD;
  for (final p in places) {
    final d = haversine(p.lat, p.lon, lat, lon);
    if (d <= p.radiusM + _placeSlackM && (bestD == null || d < bestD)) {
      best = p;
      bestD = d;
    }
  }
  return best;
}

Habits _habits(List<ScoredTrip> trips, StatsInput input) {
  var nightWeighted = 0.0;
  var distance = 0.0;
  var moving = 0.0;
  var weekend = 0;
  var weekday = 0;
  final visits = <String, int>{};
  final routes = <String, int>{};
  final routeSample = <String, TripEndpoints>{};
  for (final t in trips) {
    final d = t.trip.distanceM;
    distance += d;
    moving += t.trip.movingS > 0 ? t.trip.movingS : t.score.summary.movingTimeS;
    final night = t.trip.nightFraction ?? t.score.summary.nightFraction;
    nightWeighted += d * night.clamp(0, 1);
    final start = DateTime.fromMillisecondsSinceEpoch(t.trip.startedAt);
    if (start.weekday == DateTime.saturday ||
        start.weekday == DateTime.sunday) {
      weekend++;
    } else {
      weekday++;
    }
    final ends = input.endpoints[t.trip.id];
    if (ends == null) continue;
    final at = _placeAt(input.places, ends.endLat, ends.endLon);
    if (at != null) visits[at.label] = (visits[at.label] ?? 0) + 1;
    final key = [
      (ends.startLat / _routeGridDeg).round(),
      (ends.startLon / _routeGridDeg).round(),
      (ends.endLat / _routeGridDeg).round(),
      (ends.endLon / _routeGridDeg).round(),
    ].join(':');
    routes[key] = (routes[key] ?? 0) + 1;
    routeSample[key] ??= ends;
  }
  final topPlaces =
      visits.entries
          .map((e) => PlaceVisits(label: e.key, visits: e.value))
          .toList()
        ..sort((a, b) {
          final c = b.visits.compareTo(a.visits);
          return c != 0 ? c : a.label.compareTo(b.label);
        });
  GroundhogRoute? groundhog;
  String? bestKey;
  var bestCount = 1;
  for (final e in routes.entries) {
    if (e.value > bestCount) {
      bestCount = e.value;
      bestKey = e.key;
    }
  }
  if (bestKey != null) {
    final ends = routeSample[bestKey]!;
    groundhog = GroundhogRoute(
      count: bestCount,
      fromLabel: _placeAt(input.places, ends.startLat, ends.startLon)?.label,
      toLabel: _placeAt(input.places, ends.endLat, ends.endLon)?.label,
    );
  }
  return Habits(
    nightFraction: distance <= 0 ? 0 : (nightWeighted / distance).clamp(0, 1),
    weekdayTrips: weekday,
    weekendTrips: weekend,
    averageDistanceM: distance / trips.length,
    averageMovingS: moving / trips.length,
    topPlaces: topPlaces.take(3).toList(),
    groundhog: groundhog,
  );
}

RealityChecks _reality(List<ScoredTrip> trips, StatsInput input) {
  var over = 0.0;
  var saved = 0.0;
  var risk = 0.0;
  var harsh = 0;
  for (final t in trips) {
    over += t.score.summary.secondsOverLimit;
    saved += t.score.summary.timeSavedBySpeedingS;
    for (final e in t.score.events) {
      switch (e.kind) {
        case EventKind.harshAccel:
          harsh++;
        case EventKind.speeding:
          final limit = e.limitMps;
          final max = e.maxSpeedMps;
          final maxOver =
              (e.detail['maxOver'] as num?)?.toDouble() ??
              (limit != null && max != null ? max - limit : 0.0);
          if (e.severity.index >= Severity.major.index ||
              maxOver >= ticketRiskOverMps) {
            risk += e.durationS;
          }
        default:
          break;
      }
    }
  }
  return RealityChecks(
    secondsOverLimit: over,
    timeSavedS: saved,
    ticketRiskS: risk,
    harshAccelCount: harsh,
    moneyBurned: harsh * litresPerHarshAccel * input.fuelPricePerLitre,
  );
}

Social _social(List<ScoredTrip> trips, StatsInput input, StatsRange range) {
  final convoys = [
    for (final c in input.convoys)
      if (range.contains(c.joinedAt) ||
          (c.leftAt != null && range.contains(c.leftAt!)))
        c,
  ];
  if (convoys.isEmpty) return Social.empty;
  var distance = 0.0;
  final companions = <String, Companion>{};
  var dj = 0;
  for (final c in convoys) {
    // Twelve hours is the longest a one-day convoy is assumed to run when
    // the phone never recorded leaving it.
    final end =
        c.leftAt ?? c.joinedAt + const Duration(hours: 12).inMilliseconds;
    for (final t in trips) {
      if (t.trip.startedAt >= c.joinedAt && t.trip.startedAt <= end) {
        distance += t.trip.distanceM;
      }
    }
    for (final m in input.convoyMembers[c.convoyId] ?? const <ConvoyMember>[]) {
      if (m.userId == input.myUserId) continue;
      final prev = companions[m.userId];
      companions[m.userId] = Companion(
        userId: m.userId,
        name: m.name,
        convoys: (prev?.convoys ?? 0) + 1,
      );
    }
    dj += input.djTracksByConvoy[c.convoyId] ?? 0;
  }
  final top = companions.values.toList()
    ..sort((a, b) {
      final c = b.convoys.compareTo(a.convoys);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  return Social(
    convoysJoined: convoys.length,
    convoyDistanceM: distance,
    topCompanions: top.take(3).toList(),
    djTracks: dj,
  );
}

List<VehicleStatLine> _vehicles(
  List<ScoredTrip> trips,
  StatsInput input,
  _EconomyLookup econ,
) {
  final byVehicle = <String, List<ScoredTrip>>{};
  for (final t in trips) {
    final id = t.trip.vehicleId;
    if (id == null) continue;
    (byVehicle[id] ??= []).add(t);
  }
  final names = {for (final v in input.vehicles) v.id: v.name};
  final out = <VehicleStatLine>[];
  for (final e in byVehicle.entries) {
    var distance = 0.0;
    var litres = 0.0;
    var scoreSum = 0;
    var scored = 0;
    for (final t in e.value) {
      distance += t.trip.distanceM;
      litres += econ.litres(t);
      if (t.score.scored) {
        scored++;
        scoreSum += t.score.score;
      }
    }
    out.add(
      VehicleStatLine(
        vehicleId: e.key,
        name: names[e.key] ?? e.value.first.trip.vehicleLabel ?? 'Unknown car',
        trips: e.value.length,
        distanceM: distance,
        averageScore: scored == 0 ? null : scoreSum / scored,
        lPer100km: econ.measured(e.key),
        fuelLitres: litres,
      ),
    );
  }
  out.sort((a, b) {
    final c = b.trips.compareTo(a.trips);
    return c != 0 ? c : a.name.compareTo(b.name);
  });
  return out;
}
