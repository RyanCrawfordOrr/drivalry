import 'package:drift/drift.dart' show Value;
import 'package:drivalry/data/badges/badge_engine.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/garage/fuel_math.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/data/models/trip_score_view.dart';
import 'package:drivalry/data/repos/convoy_models.dart';
import 'package:drivalry/data/stats/stats_engine.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show haversine;
import 'package:flutter_test/flutter_test.dart';

/// A scored driver trip built in memory, no database.
ScoredTrip trip({
  required String id,
  required DateTime start,
  double distanceM = 10000,
  double movingS = 900,
  int score = 90,
  bool reckless = false,
  String? region = 'us-tn',
  String? vehicleId,
  double? nightFraction,
  double secondsOver = 0,
  double timeSaved = 0,
  int xp = 60,
  List<Map<String, dynamic>> events = const [],
}) {
  final startedAt = start.millisecondsSinceEpoch;
  final t = Trip(
    id: id,
    startedAt: startedAt,
    endedAt: startedAt + (movingS * 1000).round(),
    phase: TripPhase.scored.wire,
    distanceM: distanceM,
    movingS: movingS,
    passengerHint: false,
    passengerAnswered: true,
    crashCandidate: false,
    createdAt: startedAt,
    packRegion: region,
    vehicleId: vehicleId,
    nightFraction: nightFraction,
  ).copyWith(isPassenger: const Value(false));
  final s = TripScoreView.fromJson({
    'tripId': id,
    'scored': true,
    'score': score,
    'penalties': {'speed': 0, 'smoothness': 0, 'attention': 0, 'efficiency': 0},
    'flags': reckless ? ['reckless'] : [],
    'reckless': reckless,
    'xp': xp,
    'events': events,
    'observations': [],
    'summary': {
      'distanceM': distanceM,
      'movingTimeS': movingS,
      'totalTimeS': movingS + 60,
      'maxSpeed': 20,
      'avgMovingSpeed': 12,
      'secondsOverLimit': secondsOver,
      'secondsWithKnownLimit': movingS,
      'timeSavedBySpeedingS': timeSaved,
      'startT': startedAt,
      'endT': startedAt + (movingS * 1000).round(),
      'nightFraction': nightFraction ?? 0,
      'gpsQuality': 1,
    },
    'feedback': {
      'headline': {'tone': 'praise', 'text': 'Smooth.'},
      'lines': [],
    },
  });
  return ScoredTrip(t, s);
}

Map<String, dynamic> event(
  String kind, {
  String severity = 'minor',
  double durationS = 10,
  Map<String, dynamic> detail = const {},
}) => {
  'kind': kind,
  'severity': severity,
  'startT': 0,
  'endT': (durationS * 1000).round(),
  'durationS': durationS,
  'startIdx': 0,
  'endIdx': 1,
  'lat': 36.16,
  'lon': -86.78,
  'detail': detail,
};

Place place(String id, String kind, String label, double lat, double lon) =>
    Place(
      id: id,
      label: label,
      kind: kind,
      lat: lat,
      lon: lon,
      radiusM: 150,
      createdAt: 0,
    );

TripEndpoints ends(double aLat, double aLon, double bLat, double bLon) =>
    TripEndpoints(startLat: aLat, startLon: aLon, endLat: bLat, endLon: bLon);

const allTime = StatsRange(label: 'All time');
final now = DateTime(2026, 11, 3, 12);

/// Newest first, like the database stream.
List<ScoredTrip> newestFirst(List<ScoredTrip> trips) =>
    trips..sort((a, b) => b.trip.startedAt.compareTo(a.trip.startedAt));

void main() {
  group('windows', () {
    test('season is the calendar quarter, named by its months', () {
      final r = StatsRange.season(now);
      expect(r.label, 'Oct–Dec 2026');
      expect(r.start, DateTime(2026, 10));
      expect(r.end, DateTime(2027));
      expect(r.contains(DateTime(2026, 10).millisecondsSinceEpoch), isTrue);
      expect(r.contains(DateTime(2027).millisecondsSinceEpoch), isFalse);
      expect(
        r.contains(DateTime(2026, 9, 30, 23, 59).millisecondsSinceEpoch),
        isFalse,
      );
    });

    test('previous season and month', () {
      expect(StatsRange.previousSeason(now).label, 'Jul–Sep 2026');
      expect(
        StatsRange.previousSeason(DateTime(2026, 2)).label,
        'Oct–Dec 2025',
      );
      final m = StatsRange.month(now);
      expect(m.label, 'Nov 2026');
      expect(m.end, DateTime(2026, 12));
      expect(StatsRange.forWindow(StatsWindow.allTime, now).isAllTime, isTrue);
    });
  });

  group('empty and windowed input', () {
    test('no trips gives an empty, non-throwing result', () {
      final s = computeDriverStats(const StatsInput(trips: []), allTime);
      expect(s.isEmpty, isTrue);
      expect(s.totals.averageScore, isNull);
      expect(s.records.longestTrip, isNull);
      expect(s.geography.stateCodes, isEmpty);
      expect(s.habits.groundhog, isNull);
      expect(s.reality.timeSavedLine, isNull);
      expect(s.social.convoysJoined, 0);
      expect(s.vehicles, isEmpty);
    });

    test('trips outside the window are ignored', () {
      final input = StatsInput(
        trips: newestFirst([
          trip(id: 'a', start: DateTime(2026, 11, 2)),
          trip(id: 'b', start: DateTime(2026, 8, 2)),
        ]),
      );
      expect(computeDriverStats(input, StatsRange.month(now)).totals.trips, 1);
      expect(computeDriverStats(input, StatsRange.season(now)).totals.trips, 1);
      expect(computeDriverStats(input, allTime).totals.trips, 2);
    });
  });

  group('totals', () {
    test('sums distance, time, fuel and scores', () {
      final input = StatsInput(
        trips: newestFirst([
          trip(id: 'a', start: DateTime(2026, 11, 1), score: 90, xp: 60),
          trip(id: 'b', start: DateTime(2026, 11, 2), score: 70, xp: 20),
          trip(
            id: 'c',
            start: DateTime(2026, 11, 3),
            score: 95,
            reckless: false,
            xp: 80,
          ),
        ]),
      );
      final t = computeDriverStats(input, allTime).totals;
      expect(t.trips, 3);
      expect(t.distanceM, 30000);
      expect(t.movingS, 2700);
      expect(t.averageScore, closeTo(85, 1e-9));
      expect(t.bestScore, 95);
      expect(t.cleanTrips, 2);
      expect(t.xp, 160);
      // 30 km at the default 9.4 L/100 km.
      expect(t.fuelLitres, closeTo(2.82, 1e-9));
      expect(t.fuelCost, closeTo(2.82 * defaultFuelPricePerLitre, 1e-9));
      expect(t.co2Kg, closeTo(2.82 * co2KgPerLitre, 1e-9));
    });

    test('uses the measured economy of the car when fill-ups exist', () {
      FuelEntry fill(String id, int at, double odo, double litres) => FuelEntry(
        id: id,
        vehicleId: 'v1',
        at: at,
        odometerKm: odo,
        litres: litres,
        currency: 'USD',
        fullTank: true,
      );
      // 500 km on 40 L: 8 L/100 km.
      final stats = computeFuelStats([
        fill('f1', 1, 1000, 30),
        fill('f2', 2, 1500, 40),
      ]);
      final input = StatsInput(
        trips: [trip(id: 'a', start: DateTime(2026, 11, 1), vehicleId: 'v1')],
        fuelStats: {'v1': stats},
        fuelPricePerLitre: 2,
      );
      final s = computeDriverStats(input, allTime);
      expect(s.totals.fuelLitres, closeTo(0.8, 1e-9));
      expect(s.totals.fuelCost, closeTo(1.6, 1e-9));
      expect(s.vehicles.single.lPer100km, closeTo(8, 1e-9));
    });
  });

  group('records', () {
    test('longest trip, altitude, early and late starts, busiest day', () {
      final trips = newestFirst([
        trip(id: 'a', start: DateTime(2026, 11, 1, 7, 10), distanceM: 5000),
        trip(id: 'b', start: DateTime(2026, 11, 1, 23, 30), distanceM: 50000),
        trip(id: 'c', start: DateTime(2026, 11, 2, 1, 15), distanceM: 8000),
        trip(id: 'd', start: DateTime(2026, 11, 1, 12), distanceM: 1000),
      ]);
      final input = StatsInput(
        trips: trips,
        extents: {
          'a': const TripExtent(
            minLat: 36,
            maxLat: 36.1,
            minLon: -86.8,
            maxLon: -86.7,
            maxAltitudeM: 180,
          ),
          'b': const TripExtent(
            minLat: 36,
            maxLat: 36.1,
            minLon: -86.8,
            maxLon: -86.7,
            maxAltitudeM: 1240.5,
          ),
        },
      );
      final r = computeDriverStats(input, allTime).records;
      expect(r.longestTrip!.trip.id, 'b');
      expect(r.highestAltitudeM, 1240.5);
      expect(r.earliestStart, DateTime(2026, 11, 1, 7, 10));
      // 1:15 am ranks later than 11:30 pm.
      expect(r.latestStart, DateTime(2026, 11, 2, 1, 15));
      expect(r.mostTripsInDay, 3);
      expect(r.busiestDay, DateTime(2026, 11, 1));
    });

    test('longest and current clean streaks', () {
      final trips = newestFirst([
        trip(id: 'a', start: DateTime(2026, 11, 1), score: 90),
        trip(id: 'b', start: DateTime(2026, 11, 2), score: 85),
        trip(id: 'c', start: DateTime(2026, 11, 3), score: 85, reckless: true),
        trip(id: 'd', start: DateTime(2026, 11, 4), score: 91),
        trip(id: 'e', start: DateTime(2026, 11, 5), score: 60),
        trip(id: 'f', start: DateTime(2026, 11, 6), score: 88),
      ]);
      final r = computeDriverStats(StatsInput(trips: trips), allTime).records;
      expect(r.longestCleanStreak, 2);
      expect(r.currentCleanStreak, 1);
    });
  });

  group('geography', () {
    test('states visited come from pack regions, most trips first', () {
      final trips = newestFirst([
        trip(id: 'a', start: DateTime(2026, 11, 1), region: 'us-ky'),
        trip(id: 'b', start: DateTime(2026, 11, 2), region: 'us-tn'),
        trip(id: 'c', start: DateTime(2026, 11, 3), region: 'US-TN'),
        trip(id: 'd', start: DateTime(2026, 11, 4), region: 'gb'),
        trip(id: 'e', start: DateTime(2026, 11, 5), region: null),
      ]);
      final g = computeDriverStats(StatsInput(trips: trips), allTime).geography;
      expect(g.regions, ['us-tn', 'gb', 'us-ky']);
      expect(g.stateCodes, ['TN', 'KY']);
    });

    test('most driven road counts trips, not segments', () {
      final trips = newestFirst([
        trip(id: 'a', start: DateTime(2026, 11, 1)),
        trip(id: 'b', start: DateTime(2026, 11, 2)),
        trip(id: 'c', start: DateTime(2026, 11, 3)),
      ]);
      final g = computeDriverStats(
        StatsInput(
          trips: trips,
          roadsByTrip: {
            'a': {'Broadway', 'I-40'},
            'b': {'Broadway', 'Church Street'},
            'c': {'I-40', 'Broadway'},
          },
        ),
        allTime,
      ).geography;
      expect(g.mostDrivenRoad, 'Broadway');
      expect(g.mostDrivenRoadTrips, 3);
    });

    test(
      'home radius holds 90 % of distance; farthest point is the far trip',
      () {
        final home = place('h', 'home', 'Home', 36.16, -86.78);
        // Trip a stays near home (about 5 km), trip b goes far (about 50 km).
        final trips = newestFirst([
          trip(id: 'a', start: DateTime(2026, 11, 1), distanceM: 10000),
          trip(id: 'b', start: DateTime(2026, 11, 2), distanceM: 1000),
        ]);
        final input = StatsInput(
          trips: trips,
          places: [home],
          extents: {
            'a': const TripExtent(
              minLat: 36.16,
              maxLat: 36.2,
              minLon: -86.78,
              maxLon: -86.75,
            ),
            'b': const TripExtent(
              minLat: 36.16,
              maxLat: 36.6,
              minLon: -86.78,
              maxLon: -86.7,
            ),
          },
        );
        final g = computeDriverStats(input, allTime).geography;
        expect(g.hasHome, isTrue);
        expect(
          g.homeRadiusM,
          closeTo(haversine(36.16, -86.78, 36.2, -86.75), 1),
        );
        expect(
          g.farthestFromHomeM,
          closeTo(haversine(36.16, -86.78, 36.6, -86.7), 1),
        );
      },
    );

    test('without a Home place the home figures are null', () {
      final g = computeDriverStats(
        StatsInput(
          trips: [trip(id: 'a', start: DateTime(2026, 11, 1))],
        ),
        allTime,
      ).geography;
      expect(g.hasHome, isFalse);
      expect(g.homeRadiusM, isNull);
      expect(g.farthestFromHomeM, isNull);
    });
  });

  group('habits', () {
    final home = place('h', 'home', 'Home', 36.16, -86.78);
    final work = place('w', 'work', 'Work', 36.20, -86.70);

    test('night share is distance-weighted; weekend split counts trips', () {
      final trips = newestFirst([
        // Sunday, all at night, long.
        trip(
          id: 'a',
          start: DateTime(2026, 11, 1, 22),
          distanceM: 30000,
          nightFraction: 1,
        ),
        // Monday, daytime, short.
        trip(
          id: 'b',
          start: DateTime(2026, 11, 2, 9),
          distanceM: 10000,
          nightFraction: 0,
        ),
        // Saturday.
        trip(
          id: 'c',
          start: DateTime(2026, 11, 7, 10),
          distanceM: 0,
          nightFraction: 0,
        ),
      ]);
      final h = computeDriverStats(StatsInput(trips: trips), allTime).habits;
      expect(h.nightFraction, closeTo(0.75, 1e-9));
      expect(h.nightPercent, 75);
      expect(h.weekendTrips, 2);
      expect(h.weekdayTrips, 1);
      expect(h.weekendPercent, 67);
      expect(h.averageDistanceM, closeTo(40000 / 3, 1e-6));
    });

    test(
      'Groundhog Route is the most repeated start→end pair, labelled by places',
      () {
        final trips = newestFirst([
          for (var i = 0; i < 3; i++)
            trip(id: 'commute$i', start: DateTime(2026, 11, 2 + i, 8)),
          trip(id: 'other', start: DateTime(2026, 11, 6, 8)),
        ]);
        final h = computeDriverStats(
          StatsInput(
            trips: trips,
            places: [home, work],
            endpoints: {
              // Small GPS jitter at each end still counts as the same route.
              'commute0': ends(36.1601, -86.7801, 36.2002, -86.7001),
              'commute1': ends(36.1599, -86.7799, 36.1999, -86.6999),
              'commute2': ends(36.1600, -86.7802, 36.2001, -86.7002),
              'other': ends(36.16, -86.78, 35.9, -86.5),
            },
          ),
          allTime,
        ).habits;
        expect(h.groundhog, isNotNull);
        expect(h.groundhog!.count, 3);
        expect(h.groundhog!.fromLabel, 'Home');
        expect(h.groundhog!.toLabel, 'Work');
        expect(h.groundhog!.label, 'Home → Work');
        expect(h.topPlaces.single.label, 'Work');
        expect(h.topPlaces.single.visits, 3);
      },
    );

    test(
      'no repeated route gives no Groundhog; unknown ends have no labels',
      () {
        final trips = newestFirst([
          trip(id: 'a', start: DateTime(2026, 11, 2)),
          trip(id: 'b', start: DateTime(2026, 11, 3)),
          trip(id: 'c', start: DateTime(2026, 11, 4)),
        ]);
        final none = computeDriverStats(
          StatsInput(
            trips: trips,
            endpoints: {
              'a': ends(36.1, -86.1, 36.2, -86.2),
              'b': ends(36.3, -86.3, 36.4, -86.4),
            },
          ),
          allTime,
        ).habits;
        expect(none.groundhog, isNull);
        final unlabelled = computeDriverStats(
          StatsInput(
            trips: trips,
            endpoints: {
              'a': ends(36.1, -86.1, 36.2, -86.2),
              'b': ends(36.1, -86.1, 36.2, -86.2),
            },
          ),
          allTime,
        ).habits.groundhog!;
        expect(unlabelled.count, 2);
        expect(unlabelled.label, 'your usual route');
      },
    );
  });

  group('reality checks', () {
    test('time saved by speeding reads like the spec line', () {
      final trips = newestFirst([
        trip(
          id: 'a',
          start: DateTime(2026, 11, 1),
          secondsOver: 10000,
          timeSaved: 400,
        ),
        trip(
          id: 'b',
          start: DateTime(2026, 11, 2),
          secondsOver: 5120,
          timeSaved: 260,
        ),
      ]);
      final rc = computeDriverStats(StatsInput(trips: trips), allTime).reality;
      expect(rc.secondsOverLimit, 15120);
      expect(rc.timeSavedS, 660);
      expect(
        rc.timeSavedLine,
        'You drove over the limit for 4.2 h. It saved you 11 minutes.',
      );
      expect(RealityChecks.formatHoursOver(900), '15 min');
      expect(RealityChecks.formatHoursOver(40000), '11 h');
    });

    test('under a minute over the limit has no line', () {
      final rc = computeDriverStats(
        StatsInput(
          trips: [trip(id: 'a', start: DateTime(2026, 11, 1), secondsOver: 30)],
        ),
        allTime,
      ).reality;
      expect(rc.timeSavedLine, isNull);
    });

    test('ticket risk and money burned by hard acceleration', () {
      final t = trip(
        id: 'a',
        start: DateTime(2026, 11, 1),
        events: [
          event('speeding', severity: 'major', durationS: 30),
          // Minor severity but 5 m/s over: still ticket territory.
          event(
            'speeding',
            durationS: 20,
            detail: {'limit': 20, 'maxSpeed': 25},
          ),
          // Minor and barely over: ignored.
          event(
            'speeding',
            durationS: 40,
            detail: {'limit': 20, 'maxSpeed': 21},
          ),
          event('harsh_accel'),
          event('harsh_accel'),
          event('harsh_brake'),
        ],
      );
      final rc = computeDriverStats(
        StatsInput(trips: [t], fuelPricePerLitre: 1),
        allTime,
      ).reality;
      expect(rc.ticketRiskS, 50);
      expect(rc.harshAccelCount, 2);
      expect(rc.moneyBurned, closeTo(2 * litresPerHarshAccel, 1e-9));
    });
  });

  group('social', () {
    ConvoyLocalData convoy(String id, DateTime joined, {DateTime? left}) =>
        ConvoyLocalData(
          convoyId: id,
          role: 'member',
          joinedAt: joined.millisecondsSinceEpoch,
          leftAt: left?.millisecondsSinceEpoch,
          updatedAt: 0,
        );
    ConvoyMember member(String id, String name) => ConvoyMember(
      userId: id,
      handle: id,
      displayName: name,
      role: 'member',
      joinedAt: DateTime(2026),
    );

    test('convoys joined, convoy distance, companions and DJ score', () {
      final trips = newestFirst([
        // During convoy c1.
        trip(id: 'a', start: DateTime(2026, 10, 10, 9), distanceM: 40000),
        trip(id: 'b', start: DateTime(2026, 10, 10, 14), distanceM: 30000),
        // After c1 ended.
        trip(id: 'c', start: DateTime(2026, 10, 11, 9), distanceM: 5000),
        // During c2, which never recorded a leave (12 h assumed).
        trip(id: 'd', start: DateTime(2026, 10, 20, 15), distanceM: 20000),
        trip(id: 'e', start: DateTime(2026, 10, 21, 9), distanceM: 9000),
      ]);
      final input = StatsInput(
        trips: trips,
        myUserId: 'me',
        convoys: [
          convoy(
            'c1',
            DateTime(2026, 10, 10, 8),
            left: DateTime(2026, 10, 10, 18),
          ),
          convoy('c2', DateTime(2026, 10, 20, 8)),
          convoy('old', DateTime(2026, 6, 1)),
        ],
        convoyMembers: {
          'c1': [member('me', 'Me'), member('u1', 'Alex'), member('u2', 'Sam')],
          'c2': [member('me', 'Me'), member('u1', 'Alex')],
          'old': [member('me', 'Me'), member('u3', 'Jo')],
        },
        djTracksByConvoy: {'c1': 7, 'old': 3},
      );
      final so = computeDriverStats(input, StatsRange.season(now)).social;
      expect(so.convoysJoined, 2);
      expect(so.convoyDistanceM, 90000);
      expect(so.topCompanions.map((c) => c.name), ['Alex', 'Sam']);
      expect(so.topCompanions.first.convoys, 2);
      expect(so.djTracks, 7);
    });
  });

  group('vehicles', () {
    test('per-car trips, score and economy; unknown cars keep their label', () {
      final trips = newestFirst([
        trip(
          id: 'a',
          start: DateTime(2026, 11, 1),
          vehicleId: 'truck',
          score: 60,
        ),
        trip(
          id: 'b',
          start: DateTime(2026, 11, 2),
          vehicleId: 'truck',
          score: 70,
        ),
        trip(
          id: 'c',
          start: DateTime(2026, 11, 3),
          vehicleId: 'hatch',
          score: 95,
        ),
        trip(id: 'd', start: DateTime(2026, 11, 4), vehicleId: null, score: 50),
      ]);
      final input = StatsInput(
        trips: trips,
        vehicles: [
          const Vehicle(
            id: 'truck',
            name: 'F-150',
            bluetoothNames: '[]',
            neverTrack: false,
            createdAt: 0,
          ),
        ],
      );
      final v = computeDriverStats(input, allTime).vehicles;
      expect(v, hasLength(2));
      expect(v.first.name, 'F-150');
      expect(v.first.trips, 2);
      expect(v.first.averageScore, 65);
      expect(v.first.lPer100km, isNull);
      expect(
        v.first.fuelLitres,
        closeTo(20 * defaultLitresPer100km / 100, 1e-9),
      );
      expect(v.last.vehicleId, 'hatch');
      expect(v.last.name, 'Unknown car');
    });
  });
}
