import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/circles_repo.dart' show Circle;
import 'package:drivalry/data/repos/circles_sync.dart';
import 'package:drivalry/data/repos/friends_sync.dart';
import 'package:drivalry/data/repos/presence_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/cues/live_limit.dart';
import 'package:drivalry/features/drive/drive_screen.dart';
import 'package:drivalry/features/drive/friends_map/friends_map.dart';
import 'package:drivalry/features/profile/profile_model.dart';
import 'package:drivalry/features/profile/profile_repo.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:drivalry/tracking/weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/fake_tracking_port.dart';
import '../art_harness.dart';
import '../../support/scored_trips.dart';
import '../../support/sqlite_support.dart';
import 'scene.dart';

/// The Drive tab mid-drive: the friends map full-bleed, the speed capsule and
/// the live block in the sheet with the posted limit, the last scored trip
/// peeking underneath.
class DriveScene extends ArtScene {
  AppDatabase? _db;
  FakeTrackingPort? _port;

  @override
  String get id => '01-drive';

  @override
  String get headline => 'Every drive gets a score.';

  @override
  String get subline =>
      'Your phone notices the drive, scores it 0 to 100 on the device and '
      'shows the posted limit as you go.';

  @override
  Duration get settle => const Duration(seconds: 3);

  @override
  Future<Widget> build() async {
    final db = _db = memoryDatabase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // Three scored trips: the newest is the "Last trip" card.
    final trips = [
      (
        'art-92',
        today.add(const Duration(hours: 8, minutes: 5)),
        92,
        70,
        11300.0,
        1380.0,
        'Smooth from the driveway to the parking lot. Textbook.',
      ),
      (
        'art-78',
        yesterday.add(const Duration(hours: 18, minutes: 30)),
        78,
        48,
        5600.0,
        780.0,
        'Mostly smooth. One sharp corner on 12th Ave cost you.',
      ),
      (
        'art-64',
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
      // Answered, so the passenger question does not sit on the tab.
      await db.updateTrip(
        id,
        TripsCompanion(
          passengerAnswered: const Value(true),
          limitCoverage: Value(score >= 90 ? 0.94 : 0.88),
        ),
      );
    }

    // A trip in progress: the plugin reports it active and the controller
    // rebuilds the live numbers from the stored fixes. No `trips` row, so the
    // recording does not appear in the list below.
    const liveId = 'art-live';
    final tripStart = now.subtract(const Duration(minutes: 14));
    final fixes = <SamplesCompanion>[];
    const steps = 14;
    const totalLat = 0.1165; // about 13 km due north: 8.0 mi
    for (var i = 0; i <= steps; i++) {
      final t = tripStart.add(Duration(minutes: i)).millisecondsSinceEpoch;
      final speed = i == steps ? 20.1168 : 15.0 + (i % 5) * 1.6;
      fixes.add(
        SamplesCompanion.insert(
          tripId: liveId,
          t: t,
          lat: 36.10 + totalLat * i / steps,
          lon: -86.80 + 0.004 * (i % 3),
          accuracy: 5,
          speed: Value(speed),
        ),
      );
    }
    await db.insertFixBatch(liveId, tripStart.millisecondsSinceEpoch, fixes);

    final port = _port = FakeTrackingPort(
      state: TrackingState(
        phase: TrackingPhase.active,
        tripId: liveId,
        tripStartedAt: tripStart.millisecondsSinceEpoch,
        permissions: const TrackingPermissions(
          location: LocationPermission.always,
          preciseLocation: true,
          motion: SimplePermission.granted,
          notifications: SimplePermission.granted,
          bluetooth: SimplePermission.granted,
        ),
      ),
    );

    final utc = now.toUtc();
    final presence = <PresenceRow>[
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
      PresenceRow(
        userId: 'u-jordan',
        handle: 'jordan',
        displayName: 'Jordan',
        lat: 36.17,
        lon: -86.75,
        driving: true,
        speed: 11.0,
        battery: 0.88,
        updatedAt: utc.subtract(const Duration(seconds: 45)),
      ),
    ];
    final circles = [
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
    const membership = <String, Set<String>>{
      'c-carpool': {'me', 'u-sam', 'u-priya'},
      'c-family': {'me', 'u-jordan'},
    };
    final limit = LiveLimitState(
      tripId: liveId,
      limitMps: 20.1168,
      posted: 45,
      unitLabel: 'mph',
      roadName: 'Harding Pike',
      confidence: 0.96,
      speedMps: 20.1168,
      sinceMs: now.millisecondsSinceEpoch - 90_000,
      updatedAt: now.millisecondsSinceEpoch,
    );

    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        trackingPortProvider.overrideWithValue(port),
        deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
        weatherClientProvider.overrideWithValue(const NoWeather()),
        currentUserIdProvider.overrideWithValue('me'),
        friendsMapSurfaceProvider.overrideWithValue((_) => const _MapStandIn()),
        visiblePresenceProvider.overrideWith((_) => Stream.value(presence)),
        myCirclesProvider.overrideWith(() => _FixedCircles(circles)),
        circleMembershipProvider.overrideWithValue(membership),
        liveLimitProvider.overrideWith((_) => Stream.value(limit)),
        // The floating chrome: a real avatar, two requests waiting, and no
        // developer button in the store shot.
        myProfileProvider.overrideWith(
          (_) => Stream.value(
            const Profile(id: 'me', handle: 'ryan', displayName: 'Ryan Orr'),
          ),
        ),
        pendingRequestCountProvider.overrideWithValue(2),
        devToolsVisibleProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const DriveScreen(),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    await _port?.dispose();
    await _db?.close();
  }
}

/// `myCirclesProvider` with a fixed list and no network.
class _FixedCircles extends MyCirclesNotifier {
  _FixedCircles(this.circles);
  final List<Circle> circles;

  @override
  Future<List<Circle>> build() async => circles;
}

/// Stands in for the Google map tile layer: a dark street grid, a river and
/// the friend pins the real map would draw as markers.
class _MapStandIn extends StatelessWidget {
  const _MapStandIn();

  @override
  Widget build(BuildContext context) =>
      const CustomPaint(painter: _MapPainter(), size: Size.infinite);
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  static const _field = Color(0xFF1B2130);
  static const _minor = Color(0xFF232B3C);
  static const _major = Color(0xFF2E3850);
  static const _river = Color(0xFF16202F);
  static const _orange = Color(0xFFF08566);
  static const _teal = Color(0xFF13C2A3);
  static const _amber = Color(0xFFF5B400);
  static const _blue = Color(0xFF4C8DFF);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = _field);

    // Minor streets: a regular grid.
    final minor = Paint()
      ..color = _minor
      ..strokeWidth = 1.5;
    for (var x = 14.0; x < w; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), minor);
    }
    for (var y = 10.0; y < h; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(w, y), minor);
    }

    // Main roads.
    final major = Paint()
      ..color = _major
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final fx in [0.22, 0.56, 0.84]) {
      canvas.drawLine(Offset(w * fx, 0), Offset(w * fx, h), major);
    }
    for (final fy in [0.28, 0.66]) {
      canvas.drawLine(Offset(0, h * fy), Offset(w, h * fy), major);
    }

    // River.
    final river = Path()
      ..moveTo(-30, h * 0.52)
      ..cubicTo(w * 0.22, h * 0.30, w * 0.40, h * 0.98, w * 0.68, h * 0.74)
      ..quadraticBezierTo(w * 0.86, h * 0.60, w + 30, h * 0.70);
    // Faint banks first, so the water reads against the grid.
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0x552A3A52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 42
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      river,
      Paint()
        ..color = _river
        ..style = PaintingStyle.stroke
        ..strokeWidth = 36
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Two arterials cutting across the grid (bridges over the river).
    final arterial = Paint()
      ..color = const Color(0xFF364262)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, h * 0.90), Offset(w * 0.72, 0), arterial);
    canvas.drawLine(Offset(w * 0.30, h), Offset(w, h * 0.18), arterial);

    // Me: a blue dot with a soft accuracy halo.
    final me = Offset(w * 0.44, h * 0.58);
    canvas.drawCircle(me, 20, Paint()..color = _blue.withValues(alpha: 0.18));
    canvas.drawCircle(me, 9, Paint()..color = Colors.white);
    canvas.drawCircle(me, 6.5, Paint()..color = _blue);

    // Friends.
    _pin(canvas, Offset(w * 0.27, h * 0.40), _orange, 'S', driving: true);
    _pin(canvas, Offset(w * 0.70, h * 0.33), _teal, 'P', driving: false);
    _pin(canvas, Offset(w * 0.62, h * 0.78), _amber, 'J', driving: true);
  }

  void _pin(
    Canvas canvas,
    Offset c,
    Color fill,
    String letter, {
    required bool driving,
  }) {
    const r = 17.0;
    canvas.drawCircle(
      c + const Offset(0, 2),
      r + 1,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    canvas.drawCircle(c, r, Paint()..color = driving ? _teal : Colors.white);
    canvas.drawCircle(c, r - 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, r - 4.5, Paint()..color = fill);
    final text = TextPainter(
      text: TextSpan(
        text: letter,
        style: const TextStyle(
          fontFamily: 'Roboto',
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, c - Offset(text.width / 2, text.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
