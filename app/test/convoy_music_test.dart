import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/spotify/spotify_auth.dart';
import 'package:drivalry/data/spotify/spotify_client.dart';
import 'package:drivalry/data/spotify/spotify_providers.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/music/convoy_music_screen.dart';
import 'package:drivalry/features/convoy/music/dj_controller.dart';
import 'package:drivalry/features/convoy/radio/data_bus.dart';
import 'package:drivalry/features/convoy/radio/mesh_data_bus.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('the Spotify callback is not a Drivalry deep link', () {
    expect(SpotifyAuth.redirectUri, startsWith('drivalry-auth://'));
    expect(
      deepLinkToRoute(Uri.parse('${SpotifyAuth.redirectUri}?code=x&state=y')),
      isNull,
    );
  });

  testWidgets('Jam links show and DJ is honest about its build', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUserIdProvider.overrideWithValue('me')],
        child: const MaterialApp(home: ConvoyMusicScreen(convoyId: 'c1')),
      ),
    );
    await tester.pump();
    expect(find.text('Everyone on one playlist'), findsOneWidget);
    expect(find.byKey(const Key('open-spotify')), findsOneWidget);
    expect(find.text('Convoy DJ'), findsOneWidget);
    // Tests build without SPOTIFY_CLIENT_ID.
    expect(
      find.textContaining("isn't available in this version"),
      findsOneWidget,
    );
    expect(find.byKey(const Key('connect-spotify')), findsNothing);
    await unmountAndSettle(tester);
  });

  test(
    'DjController follows the data bus when the radio starts',
    () async {
      final db = memoryDatabase();
      final bus = LoopbackDataBus('me');
      // No bus override: the real provider swaps Noop for the mesh bus when
      // the radio registers one.
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue('me'),
          spotifyTokenStoreProvider.overrideWithValue(
            InMemorySpotifyTokenStore(),
          ),
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response('', 500)),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        bus.dispose();
        await db.close();
      });
      final sub = container.listen(djControllerProvider('c1'), (_, _) {});
      addTearDown(sub.close);
      final c = container.read(djControllerProvider('c1').notifier);
      DjState s() => container.read(djControllerProvider('c1'));
      await settle();
      c.claim();
      await settle();
      expect(s().isDj, isTrue);
      expect(s().peers, isEmpty);

      container.read(radioBusRegistryProvider.notifier).register('c1', bus);
      bus.connect('aaa');
      await settle();
      expect(
        identical(container.read(djControllerProvider('c1').notifier), c),
        isTrue,
        reason: 'no rebuild',
      );
      expect(s().isDj, isTrue, reason: 'the claim survives the bus swap');
      expect(s().peers, {'aaa'});
      expect(bus.sent.last.payload['cmd'], 'ping', reason: 'new peer pinged');
    },
    skip: skipWithoutSqlite() != null,
  );

  test(
    'DjController claims, pings new peers, follows the DJ and persists counts',
    () async {
      final db = memoryDatabase();
      final bus = LoopbackDataBus('me');
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          currentUserIdProvider.overrideWithValue('me'),
          convoyDataBusProvider.overrideWith((ref, id) => bus),
          spotifyTokenStoreProvider.overrideWithValue(
            InMemorySpotifyTokenStore(),
          ),
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response('', 500)),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        bus.dispose();
        await db.close();
      });
      final sub = container.listen(djControllerProvider('c1'), (_, _) {});
      final c = container.read(djControllerProvider('c1').notifier);
      DjState s() => container.read(djControllerProvider('c1'));
      await settle();
      expect(s().spotifyConnected, isFalse);
      expect(s().dj, isNull);

      c.claim();
      await settle();
      expect(bus.sent.single.type, 'dj');
      expect(bus.sent.single.payload['cmd'], 'claim');
      expect(s().isDj, isTrue);
      expect(s().dj, 'me');

      // A new peer gets a clock ping straight away.
      bus.connect('aaa');
      await settle();
      expect(s().peers, {'aaa'});
      expect(bus.sent.last.payload['cmd'], 'ping');

      // A lower id takes over; its play commands drive our state.
      bus.inject('aaa', 'dj', {'cmd': 'claim'});
      await settle();
      expect(s().dj, 'aaa');
      expect(s().isDj, isFalse);

      final track = SpotifyTrack(
        uri: 'spotify:track:z',
        name: 'Zed',
        artists: 'Z',
        durationMs: 1000,
      );
      bus.inject('aaa', 'dj', {
        'cmd': 'play',
        'uri': track.uri,
        'positionMs': 0,
        'atT': DateTime.now().millisecondsSinceEpoch + 60_000,
        'track': track.toJson(),
      });
      await settle();
      expect(s().current?.name, 'Zed');
      await settle();
      expect(await db.getSetting(DjController.tracksKey('c1')), '{"aaa":1}');

      c.voteSkip();
      await settle();
      expect(s().skipVotes, 1);
      expect(bus.sent.last.payload['cmd'], 'skip-vote');

      // Queue edits are local until the DJ plays them.
      c.addToQueue(track);
      expect(s().queue, hasLength(1));
      c.removeFromQueue(track.uri);
      expect(s().queue, isEmpty);
      sub.close();
    },
    skip: skipWithoutSqlite(),
  );
}
