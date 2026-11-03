import 'dart:convert';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/google/places_client.dart' show StopCategory;
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/repos/convoy_sync.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/stops/convoy_stops_screen.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../support/fake_tracking_port.dart';
import '../art_harness.dart';
import '../../support/sqlite_support.dart';
import 'convoy_scene.dart';
import 'scene.dart';

/// The stops screen of the active convoy: one accepted stop up next, three
/// proposals being voted on and one stop already behind us.
class ConvoyStopsScene extends ArtScene {
  AppDatabase? _db;
  FakeTrackingPort? _port;

  @override
  String get id => '08-stops';

  @override
  String get headline => 'Vote on the next stop.';

  @override
  String get subline =>
      'Anyone proposes gas, food or a photo stop; the convoy votes and the '
      'leader locks it in.';

  @override
  Future<Widget> build() async {
    final db = memoryDatabase();
    _db = db;
    await ArtConvoy.seed(db);
    await db.cachePut(
      ConvoyRepo.stopsKey(ArtConvoy.id),
      jsonEncode([for (final s in _stops()) s.toJson()]),
      ArtConvoy.nowMs,
    );
    final port = FakeTrackingPort();
    _port = port;

    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        trackingPortProvider.overrideWithValue(port),
        currentUserIdProvider.overrideWithValue(ArtConvoy.me),
        // Sam leads this convoy; the leader's accept/reject menu stays out
        // of the tiles so the votes carry the screen.
        amConvoyLeaderProvider.overrideWith((ref, id) => false),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: const ConvoyStopsScreen(convoyId: ArtConvoy.id),
      ),
    );
  }

  List<ConvoyStop> _stops() {
    final t0 = ArtConvoy.started;
    ConvoyStop stop(
      String id,
      String name,
      StopCategory category,
      String by,
      StopStatus status,
      Map<String, int> votes, {
      required int minute,
      required double lat,
      required double lon,
    }) => ConvoyStop(
      id: 'stop-$id',
      convoyId: ArtConvoy.id,
      proposedBy: by,
      category: category,
      name: name,
      lat: lat,
      lon: lon,
      status: status,
      createdAt: t0.add(Duration(minutes: minute)),
      votes: votes,
    );

    return [
      stop(
        'diner',
        'Pine Ridge Diner',
        StopCategory.food,
        ArtConvoy.priya,
        StopStatus.accepted,
        {
          ArtConvoy.priya: 1,
          ArtConvoy.sam: 1,
          ArtConvoy.me: 1,
          ArtConvoy.jordan: 1,
        },
        minute: 48,
        lat: 37.962,
        lon: -120.225,
      ),
      stop(
        'fuel',
        'Summit Fuel Stop',
        StopCategory.gas,
        ArtConvoy.sam,
        StopStatus.proposed,
        {ArtConvoy.sam: 1, ArtConvoy.maya: 1, ArtConvoy.jordan: 1},
        minute: 71,
        lat: 38.041,
        lon: -120.110,
      ),
      stop(
        'lookout',
        'Eagle Point Lookout',
        StopCategory.photo,
        ArtConvoy.me,
        StopStatus.proposed,
        {ArtConvoy.me: 1, ArtConvoy.priya: 1, ArtConvoy.sam: -1},
        minute: 83,
        lat: 38.112,
        lon: -120.034,
      ),
      stop(
        'shack',
        'Harbor Fish Shack',
        StopCategory.food,
        ArtConvoy.jordan,
        StopStatus.proposed,
        {ArtConvoy.jordan: 1, ArtConvoy.me: -1, ArtConvoy.maya: -1},
        minute: 90,
        lat: 38.150,
        lon: -120.012,
      ),
      stop(
        'chargers',
        'Ridgeline Chargers',
        StopCategory.charging,
        ArtConvoy.maya,
        StopStatus.done,
        {ArtConvoy.maya: 1, ArtConvoy.me: 1, ArtConvoy.sam: 1},
        minute: 12,
        lat: 37.801,
        lon: -120.402,
      ),
    ];
  }

  @override
  Future<void> dispose() async {
    await _port?.dispose();
    await _db?.close();
  }
}
