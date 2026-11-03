// Layout audit for the Drive area (docs/12 §2): every screen and state the
// tab can show, rendered at real phone sizes with seeded data, checked for
// overflow, overlapping text, text past the screen edge and empty bands.
//
//   DRIVALRY_LAYOUT=1 flutter test test/layout/layout_drive_test.dart
//
// PNGs land in test/layout/out/<state>_<size>.png (gitignored). Without
// DRIVALRY_LAYOUT the suite skips: it needs the Flutter font cache.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/models/trip_phase.dart';
import 'package:drivalry/data/repos/circles_repo.dart' show Circle;
import 'package:drivalry/data/repos/circles_sync.dart';
import 'package:drivalry/data/repos/friends_sync.dart';
import 'package:drivalry/data/repos/presence_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/cues/live_limit.dart';
import 'package:drivalry/features/drive/drive_screen.dart';
import 'package:drivalry/features/drive/first_run_flow.dart';
import 'package:drivalry/features/drive/friends_map/friend_marker.dart';
import 'package:drivalry/features/drive/friends_map/friends_map.dart';
import 'package:drivalry/features/drive/packs_screen.dart';
import 'package:drivalry/features/drive/parking/parking_screen.dart';
import 'package:drivalry/features/drive/simulate_sheet.dart';
import 'package:drivalry/features/drive/trip_detail_screen.dart';
import 'package:drivalry/features/drive/widgets/drive_status_capsule.dart';
import 'package:drivalry/features/profile/profile_model.dart';
import 'package:drivalry/features/profile/profile_repo.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/weather.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart'
    show RoadClass, RoadSegment;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show MatrixUtils, RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../art/art_harness.dart';
import '../support/fake_tracking_port.dart';
import '../support/scored_trips.dart';
import '../support/sqlite_support.dart';
import '../support/widget_support.dart';
import 'layout_audit.dart';

/// The owner's test phone: 448 x 997 logical pixels, a 66 px status bar and
/// 24 px gesture navigation. Added to the two standard sizes.
const _ownerPhone = PhoneSize('owner-448', 448, 997, top: 66, bottom: 24);
const _sizes = [...phoneSizes, _ownerPhone];

const _granted = TrackingPermissions(
  location: LocationPermission.always,
  preciseLocation: true,
  motion: SimplePermission.granted,
  notifications: SimplePermission.granted,
  bluetooth: SimplePermission.granted,
);

/// Location while in use only: enough to record by hand, not to auto-detect.
const _partial = TrackingPermissions(
  location: LocationPermission.whileInUse,
  preciseLocation: true,
  motion: SimplePermission.granted,
);

const _detailTrip = 'audit-roast';

/// One database and one fake plugin per shot, closed after it.
class _Fixture {
  final AppDatabase db = memoryDatabase();
  FakeTrackingPort port = FakeTrackingPort();

  Future<void> dispose() async {
    await port.dispose();
    await db.close();
  }
}

/// One screen state to render.
class _Shot {
  const _Shot(this.id, this.build, {this.prepare, this.light = false});

  final String id;
  final Future<Widget> Function(_Fixture f) build;

  /// Runs after the first frames: taps, scrolls, opens sheets.
  final Future<void> Function(WidgetTester tester)? prepare;
  final bool light;

  /// Fake time pumped before capture, so streams and animations settle.
  static const settle = Duration(seconds: 3);
}

Widget _app(
  Widget home, {
  List<Override> overrides = const [],
  bool light = false,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: artTheme(Brightness.light),
    darkTheme: artTheme(),
    themeMode: light ? ThemeMode.light : ThemeMode.dark,
    debugShowCheckedModeBanner: false,
    home: home,
  ),
);

List<Override> _base(_Fixture f) => [
  databaseProvider.overrideWithValue(f.db),
  trackingPortProvider.overrideWithValue(f.port),
  deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
  weatherClientProvider.overrideWithValue(const NoWeather()),
];

/// The Drive tab as the store scene builds it: signed in, a stand-in map,
/// the developer button present (debug builds have it), two requests waiting.
List<Override> _drive(
  _Fixture f, {
  List<PresenceRow> presence = const [],
  bool circles = false,
  LiveLimitState? limit,
}) => [
  ..._base(f),
  currentUserIdProvider.overrideWithValue('me'),
  friendsMapSurfaceProvider.overrideWithValue((_) => const _MapStandIn()),
  visiblePresenceProvider.overrideWith((_) => Stream.value(presence)),
  myCirclesProvider.overrideWith(
    () => _FixedCircles(circles ? _circles() : const []),
  ),
  circleMembershipProvider.overrideWithValue(
    circles
        ? const {
            'c-carpool': {'me', 'u-sam', 'u-priya'},
            'c-family': {'me', 'u-jordan'},
          }
        : const {},
  ),
  if (limit != null) liveLimitProvider.overrideWith((_) => Stream.value(limit)),
  myProfileProvider.overrideWith(
    (_) => Stream.value(
      const Profile(id: 'me', handle: 'ryan', displayName: 'Ryan Orr'),
    ),
  ),
  pendingRequestCountProvider.overrideWithValue(2),
  devToolsVisibleProvider.overrideWithValue(true),
];

List<Circle> _circles() {
  final utc = DateTime.now().toUtc();
  return [
    Circle(
      id: 'c-carpool',
      name: 'Carpool',
      createdBy: 'me',
      inviteCode: 'CARPOOL1',
      createdAt: utc,
      memberCount: 3,
    ),
    Circle(
      id: 'c-family',
      name: 'Family',
      createdBy: 'u-jordan',
      inviteCode: 'FAMILY01',
      createdAt: utc,
      memberCount: 2,
    ),
  ];
}

List<PresenceRow> _presence() {
  final utc = DateTime.now().toUtc();
  return [
    PresenceRow(
      userId: 'u-sam',
      handle: 'sam',
      displayName: 'Sam',
      lat: 36.165,
      lon: -86.78,
      driving: true,
      speed: 14.2,
      battery: 0.71,
      updatedAt: utc.subtract(const Duration(seconds: 20)),
    ),
    PresenceRow(
      userId: 'u-priya',
      handle: 'priya',
      displayName: 'Priya',
      lat: 36.15,
      lon: -86.80,
      driving: false,
      battery: 0.54,
      updatedAt: utc.subtract(const Duration(minutes: 12)),
    ),
  ];
}

// ---------------------------------------------------------------- seeding --

/// Three scored, answered trips: the newest is the "Last trip" hero.
Future<void> _seedTrips(AppDatabase db) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final trips = [
    (
      'audit-92',
      today.add(const Duration(hours: 8, minutes: 5)),
      92,
      70,
      11300.0,
      1380.0,
      'Smooth from the driveway to the parking lot. Textbook.',
    ),
    (
      'audit-78',
      yesterday.add(const Duration(hours: 18, minutes: 30)),
      78,
      48,
      5600.0,
      780.0,
      'Mostly smooth. One sharp corner on 12th Ave cost you.',
    ),
    (
      'audit-64',
      yesterday.add(const Duration(hours: 7, minutes: 50)),
      64,
      30,
      18300.0,
      1500.0,
      'Three hard brakes in 11 miles. Give the car in front some room.',
    ),
  ];
  for (final (id, start, score, xp, dist, moving, headline) in trips) {
    await seedScoredTrip(
      db,
      id: id,
      startedAt: start.millisecondsSinceEpoch,
      score: score,
      xp: xp,
      distanceM: dist,
      movingS: moving,
      packRegion: 'us-tn',
      headline: headline,
    );
    await db.updateTrip(
      id,
      TripsCompanion(
        passengerAnswered: const Value(true),
        limitCoverage: Value(score >= 90 ? 0.94 : 0.88),
      ),
    );
  }
}

/// A trip in progress: fixes stored, no `trips` row, so the recording shows
/// in the live block and not in the list.
Future<TrackingState> _seedLive(AppDatabase db) async {
  const liveId = 'audit-live';
  final now = DateTime.now();
  final tripStart = now.subtract(const Duration(minutes: 14));
  final fixes = <SamplesCompanion>[];
  const steps = 14;
  for (var i = 0; i <= steps; i++) {
    fixes.add(
      SamplesCompanion.insert(
        tripId: liveId,
        t: tripStart.add(Duration(minutes: i)).millisecondsSinceEpoch,
        lat: 36.10 + 0.1165 * i / steps,
        lon: -86.80 + 0.004 * (i % 3),
        accuracy: 5,
        speed: Value(i == steps ? 20.1168 : 15.0 + (i % 5) * 1.6),
      ),
    );
  }
  await db.insertFixBatch(liveId, tripStart.millisecondsSinceEpoch, fixes);
  return TrackingState(
    phase: TrackingPhase.active,
    tripId: liveId,
    tripStartedAt: tripStart.millisecondsSinceEpoch,
    permissions: _granted,
  );
}

LiveLimitState _liveLimit() {
  final now = DateTime.now().millisecondsSinceEpoch;
  return LiveLimitState(
    tripId: 'audit-live',
    limitMps: 20.1168,
    posted: 45,
    unitLabel: 'mph',
    roadName: 'Harding Pike',
    confidence: 0.96,
    speedMps: 20.1168,
    sinceMs: now - 90_000,
    updatedAt: now,
  );
}

/// The newest trip's parking spot, with a road name from its own segments
/// so nothing is looked up online.
Future<void> _seedParking(AppDatabase db) async {
  final parkedAt = DateTime.now().subtract(const Duration(minutes: 12));
  await db.replaceSegments('audit-92', const [
    RoadSegment(
      fromIdx: 0,
      toIdx: 400,
      speedLimit: 15.6464,
      confidence: 0.9,
      roadClass: RoadClass.residential,
      name: 'Elm St',
      wayId: 'w-elm',
    ),
  ]);
  await db.insertParkingSpot(
    ParkingSpotsCompanion.insert(
      tripId: 'audit-92',
      lat: 36.1627,
      lon: -86.7816,
      accuracy: 12,
      parkedAt: parkedAt.millisecondsSinceEpoch,
      note: const Value('Level 3, near the lift'),
    ),
  );
}

Future<void> _seedPack(AppDatabase db) => db.upsertPack(
  PacksCompanion.insert(
    region: 'us-tn',
    name: 'Tennessee',
    osmTimestamp: '2026-10-01T00:00:00Z',
    path: 'us-tn.pack',
    sha256: 'audit',
    bytes: 48_300_000,
    wayCount: 412_000,
    bboxMinLat: 34.98,
    bboxMinLon: -90.31,
    bboxMaxLat: 36.68,
    bboxMaxLon: -81.65,
    installedAt: DateTime.now().millisecondsSinceEpoch,
  ),
);

/// The roast trip from the store scene (score 58, one speeding and one phone
/// episode), with a matched road so the flag sheet opens, and the route
/// samples when [route] is set.
Future<void> _seedDetailTrip(AppDatabase db, {required bool route}) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, 17, 42);
  final startT = start.millisecondsSinceEpoch;
  const movingS = 1380.0;
  const totalS = 1500.0;
  const distanceM = 14800.0;
  final endT = startT + (totalS * 1000).round();
  const limit35 = 15.6464;
  const speed48 = 21.4603;
  const speed38 = 16.9926;

  await db.ensureTrip(
    TripsCompanion.insert(
      id: _detailTrip,
      startedAt: startT,
      endedAt: Value(endT),
      phase: TripPhase.scored.wire,
      endReason: const Value('stationary'),
      triggerKind: const Value('activity'),
      createdAt: startT,
      isPassenger: const Value(false),
      passengerAnswered: const Value(true),
      distanceM: const Value(distanceM),
      movingS: const Value(movingS),
      packRegion: const Value('us-tn'),
      packVersion: const Value('2026-10-01'),
      limitCoverage: const Value(0.82),
      nightFraction: const Value(0.3),
      weather: const Value('Rain'),
      vehicleLabel: const Value('Civic'),
    ),
  );
  await db.replaceSegments(_detailTrip, const [
    RoadSegment(
      fromIdx: 0,
      toIdx: 2000,
      speedLimit: limit35,
      confidence: 0.9,
      roadClass: RoadClass.primary,
      name: 'Harding Pike',
      wayId: 'w-harding',
    ),
  ]);
  if (route) {
    final fixes = <SamplesCompanion>[];
    const n = 60;
    for (var i = 0; i < n; i++) {
      final f = i / (n - 1);
      fixes.add(
        SamplesCompanion.insert(
          tripId: _detailTrip,
          t: startT + i * 25_000,
          lat: 36.1335 - 0.03 * f + 0.004 * math.sin(f * 9),
          lon: -86.8460 - 0.05 * f,
          accuracy: 5,
          speed: Value(14 + 4 * math.sin(f * 7)),
        ),
      );
    }
    await db.insertFixBatch(_detailTrip, startT, fixes);
  }

  final speedingStart = startT + 9 * 60_000;
  final phoneStart = startT + 15 * 60_000;
  final events = <Map<String, dynamic>>[
    {
      'kind': 'speeding',
      'severity': 'moderate',
      'startT': speedingStart,
      'endT': speedingStart + 74_000,
      'durationS': 74,
      'startIdx': 540,
      'endIdx': 614,
      'lat': 36.1335,
      'lon': -86.8460,
      'detail': {
        'kind': 'speeding',
        'limit': limit35,
        'maxSpeed': speed48,
        'avgOver': 4.1,
        'maxOver': speed48 - limit35,
        'roadName': 'Harding Pike',
        'roadClass': 'primary',
        'timeSavedS': 11,
      },
    },
    {
      'kind': 'phone_handling',
      'severity': 'moderate',
      'startT': phoneStart,
      'endT': phoneStart + 23_000,
      'durationS': 23,
      'startIdx': 900,
      'endIdx': 923,
      'lat': 36.1190,
      'lon': -86.8695,
      'detail': {
        'kind': 'phone_handling',
        'interactions': 2,
        'maxSpeed': speed38,
        'kinds': ['unlock', 'touch'],
      },
    },
  ];
  const headline = 'Two phone grabs and 48 in a 35. The roast writes itself.';
  final json = {
    'tripId': _detailTrip,
    'scored': true,
    'score': 58,
    'penalties': {
      'speed': 24.0,
      'smoothness': 0.0,
      'attention': 18.0,
      'efficiency': 0.0,
    },
    'flags': <String>[],
    'reckless': false,
    'xp': 32,
    'events': events,
    'observations': <Map<String, dynamic>>[],
    'summary': {
      'distanceM': distanceM,
      'movingTimeS': movingS,
      'totalTimeS': totalS,
      'maxSpeed': speed48,
      'avgMovingSpeed': 10.72,
      'secondsOverLimit': 74,
      'secondsWithKnownLimit': 1132,
      'timeSavedBySpeedingS': 11,
      'startT': startT,
      'endT': endT,
      'nightFraction': 0.3,
      'gpsQuality': 0.96,
    },
    'feedback': {
      'headline': {'tone': 'roast', 'text': headline},
      'lines': [
        {
          'tone': 'roast',
          'text': '48 in a 35 on Harding Pike. All that for 11 seconds.',
          'eventIndex': 0,
        },
      ],
    },
  };
  await db.upsertScore(
    TripScoresCompanion.insert(
      tripId: _detailTrip,
      scoreJson: jsonEncode(json),
      score: const Value(58),
      xp: 32,
      reckless: false,
      scored: true,
      roastText: const Value(headline),
      scoredAt: endT + 2_000,
    ),
  );
}

// ------------------------------------------------------------------ hosts --

/// A bare page whose context and ref the `prepare` step uses to open a sheet
/// or the celebration on top of it.
BuildContext? _hostContext;
WidgetRef? _hostRef;

Widget _host() => Scaffold(
  body: Consumer(
    builder: (ctx, ref, _) {
      _hostContext = ctx;
      _hostRef = ref;
      return const SizedBox.expand();
    },
  ),
);

Future<void> _settleSheet(WidgetTester tester) =>
    pumpFor(tester, const Duration(milliseconds: 800));

Widget _firstRun({
  TrackingPermissions permissions = const TrackingPermissions(),
}) => FirstRunFlow(
  permissions: permissions,
  onRequest: () async => _partial,
  onOpenSettings: () {},
  onDone: () {},
);

// ------------------------------------------------------------------ shots --

final List<_Shot> _shots = [
  // Drive home, idle, three trips, friends on the map, circle chips.
  for (final light in [false, true])
    _Shot(light ? 'drive-idle-trips-light' : 'drive-idle-trips', (f) async {
      await _seedTrips(f.db);
      f.port = FakeTrackingPort(
        state: const TrackingState(permissions: _granted),
      );
      return _app(
        const DriveScreen(),
        overrides: _drive(f, presence: _presence(), circles: true),
        light: light,
      );
    }, light: light),
  // Drive home, idle, nothing recorded yet, nobody sharing.
  _Shot('drive-idle-empty', (f) async {
    f.port = FakeTrackingPort(
      state: const TrackingState(permissions: _granted),
    );
    return _app(const DriveScreen(), overrides: _drive(f, circles: true));
  }),
  // Recording: the speed capsule, the live block, the last trip under it.
  _Shot('drive-recording', (f) async {
    await _seedTrips(f.db);
    f.port = FakeTrackingPort(state: await _seedLive(f.db));
    return _app(
      const DriveScreen(),
      overrides: _drive(
        f,
        presence: _presence(),
        circles: true,
        limit: _liveLimit(),
      ),
    );
  }),
  // Permissions partly granted with trips: the one auto-detect tile.
  _Shot('drive-setup', (f) async {
    await _seedTrips(f.db);
    f.port = FakeTrackingPort(
      state: const TrackingState(permissions: _partial),
    );
    return _app(const DriveScreen(), overrides: _drive(f, circles: true));
  }),
  // "Almost there": the OS said no again, so the sheet points at Settings.
  _Shot(
    'drive-almost-there',
    (f) async {
      await _seedTrips(f.db);
      f.port = FakeTrackingPort(
        state: const TrackingState(permissions: _partial),
      )..permissionsOnRequest = _partial;
      return _app(const DriveScreen(), overrides: _drive(f));
    },
    prepare: (tester) async {
      await tester.tap(find.byKey(const Key('auto-detect-tile')));
      await _settleSheet(tester);
    },
  ),
  // The capsule's sheet.
  _Shot(
    'drive-detect-sheet',
    (f) async {
      await _seedTrips(f.db);
      f.port = FakeTrackingPort(
        state: const TrackingState(permissions: _granted),
      );
      return _app(const DriveScreen(), overrides: _drive(f, circles: true));
    },
    prepare: (tester) async {
      await tester.tap(find.byType(DriveStatusCapsule));
      await _settleSheet(tester);
    },
  ),
  // Long-press on the last trip.
  _Shot(
    'drive-trip-actions',
    (f) async {
      await _seedTrips(f.db);
      f.port = FakeTrackingPort(
        state: const TrackingState(permissions: _granted),
      );
      return _app(const DriveScreen(), overrides: _drive(f, circles: true));
    },
    prepare: (tester) async {
      await tester.longPress(
        find.text('Smooth from the driveway to the parking lot. Textbook.'),
      );
      await _settleSheet(tester);
    },
  ),
  // Parked: the parking tile above the last trip.
  _Shot('drive-parking-card', (f) async {
    await _seedTrips(f.db);
    await _seedParking(f.db);
    f.port = FakeTrackingPort(
      state: const TrackingState(permissions: _granted),
    );
    return _app(const DriveScreen(), overrides: _drive(f, circles: true));
  }),
  // First run, three pages.
  _Shot('first-run-1', (f) async => _app(_firstRun())),
  _Shot(
    'first-run-2',
    (f) async => _app(_firstRun()),
    prepare: (tester) async {
      await tester.tap(find.text('Next'));
      await _settleSheet(tester);
    },
  ),
  _Shot(
    'first-run-3',
    (f) async => _app(_firstRun()),
    prepare: (tester) async {
      await tester.tap(find.text('Next'));
      await _settleSheet(tester);
      // The fake grants location only, so the flow moves on to motion.
      await tester.tap(find.text('Allow'));
      await _settleSheet(tester);
    },
  ),
  // Trip detail with a route, initial scroll position; light too.
  for (final light in [false, true])
    _Shot(light ? 'trip-detail-route-light' : 'trip-detail-route', (f) async {
      await _seedDetailTrip(f.db, route: true);
      return _app(
        const TripDetailScreen(tripId: _detailTrip),
        overrides: [
          ..._base(f),
          tripMapSurfaceProvider.overrideWithValue(
            (_) => const _RouteStandIn(),
          ),
        ],
        light: light,
      );
    }, light: light),
  // Trip detail without a route.
  _Shot('trip-detail-noroute', (f) async {
    await _seedDetailTrip(f.db, route: false);
    return _app(
      const TripDetailScreen(tripId: _detailTrip),
      overrides: _base(f),
    );
  }),
  // Trip detail scrolled to the stats and the timeline.
  _Shot(
    'trip-detail-scrolled',
    (f) async {
      await _seedDetailTrip(f.db, route: true);
      return _app(
        const TripDetailScreen(tripId: _detailTrip),
        overrides: [
          ..._base(f),
          tripMapSurfaceProvider.overrideWithValue(
            (_) => const _RouteStandIn(),
          ),
        ],
      );
    },
    prepare: (tester) async {
      // Sliver children build lazily: scroll until the section exists.
      await tester.scrollUntilVisible(
        find.text('WHAT HAPPENED'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFor(tester, const Duration(milliseconds: 400));
    },
  ),
  // "Limit is wrong here" from the speeding row.
  _Shot(
    'trip-flag-sheet',
    (f) async {
      await _seedDetailTrip(f.db, route: false);
      return _app(
        const TripDetailScreen(tripId: _detailTrip),
        overrides: _base(f),
      );
    },
    prepare: (tester) async {
      final flag = find.byIcon(Icons.flag_outlined);
      await tester.scrollUntilVisible(
        flag,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFor(tester, const Duration(milliseconds: 300));
      await tester.tap(flag);
      await _settleSheet(tester);
    },
  ),
  // Where I parked.
  _Shot('parking-screen', (f) async {
    await _seedTrips(f.db);
    await _seedParking(f.db);
    return _app(const ParkingScreen(), overrides: _base(f));
  }),
  // Speed-limit packs with one installed.
  _Shot('packs-screen', (f) async {
    await _seedPack(f.db);
    return _app(const PacksScreen(), overrides: _base(f));
  }),
  // Developer: simulate a drive, with a pack to route from.
  _Shot(
    'simulate-sheet',
    (f) async {
      await _seedPack(f.db);
      return _app(_host(), overrides: _base(f));
    },
    prepare: (tester) async {
      unawaited(showSimulateSheet(_hostContext!, _hostRef!));
      await _settleSheet(tester);
    },
  ),
  // Trip scored: confetti with badges, and the roast stamp.
  _Shot(
    'celebration-92',
    (f) async => _app(_host(), overrides: _base(f)),
    prepare: (tester) async {
      unawaited(
        showCelebration(
          _hostContext!,
          title: 'Trip scored',
          score: 92,
          verdict: 'Smooth from the driveway to the parking lot. Textbook.',
          xp: 70,
          badges: const ['Flawless', 'Night owl', 'Ten in a row'],
          onShare: () {},
        ),
      );
      await pumpFor(tester, const Duration(milliseconds: 1800));
    },
  ),
  _Shot(
    'celebration-35',
    (f) async => _app(_host(), overrides: _base(f)),
    prepare: (tester) async {
      unawaited(
        showCelebration(
          _hostContext!,
          title: 'Trip scored',
          score: 35,
          verdict:
              'Three hard brakes and a phone grab in four miles. '
              'Rough one.',
          xp: 12,
          onShare: () {},
        ),
      );
      await pumpFor(tester, const Duration(milliseconds: 1800));
    },
  ),
  // A friend's sheet from the map.
  _Shot(
    'friend-sheet',
    (f) async => _app(_host(), overrides: _base(f)),
    prepare: (tester) async {
      final marker = FriendMarker(_presence().first);
      unawaited(
        showDrivalrySheet<void>(
          _hostContext!,
          builder: (_) => FriendSheet(marker: marker),
        ),
      );
      await _settleSheet(tester);
    },
  ),
];

void main() {
  setUpAll(() async {
    if (layoutShots) await loadArtFonts();
  });
  final sqliteSkip = skipWithoutSqlite();
  for (final shot in _shots) {
    for (final size in _sizes) {
      testWidgets(
        '${shot.id} lays out on $size',
        (tester) async {
          final f = _Fixture();
          try {
            final app = await shot.build(f);
            final report = await auditLayout(
              tester,
              name: shot.id,
              app: app,
              size: size,
              settle: _Shot.settle,
              prepare: shot.prepare,
            );
            final blocking = [
              for (final i in report.blocking)
                if (!_byDesign(tester, i)) i,
            ];
            // Staggered reveals and sheet transitions must finish before the
            // tree goes away.
            await pumpFor(tester, const Duration(milliseconds: 400));
            await unmountAndSettle(tester);
            expect(blocking, isEmpty, reason: report.summary());
          } finally {
            await f.dispose();
          }
        },
        skip: sqliteSkip != null || !layoutShots,
        timeout: const Timeout(Duration(minutes: 3)),
      );
    }
  }
}

// ------------------------------------------------------- known overlaps --

final _overlapPair = RegExp(r'^"(.*)" (\[[^\]]*\]) x "(.*)" (\[[^\]]*\])$');

/// Overlaps the audit reports that are not layout faults:
///
/// * text in a bottom sheet over text of the page behind it: the tool has no
///   notion of routes, and the modal barrier dims the page;
/// * page text that has scrolled under a pinned app bar, which is opaque;
/// * the celebration's ROASTED / RECKLESS stamp across the score: the kit
///   draws it there on purpose (`lib/app/ui/celebration.dart`).
///
/// Texts are matched by words and box together, the way the audit prints
/// them, because a sheet title can repeat a caption on the page behind it.
bool _byDesign(WidgetTester tester, LayoutIssue issue) {
  if (issue.kind != 'overlap') return false;
  final m = _overlapPair.firstMatch(issue.detail);
  if (m == null) return false;
  const stamps = {'ROASTED', 'RECKLESS'};
  if (stamps.contains(m.group(1)) || stamps.contains(m.group(3))) return true;
  final a = '${m.group(1)} ${m.group(2)}';
  final b = '${m.group(3)} ${m.group(4)}';
  final covered = _coveredTexts(tester);
  return covered.sheet.contains(a) != covered.sheet.contains(b) ||
      covered.appBar.contains(a) != covered.appBar.contains(b);
}

/// Every text run inside a modal bottom sheet or an app bar, as
/// `"words" [l,t wxh]` the way the audit prints it.
({Set<String> sheet, Set<String> appBar}) _coveredTexts(WidgetTester tester) {
  final sheet = <String>{};
  final appBar = <String>{};
  for (final ro in tester.allRenderObjects) {
    if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
    final creator = ro.debugCreator;
    if (creator is! DebugCreator) continue;
    var inSheet = false;
    var inAppBar = false;
    creator.element.visitAncestorElements((e) {
      if (e.widget is BottomSheet) inSheet = true;
      if (e.widget is AppBar) inAppBar = true;
      return !(inSheet || inAppBar);
    });
    if (!inSheet && !inAppBar) continue;
    final text = ro.text.toPlainText().replaceAll('\n', ' ').trim();
    final short = text.length <= 40 ? text : '${text.substring(0, 37)}...';
    final r = MatrixUtils.transformRect(
      ro.getTransformTo(null),
      Offset.zero & ro.size,
    );
    final key =
        '$short [${r.left.round()},${r.top.round()} ${r.width.round()}x'
        '${math.max(0, r.height.round())}]';
    (inSheet ? sheet : appBar).add(key);
  }
  return (sheet: sheet, appBar: appBar);
}

// --------------------------------------------------------------- stand-ins --

/// `myCirclesProvider` with a fixed list and no network.
class _FixedCircles extends MyCirclesNotifier {
  _FixedCircles(this.circles);
  final List<Circle> circles;

  @override
  Future<List<Circle>> build() async => circles;
}

/// A dark street grid in place of the Google map tiles.
class _MapStandIn extends StatelessWidget {
  const _MapStandIn();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _GridPainter(), size: Size.infinite);
}

/// The grid with a route line, in place of the trip map.
class _RouteStandIn extends StatelessWidget {
  const _RouteStandIn();

  @override
  Widget build(BuildContext context) => const CustomPaint(
    painter: _GridPainter(route: true),
    size: Size.infinite,
  );
}

class _GridPainter extends CustomPainter {
  const _GridPainter({this.route = false});
  final bool route;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1B2130),
    );
    final minor = Paint()
      ..color = const Color(0xFF232B3C)
      ..strokeWidth = 1.5;
    for (var x = 14.0; x < w; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), minor);
    }
    for (var y = 10.0; y < h; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(w, y), minor);
    }
    final major = Paint()
      ..color = const Color(0xFF2E3850)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final fx in [0.22, 0.56, 0.84]) {
      canvas.drawLine(Offset(w * fx, 0), Offset(w * fx, h), major);
    }
    for (final fy in [0.28, 0.66]) {
      canvas.drawLine(Offset(0, h * fy), Offset(w, h * fy), major);
    }
    if (route) {
      final path = Path()
        ..moveTo(w * 0.12, h * 0.78)
        ..cubicTo(w * 0.3, h * 0.2, w * 0.6, h * 0.9, w * 0.88, h * 0.3);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF13C2A3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
