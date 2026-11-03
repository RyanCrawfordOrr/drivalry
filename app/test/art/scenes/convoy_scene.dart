import 'dart:convert';

import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/channel/convoy_channel.dart';
import 'package:drivalry/features/convoy/radio/convoy_radio_screen.dart';
import 'package:drivalry/features/convoy/radio/ice_servers.dart';
import 'package:drivalry/features/convoy/radio/peer_link.dart';
import 'package:drivalry/features/convoy/radio/radio_controller.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../support/fake_tracking_port.dart';
import '../art_harness.dart';
import '../../support/radio_fakes.dart';
import '../../support/sqlite_support.dart';
import '../../support/widget_support.dart';
import 'scene.dart';

/// The fictional five-car convoy every convoy scene shows, seeded into the
/// local cache the way a signed-in session would have it after a sync.
abstract final class ArtConvoy {
  static const id = 'art-coast-run';

  // Ids sort in roster order, so the radio lists Sam, Priya, Jordan.
  static const me = 'u0-alex';
  static const sam = 'u1-sam';
  static const priya = 'u2-priya';
  static const jordan = 'u3-jordan';
  static const maya = 'u4-maya';

  static final DateTime joined = DateTime.utc(2026, 11, 2, 8);
  static final DateTime started = DateTime.utc(2026, 11, 3, 9, 30);
  static final int nowMs = started.millisecondsSinceEpoch + 2 * 3600 * 1000;

  static List<ConvoyMember> members() => [
    _member(me, 'alex', 'Alex'),
    _member(sam, 'sam', 'Sam', role: 'leader'),
    _member(priya, 'priya', 'Priya'),
    _member(jordan, 'jordan', 'Jordan'),
    _member(maya, 'maya', 'Maya'),
  ];

  static ConvoyMember _member(
    String userId,
    String handle,
    String name, {
    String role = 'member',
  }) => ConvoyMember(
    userId: userId,
    handle: handle,
    displayName: name,
    role: role,
    joinedAt: joined,
  );

  static Convoy convoy() => Convoy(
    id: id,
    name: 'Coast run',
    createdBy: sam,
    status: ConvoyStatus.active,
    inviteCode: 'coast42',
    createdAt: joined,
    startedAt: started,
    memberCount: 5,
    destination: const Destination(
      name: 'Pinecrest Lake',
      lat: 38.187,
      lon: -119.995,
    ),
  );

  /// Writes the convoy and its members into [db]'s remote cache.
  static Future<void> seed(AppDatabase db) async {
    await db.cachePut(
      ConvoyRepo.cacheKey,
      jsonEncode([convoy().toJson()]),
      nowMs,
    );
    await db.cachePut(
      ConvoyRepo.membersKey(id),
      jsonEncode([for (final m in members()) m.toJson()]),
      nowMs,
    );
  }
}

/// The push-to-talk radio with three cars connected and one of them talking.
///
/// The real `ConvoyRadioScreen` gates its body behind `SignedInScope`, which
/// a test build (no Supabase project) renders as an "Offline build" notice,
/// so this scene puts the same `RadioBody` in the same `Scaffold` directly.
class ConvoyRadioScene extends ArtScene {
  AppDatabase? _db;
  FakeTrackingPort? _port;
  FakeConvoyChannel? _channel;
  FakePeerLinkFactory? _links;

  @override
  String get id => '05-convoy';

  @override
  String get headline => 'Road trips in convoy.';

  @override
  String get subline =>
      'One shared map, a vote on the next stop and a push-to-talk radio '
      'between the cars.';

  @override
  Future<Widget> build() async {
    final db = memoryDatabase();
    _db = db;
    await ArtConvoy.seed(db);
    final port = FakeTrackingPort();
    _port = port;
    final channel = FakeConvoyChannel(
      ArtConvoy.id,
      present: {ArtConvoy.me, ArtConvoy.sam, ArtConvoy.priya, ArtConvoy.jordan},
    );
    _channel = channel;
    final links = FakePeerLinkFactory();
    _links = links;
    // A TURN relay is configured, so the footer reads "Relay available"
    // rather than warning about cars that cannot connect directly.
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode([
          {
            'urls': 'turn:relay.example.net:3478',
            'username': 'art',
            'credential': 'art',
          },
        ]),
        200,
      ),
    );

    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        trackingPortProvider.overrideWithValue(port),
        httpClientProvider.overrideWithValue(client),
        currentUserIdProvider.overrideWithValue(ArtConvoy.me),
        convoyChannelProvider.overrideWith(
          (ref, id) => id == ArtConvoy.id ? channel : null,
        ),
        radioDepsProvider.overrideWithValue(
          RadioDeps(
            linkFactory: links,
            newAudio: FakeLocalAudio.new,
            requestMicrophone: () async => MicPermission.granted,
          ),
        ),
        iceServersProvider.overrideWith(
          (ref) => IceServersProvider(
            db,
            client,
            meteredDomain: 'relay.example.net',
            meteredApiKey: 'art',
          ),
        ),
      ],
      child: MaterialApp(
        theme: artTheme(Brightness.light),
        darkTheme: artTheme(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(title: const Text('Radio')),
          body: const RadioBody(convoyId: ArtConvoy.id),
        ),
      ),
    );
  }

  @override
  Future<void> prepare(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RadioBody)),
    );
    await container
        .read(radioControllerProvider(ArtConvoy.id).notifier)
        .start();
    await pumpFor(tester, const Duration(milliseconds: 300));

    // Sam and Priya connect directly; Jordan's car is behind a strict NAT
    // and goes through the relay, which is what the footer's byte count
    // comes from.
    const kb = 1024;
    for (final (peer, relayed, sent, received) in [
      (ArtConvoy.sam, false, 412 * kb, 388 * kb),
      (ArtConvoy.priya, false, 365 * kb, 1254 * kb),
      (ArtConvoy.jordan, true, 298 * kb, 301 * kb),
    ]) {
      final link = _links?.links[peer];
      if (link == null) continue;
      link.emit(const LinkStateChanged(LinkState.connected));
      link.emit(const LinkDataOpen());
      link.emit(
        LinkStats(relayed: relayed, bytesSent: sent, bytesReceived: received),
      );
    }
    await pumpFor(tester, const Duration(milliseconds: 300));

    // Priya is on the air.
    _channel?.inject('ptt', ArtConvoy.priya, payload: {'on': true});
  }

  @override
  Future<void> dispose() async {
    _channel?.dispose();
    await _port?.dispose();
    await _db?.close();
  }
}
