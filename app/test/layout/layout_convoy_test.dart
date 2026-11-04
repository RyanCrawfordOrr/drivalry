// Layout audit for the convoy area (docs/12-ux-direction.md §2): every
// screen and state at a small Android phone and an iPhone, dark, with the
// hub and the map screen also in light.
//
//   DRIVALRY_LAYOUT=1 flutter test test/layout/layout_convoy_test.dart
//
// Opt-in like layout_scenes_test.dart: fonts come from the Flutter cache,
// which CI does not populate, so without DRIVALRY_LAYOUT the suite skips.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/convoy/eta.dart';
import 'package:drivalry/data/convoy/lost_sheep.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/google/google_quota.dart';
import 'package:drivalry/data/google/places_client.dart';
import 'package:drivalry/data/google/routes_client.dart' show LatLon;
import 'package:drivalry/data/repos/convoy_repo.dart';
import 'package:drivalry/data/repos/convoy_sync.dart';
import 'package:drivalry/data/spotify/spotify_auth.dart';
import 'package:drivalry/data/spotify/spotify_client.dart';
import 'package:drivalry/data/spotify/spotify_providers.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/features/convoy/album/convoy_album_screen.dart';
import 'package:drivalry/features/convoy/audio/convoy_audio_session.dart';
import 'package:drivalry/features/convoy/channel/convoy_channel.dart';
import 'package:drivalry/features/convoy/chat/chat_controller.dart';
import 'package:drivalry/features/convoy/chat/convoy_chat_screen.dart';
import 'package:drivalry/features/convoy/chat/voice_notes.dart';
import 'package:drivalry/features/convoy/convoy_detail_screen.dart';
import 'package:drivalry/features/convoy/convoy_screen.dart';
import 'package:drivalry/features/convoy/create_convoy_screen.dart';
import 'package:drivalry/features/convoy/expenses/convoy_expenses_screen.dart';
import 'package:drivalry/features/convoy/games/convoy_games_screen.dart';
import 'package:drivalry/features/convoy/games/games_controller.dart';
import 'package:drivalry/features/convoy/join_convoy_screen.dart';
import 'package:drivalry/features/convoy/live/convoy_live.dart';
import 'package:drivalry/features/convoy/music/convoy_music_screen.dart';
import 'package:drivalry/features/convoy/music/dj_controller.dart';
import 'package:drivalry/features/convoy/positions/peer_positions.dart';
import 'package:drivalry/features/convoy/radio/convoy_radio_screen.dart';
import 'package:drivalry/features/convoy/radio/data_bus.dart';
import 'package:drivalry/features/convoy/radio/peer_link.dart';
import 'package:drivalry/features/convoy/radio/radio_controller.dart';
import 'package:drivalry/features/convoy/recap/convoy_recap_screen.dart';
import 'package:drivalry/features/convoy/stops/convoy_stops_screen.dart';
import 'package:drivalry/features/convoy/widgets/convoy_ui.dart';
import 'package:drivalry/tracking/providers.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../art/art_harness.dart';
import '../support/fake_tracking_port.dart';
import '../support/radio_fakes.dart';
import '../support/sqlite_support.dart';
import '../support/widget_support.dart';
import 'layout_audit.dart';

// ---------------------------------------------------------------- the cast --

const _id = 'c1';
const _me = 'me';
const _lead = 'lead';
const _priya = 'priya';
const _jordan = 'jordan';
final DateTime _created = DateTime.utc(2026, 11, 2, 8);
final DateTime _started = DateTime.utc(2026, 11, 3, 9, 30);

/// My convoy list as a signed-in session would hold it.
class _Convoys extends MyConvoysNotifier {
  _Convoys(this.list);
  final List<Convoy> list;
  @override
  Future<List<Convoy>> build() async => list;
}

ConvoyMember _member(String id, String name, {String role = 'member'}) =>
    ConvoyMember(
      userId: id,
      handle: name.toLowerCase(),
      displayName: name,
      role: role,
      joinedAt: _created,
    );

List<ConvoyMember> _members({String leader = _lead}) => [
  _member(_me, 'Alex', role: leader == _me ? 'leader' : 'member'),
  _member(_lead, 'Sam', role: leader == _lead ? 'leader' : 'member'),
  _member(_priya, 'Priya'),
  _member(_jordan, 'Jordan'),
];

const _pinecrest = Destination(
  name: 'Pinecrest Lake',
  lat: 38.187,
  lon: -119.995,
);

Convoy _convoy({
  ConvoyStatus status = ConvoyStatus.active,
  String leader = _lead,
  String id = _id,
  String name = 'Coast run',
  Destination? destination = _pinecrest,
}) => Convoy(
  id: id,
  name: name,
  createdBy: leader,
  status: status,
  inviteCode: 'coast42',
  createdAt: _created,
  startedAt: status == ConvoyStatus.planning ? null : _started,
  endedAt: status == ConvoyStatus.ended
      ? _started.add(const Duration(hours: 3))
      : null,
  memberCount: 4,
  destination: destination,
);

ConvoyStop _stop(
  String id,
  String name,
  StopCategory category,
  String by,
  StopStatus status,
  Map<String, int> votes, {
  required int minute,
}) => ConvoyStop(
  id: 'stop-$id',
  convoyId: _id,
  proposedBy: by,
  category: category,
  name: name,
  lat: 38.0 + minute / 1000,
  lon: -120.2 + minute / 1000,
  status: status,
  createdAt: _started.add(Duration(minutes: minute)),
  votes: votes,
);

List<ConvoyStop> _stopList() => [
  _stop(
    'diner',
    'Pine Ridge Diner',
    StopCategory.food,
    _priya,
    StopStatus.accepted,
    {_priya: 1, _lead: 1, _me: 1, _jordan: 1},
    minute: 48,
  ),
  _stop(
    'fuel',
    'Summit Fuel Stop',
    StopCategory.gas,
    _lead,
    StopStatus.proposed,
    {_lead: 1, _jordan: 1},
    minute: 71,
  ),
  _stop(
    'lookout',
    'Eagle Point Lookout',
    StopCategory.photo,
    _me,
    StopStatus.proposed,
    {_me: 1, _priya: 1, _lead: -1},
    minute: 83,
  ),
  _stop(
    'shack',
    'Harbor Fish Shack',
    StopCategory.food,
    _jordan,
    StopStatus.proposed,
    {_jordan: 1, _me: -1},
    minute: 90,
  ),
  _stop(
    'chargers',
    'Ridgeline Chargers',
    StopCategory.charging,
    _priya,
    StopStatus.done,
    {_priya: 1, _me: 1, _lead: 1},
    minute: 12,
  ),
  _stop(
    'motel',
    'Roadside Motel',
    StopCategory.lodging,
    _jordan,
    StopStatus.rejected,
    {_jordan: 1, _me: -1, _lead: -1},
    minute: 20,
  ),
];

List<ConvoyExpense> _expenseList() => [
  ConvoyExpense(
    id: 'e1',
    convoyId: _id,
    payerId: _me,
    amountCents: 6240,
    category: 'gas',
    createdAt: _started.add(const Duration(minutes: 50)),
  ),
  ConvoyExpense(
    id: 'e2',
    convoyId: _id,
    payerId: _lead,
    amountCents: 3850,
    category: 'food',
    note: 'Tacos for everyone',
    createdAt: _started.add(const Duration(minutes: 95)),
  ),
  ConvoyExpense(
    id: 'e3',
    convoyId: _id,
    payerId: _priya,
    amountCents: 1200,
    category: 'tolls',
    createdAt: _started.add(const Duration(minutes: 130)),
  ),
];

const _track1 = SpotifyTrack(
  uri: 'spotify:track:1',
  name: 'Midnight City',
  artists: 'M83',
  durationMs: 243000,
);
const _track2 = SpotifyTrack(
  uri: 'spotify:track:2',
  name: 'Running Up That Hill',
  artists: 'Kate Bush',
  durationMs: 300000,
);

// ---------------------------------------------------------------- fakes --

class _FakeRecorder implements VoiceRecorder {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<Uint8List?> stop() async => Uint8List.fromList(List.filled(2048, 7));
  @override
  Future<void> dispose() async {}
}

class _FakePlayer implements VoicePlayer {
  @override
  Future<void> play(Uint8List bytes, String mimeType) async {}
}

/// Places that answers every nearby search with [results] (null: the API is
/// resting, which the sheet explains).
class _FakePlaces extends PlacesClient {
  _FakePlaces(AppDatabase db, this.results)
    : super(MockClient((_) async => http.Response('', 500)), GoogleQuota(db));
  final List<PlaceSuggestion>? results;

  @override
  Future<List<PlaceSuggestion>?> nearby(
    LatLon center,
    StopCategory category, {
    double radiusM = 5000,
    int maxResults = 10,
  }) async => results;
}

List<PlaceSuggestion> _gasStations() => [
  for (final (i, (name, rating, open)) in [
    ('Summit Fuel Stop', 4.4, true),
    ('Pine Ridge Gas and Go', 4.1, true),
    ('Highway 108 Chevron', 3.9, false),
    ('Sonora Pass Service', 4.6, true),
    ('Twain Harte Shell', 4.0, null),
  ].indexed)
    PlaceSuggestion(
      placeId: 'place-$i',
      name: name,
      location: LatLon(38.02 + i * 0.01, -120.21 + i * 0.03),
      address: '$name, CA',
      rating: rating,
      openNow: open,
    ),
];

// -------------------------------------------------------------- fixture --

/// Everything one scene needs: an in-memory database seeded like a signed-in
/// session, fakes for the platform pieces and the overrides that wire them.
class _Fixture {
  _Fixture({
    Set<String> present = const {_me, _lead, _priya, _jordan},
    TrackingState tracking = const TrackingState(),
  }) : channel = FakeConvoyChannel(_id, present: present),
       port = FakeTrackingPort(state: tracking);

  final AppDatabase db = memoryDatabase();
  final FakeTrackingPort port;
  final FakeConvoyChannel channel;
  final LoopbackDataBus bus = LoopbackDataBus(_me);
  final FakePeerLinkFactory links = FakePeerLinkFactory();
  final FakeLocalAudio audio = FakeLocalAudio();
  final InMemorySpotifyTokenStore tokens = InMemorySpotifyTokenStore();

  List<Convoy> convoys = [];
  String me = _me;

  /// Give the radio and the chat the fake channel. Off by default so the map
  /// screen's live wiring stays out of scenes that do not need it.
  bool withChannel = false;
  Future<MicPermission> Function() microphone = () async =>
      MicPermission.granted;

  /// Live state the map screen reads, pinned for a scene instead of flowing
  /// from a channel.
  Map<String, PeerPosition>? positions;
  Map<String, LostSheep>? lost;
  Map<String, EtaInfo>? etas;

  /// Places answers for the stop suggestions; null keeps the real client,
  /// which has no key under test.
  PlacesClient? places;

  Future<void> seedMembers({String leader = _lead}) => db.cachePut(
    ConvoyRepo.membersKey(_id),
    jsonEncode([for (final m in _members(leader: leader)) m.toJson()]),
    1,
  );

  Widget app(Widget home, {bool light = false}) => ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      trackingPortProvider.overrideWithValue(port),
      currentUserIdProvider.overrideWithValue(me),
      cloudConfiguredProvider.overrideWithValue(true),
      deepLinkSourceProvider.overrideWithValue(const NoDeepLinks()),
      httpClientProvider.overrideWithValue(
        MockClient((_) async => http.Response('', 500)),
      ),
      myConvoysProvider.overrideWith(() => _Convoys(convoys)),
      if (withChannel) convoyChannelProvider.overrideWith((ref, id) => channel),
      convoyDataBusProvider.overrideWith((ref, id) => bus),
      speakerProvider.overrideWithValue(RecordingSpeaker()),
      voicePlayerProvider.overrideWithValue(_FakePlayer()),
      voiceRecorderProvider.overrideWithValue(_FakeRecorder()),
      spotifyTokenStoreProvider.overrideWithValue(tokens),
      radioDepsProvider.overrideWithValue(
        RadioDeps(
          linkFactory: links,
          newAudio: () => audio,
          requestMicrophone: () => microphone(),
        ),
      ),
      if (positions case final p?)
        peerPositionsProvider.overrideWith((ref, id) => Stream.value(p)),
      if (lost case final l?)
        lostSheepProvider.overrideWith((ref, id) => Stream.value(l)),
      if (etas case final e?)
        convoyEtasProvider.overrideWith((ref, id) => Stream.value(e)),
      if (places case final c?) placesClientProvider.overrideWithValue(c),
    ],
    child: MaterialApp(
      theme: artTheme(Brightness.light),
      darkTheme: artTheme(),
      themeMode: light ? ThemeMode.light : ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );

  Future<void> dispose() async {
    channel.dispose();
    bus.dispose();
    await port.dispose();
    await db.close();
  }
}

typedef _Built = (_Fixture, Widget);
typedef _Prepare =
    Future<void> Function(WidgetTester tester, _Fixture f, PhoneSize size);

class _Scene {
  const _Scene(this.name, this.build, {this.prepare});
  final String name;
  final Future<_Built> Function() build;
  final _Prepare? prepare;
}

ProviderContainer _container(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

/// The soft keyboard: 300 logical pixels of bottom inset.
void _keyboard(WidgetTester tester, PhoneSize size) {
  tester.view.viewInsets = FakeViewPadding(bottom: 300 * size.dpr);
  // The platform folds the gesture bar into the keyboard inset: padding's
  // bottom reads 0 while the keyboard is up.
  tester.view.padding = FakeViewPadding(top: size.top * size.dpr);
}

/// What is actually on screen of every text: its box clipped to each scroll
/// viewport above it, and nothing at all when a modal sheet's scrim covers
/// its route. Keyed by the `"text" [rect]` fragment the audit prints, so an
/// overlap it reports from full boxes can be re-checked on the visible
/// parts (the audit has no occlusion model).
Map<String, Rect> _visibleRects(WidgetTester tester) {
  final out = <String, Rect>{};
  final seen = Set<RenderObject>.identity();
  for (final element in tester.allElements) {
    if (element.widget is! RichText) continue;
    final ro = element.renderObject;
    if (ro is! RenderParagraph || !ro.attached || !seen.add(ro)) continue;
    final rect = MatrixUtils.transformRect(
      ro.getTransformTo(null),
      Offset.zero & ro.size,
    );
    var visible = ModalRoute.of(element)?.isCurrent == false ? Rect.zero : rect;
    for (var n = ro.parent; n != null; n = n.parent) {
      if (n is! RenderAbstractViewport) continue;
      final box = n as RenderBox;
      visible = visible.intersect(
        MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        ),
      );
    }
    final text = ro.text.toPlainText().replaceAll('\n', ' ').trim();
    out['"${_short(text)}" ${_rect(rect)}'] = visible;
  }
  return out;
}

/// True unless [issue] is an overlap whose two texts do not meet on screen.
bool _onScreen(LayoutIssue issue, Map<String, Rect> visible) {
  if (issue.kind != 'overlap') return true;
  final parts = issue.detail.split('] x "');
  if (parts.length != 2) return true;
  final a = visible['${parts[0]}]'];
  final b = visible['"${parts[1]}'];
  if (a == null || b == null) return true;
  final x = a.intersect(b);
  return x.width > 2 && x.height > 2;
}

String _short(String s) => s.length <= 40 ? s : '${s.substring(0, 37)}...';
String _rect(Rect r) =>
    '[${r.left.round()},${r.top.round()} ${r.width.round()}x'
    '${math.max(0, r.height.round())}]';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await pumpFor(tester, const Duration(milliseconds: 600));
}

Future<void> _dragSheet(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(SheetHandle), Offset(0, dy));
  await pumpFor(tester, const Duration(milliseconds: 800));
}

// --------------------------------------------------------------- builders --

Future<_Built> _hub({
  List<Convoy> convoys = const [],
  String me = _me,
  bool light = false,
}) async {
  final f = _Fixture()
    ..me = me
    ..convoys = convoys;
  await f.seedMembers(
    leader: convoys.isEmpty ? _lead : convoys.first.createdBy,
  );
  return (f, f.app(const ConvoyScreen(), light: light));
}

List<Convoy> _hubList() => [
  _convoy(),
  _convoy(
    status: ConvoyStatus.planning,
    id: 'c2',
    name: 'Night run',
    destination: null,
  ),
  _convoy(status: ConvoyStatus.ended, id: 'c9', name: 'Desert loop'),
];

Future<_Built> _create() async {
  final f = _Fixture();
  return (f, f.app(const CreateConvoyScreen()));
}

Future<_Built> _join() async {
  final f = _Fixture();
  return (f, f.app(const JoinConvoyScreen(code: 'coast42')));
}

Future<_Built> _detail({
  ConvoyStatus status = ConvoyStatus.active,
  String leader = _me,
  Destination? destination = _pinecrest,
  bool light = false,
  bool onTheRoad = false,
}) async {
  final f = _Fixture()
    ..convoys = [
      _convoy(status: status, leader: leader, destination: destination),
    ];
  await f.seedMembers(leader: leader);
  if (onTheRoad) {
    final now = DateTime.now().millisecondsSinceEpoch;
    PeerPosition pos(String id, double lat, {double? speed, int ago = 0}) =>
        PeerPosition(
          userId: id,
          t: now - ago,
          lat: lat,
          lon: -120,
          speed: speed,
          source: PositionSource.mesh,
        );
    final positions = {
      _lead: pos(_lead, 38.10, speed: 29),
      _me: pos(_me, 38.08, speed: 27),
      _priya: pos(_priya, 38.07, speed: 0),
      // Five minutes quiet and far behind the leader: the long subtitle.
      _jordan: pos(_jordan, 37.95, speed: 20, ago: 5 * 60 * 1000),
    };
    f
      ..positions = positions
      ..lost = {_jordan: const LostSheep(userId: _jordan, reason: 'behind')}
      ..etas = {
        _lead: EtaInfo(
          userId: _lead,
          seconds: 42 * 60,
          estimated: false,
          at: now,
        ),
        _me: EtaInfo(userId: _me, seconds: 47 * 60, estimated: false, at: now),
        _priya: EtaInfo(
          userId: _priya,
          seconds: 95 * 60,
          estimated: true,
          at: now,
        ),
      };
  }
  return (f, f.app(const ConvoyDetailScreen(convoyId: _id), light: light));
}

Future<_Built> _detailMissing() async {
  final f = _Fixture();
  return (f, f.app(const ConvoyDetailScreen(convoyId: 'nope')));
}

Future<_Built> _radio({
  Set<String> present = const {_me, _lead, _priya, _jordan},
  Future<MicPermission> Function()? microphone,
}) async {
  final f = _Fixture(present: present)
    ..withChannel = true
    ..convoys = [_convoy()];
  if (microphone != null) f.microphone = microphone;
  await f.seedMembers();
  return (f, f.app(const ConvoyRadioScreen(convoyId: _id)));
}

/// Starts the radio, then connects [connect], fails [stuck], has [talking]
/// speak and, with [holding], presses the big button.
_Prepare _startRadio({
  Iterable<String> connect = const [],
  String? stuck,
  String? talking,
  bool holding = false,
}) => (tester, f, size) async {
  final ctl = _container(
    tester,
    ConvoyRadioScreen,
  ).read(radioControllerProvider(_id).notifier);
  unawaited(ctl.start());
  await pumpFor(tester, const Duration(milliseconds: 400));
  for (final peer in connect) {
    f.links.links[peer]
      ?..emit(const LinkStateChanged(LinkState.connected))
      ..emit(const LinkDataOpen());
  }
  if (stuck != null) {
    f.links.links[stuck]?.emit(const LinkStateChanged(LinkState.failed));
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
  if (talking != null) f.channel.inject('ptt', talking, payload: {'on': true});
  if (holding) unawaited(ctl.press());
  await pumpFor(tester, const Duration(milliseconds: 300));
};

Future<_Built> _stops({
  bool leader = false,
  bool seeded = true,
  List<PlaceSuggestion>? Function(AppDatabase db)? places,
}) async {
  final who = leader ? _me : _lead;
  final f = _Fixture()..convoys = [_convoy(leader: who)];
  await f.seedMembers(leader: who);
  if (seeded) {
    await f.db.cachePut(
      ConvoyRepo.stopsKey(_id),
      jsonEncode([for (final s in _stopList()) s.toJson()]),
      1,
    );
  }
  if (places != null) {
    f.port.lastKnown = const LastKnownLocation(
      t: 0,
      lat: 37.9,
      lon: -120.3,
      accuracy: 10,
    );
    f.places = _FakePlaces(f.db, places(f.db));
  }
  return (f, f.app(const ConvoyStopsScreen(convoyId: _id)));
}

Future<_Built> _chat({bool driving = false, bool seeded = false}) async {
  final f =
      _Fixture(
          tracking: driving
              ? const TrackingState(phase: TrackingPhase.active, tripId: 'live')
              : const TrackingState(),
        )
        ..withChannel = true
        ..convoys = [_convoy()];
  await f.seedMembers();
  if (seeded) {
    final t0 = DateTime.now().millisecondsSinceEpoch - 20 * 60 * 1000;
    await f.db.cachePut(
      ChatController.cacheKey(_id),
      jsonEncode([
        {
          'id': 'm1',
          'from': _lead,
          't': t0,
          'text': 'Gas at the next exit? Priya is running low.',
        },
        {
          'id': 'm2',
          'from': _me,
          't': t0 + 60000,
          'text': 'Works for me. Pulling in behind you.',
          'mine': true,
        },
        {'id': 'm3', 'from': _priya, 't': t0 + 120000, 'text': 'Yes please'},
      ]),
      1,
    );
  }
  return (f, f.app(const ConvoyChatScreen(convoyId: _id)));
}

/// A voice note arrives from Sam and one of mine goes out.
Future<void> _voiceNotes(WidgetTester tester, _Fixture f) async {
  final data = Uint8List.fromList(List.filled(2048, 1));
  for (final c in const VoiceNoteChunker().split(
    id: 'v1',
    bytes: data,
    mimeType: 'audio/aac',
    durationMs: 4000,
  )) {
    f.bus.inject(_lead, 'voice', c.cast<String, dynamic>());
  }
  await pumpFor(tester, const Duration(milliseconds: 300));
  await _container(tester, ConvoyChatScreen)
      .read(chatControllerProvider(_id).notifier)
      .sendVoiceBytes(data, 'audio/aac', 7000);
  await pumpFor(tester, const Duration(milliseconds: 300));
}

Future<_Built> _music({bool dj = false, bool connected = false}) async {
  final f = _Fixture()..convoys = [_convoy()];
  await f.seedMembers();
  if (connected) {
    f.tokens.tokens = SpotifyTokens(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAtMs: DateTime.now().millisecondsSinceEpoch + 3600 * 1000,
    );
  }
  return (f, f.app(ConvoyMusicScreen(convoyId: _id, djAvailable: dj)));
}

DjController _dj(WidgetTester tester) => _container(
  tester,
  ConvoyMusicScreen,
).read(djControllerProvider(_id).notifier);

Future<_Built> _games({bool driving = false}) async {
  final f = _Fixture(
    tracking: driving
        ? const TrackingState(phase: TrackingPhase.active, tripId: 'live')
        : const TrackingState(),
  )..convoys = [_convoy()];
  await f.seedMembers();
  return (f, f.app(const ConvoyGamesScreen(convoyId: _id)));
}

GamesController _gamesCtl(WidgetTester tester) => _container(
  tester,
  ConvoyGamesScreen,
).read(gamesControllerProvider(_id).notifier);

Future<void> _openTrivia(WidgetTester tester, _Fixture f) async {
  await _tap(tester, find.text('Trivia'));
  _gamesCtl(tester).askNextQuestion();
  await pumpFor(tester, const Duration(milliseconds: 400));
  await _tap(tester, find.byKey(const Key('choice-1')));
  final c = _gamesCtl(tester);
  f.bus.inject(_lead, 'game', {
    'game': 'trivia',
    'event': 'answer',
    'index': c.trivia.currentIndex,
    'choice': c.trivia.current!.answer,
  });
  await pumpFor(tester, const Duration(milliseconds: 300));
}

Future<_Built> _expenses({bool seeded = true}) async {
  final f = _Fixture()..convoys = [_convoy()];
  await f.seedMembers();
  if (seeded) {
    await f.db.cachePut(
      ConvoyRepo.expensesKey(_id),
      jsonEncode([for (final e in _expenseList()) e.toJson()]),
      1,
    );
  }
  return (f, f.app(const ConvoyExpensesScreen(convoyId: _id)));
}

Future<_Built> _album({int photos = 0}) async {
  final f = _Fixture()..convoys = [_convoy()];
  await f.seedMembers();
  if (photos > 0) {
    await f.db.cachePut(
      ConvoyRepo.photosKey(_id),
      jsonEncode([
        for (var i = 0; i < photos; i++)
          ConvoyPhoto(
            id: 'p$i',
            convoyId: _id,
            userId: const [_me, _lead, _priya][i % 3],
            storagePath: '$_id/p$i.jpg',
            takenAt: _started.add(Duration(minutes: 10 * i)),
          ).toJson(),
      ]),
      1,
    );
  }
  return (f, f.app(const ConvoyAlbumScreen(convoyId: _id)));
}

Future<_Built> _recap({bool seeded = true}) async {
  final f = _Fixture();
  if (!seeded) return (f, f.app(const ConvoyRecapScreen(convoyId: 'nope')));
  f.convoys = [_convoy(status: ConvoyStatus.ended)];
  await f.seedMembers();
  await f.db.cachePut(
    ConvoyRepo.stopsKey(_id),
    jsonEncode([for (final s in _stopList()) s.toJson()]),
    1,
  );
  await f.db.cachePut(
    ConvoyRepo.expensesKey(_id),
    jsonEncode([for (final e in _expenseList()) e.toJson()]),
    1,
  );
  for (final (user, lon) in [
    (_lead, -120.0),
    (_me, -120.02),
    (_priya, -119.98),
  ]) {
    for (var i = 0; i < 8; i++) {
      await f.db.insertConvoyTrack(
        ConvoyTracksCompanion(
          convoyId: const Value(_id),
          userId: Value(user),
          t: Value(_started.millisecondsSinceEpoch + i * 60000),
          lat: Value(37.9 + i * 0.02),
          lon: Value(lon + i * 0.004),
        ),
      );
    }
  }
  return (f, f.app(const ConvoyRecapScreen(convoyId: _id)));
}

// ----------------------------------------------------------------- scenes --

final List<_Scene> _scenes = [
  // The hub.
  _Scene('hub-empty', _hub),
  _Scene(
    'hub-past',
    () => _hub(
      convoys: [
        _convoy(status: ConvoyStatus.ended, id: 'c9', name: 'Desert loop'),
        _convoy(
          status: ConvoyStatus.ended,
          id: 'c8',
          name: 'Thanksgiving drive',
          destination: null,
        ),
      ],
    ),
  ),
  _Scene(
    'hub-planning-leader',
    () => _hub(
      convoys: [_convoy(status: ConvoyStatus.planning, leader: _me)],
    ),
  ),
  _Scene(
    'hub-planning-member',
    () => _hub(convoys: [_convoy(status: ConvoyStatus.planning)]),
  ),
  _Scene('hub-active', () => _hub(convoys: _hubList())),
  _Scene('hub-active-light', () => _hub(convoys: _hubList(), light: true)),
  _Scene(
    'hub-join-code-sheet',
    _hub,
    prepare: (tester, f, size) async {
      await _tap(tester, find.byIcon(Icons.key_outlined));
      _keyboard(tester, size);
    },
  ),
  _Scene(
    'hub-invite-sheet',
    () => _hub(convoys: [_convoy(status: ConvoyStatus.planning)]),
    prepare: (tester, f, size) => _tap(tester, find.text('Invite cars')),
  ),

  // Create and join.
  _Scene('create', _create, prepare: (t, f, size) async => _keyboard(t, size)),
  _Scene(
    'create-destination-picker',
    _create,
    prepare: (tester, f, size) async {
      await _tap(tester, find.text('Destination'));
      await tester.enterText(
        find.byKey(const Key('destination-search')),
        'Pine',
      );
      // Past the debounce; without a Places key the sheet says so.
      await pumpFor(tester, const Duration(seconds: 1));
      _keyboard(tester, size);
    },
  ),
  _Scene('join', _join),

  // The map screen and its sheet.
  _Scene('detail-active-leader-half', () => _detail(onTheRoad: true)),
  _Scene(
    'detail-active-leader-peek',
    () => _detail(onTheRoad: true),
    prepare: (tester, f, size) => _dragSheet(tester, 500),
  ),
  _Scene(
    'detail-active-leader-full',
    () => _detail(onTheRoad: true),
    prepare: (tester, f, size) => _dragSheet(tester, -700),
  ),
  _Scene(
    'detail-active-member-half',
    () => _detail(leader: _lead, onTheRoad: true),
  ),
  _Scene(
    'detail-active-member-peek',
    () => _detail(leader: _lead, onTheRoad: true),
    prepare: (tester, f, size) => _dragSheet(tester, 500),
  ),
  _Scene('detail-active-light', () => _detail(onTheRoad: true, light: true)),
  _Scene(
    'detail-planning-leader',
    () => _detail(status: ConvoyStatus.planning, destination: null),
  ),
  _Scene(
    'detail-planning-member',
    () => _detail(status: ConvoyStatus.planning, leader: _lead),
  ),
  _Scene(
    'detail-planning-member-peek',
    () => _detail(status: ConvoyStatus.planning, leader: _lead),
    prepare: (tester, f, size) => _dragSheet(tester, 500),
  ),
  _Scene('detail-ended', () => _detail(status: ConvoyStatus.ended)),
  _Scene('detail-missing', _detailMissing),

  // Radio.
  _Scene('radio-off', _radio),
  _Scene(
    'radio-starting',
    () => _radio(microphone: () => Completer<MicPermission>().future),
    prepare: _startRadio(),
  ),
  _Scene(
    'radio-quiet',
    _radio,
    prepare: _startRadio(connect: [_lead, _priya], stuck: _jordan),
  ),
  _Scene(
    'radio-live',
    _radio,
    prepare: _startRadio(connect: [_lead, _priya, _jordan], talking: _priya),
  ),
  _Scene(
    'radio-on-air',
    _radio,
    prepare: _startRadio(connect: [_lead, _priya, _jordan], holding: true),
  ),
  _Scene(
    'radio-no-peers',
    () => _radio(present: const {_me}),
    prepare: _startRadio(),
  ),
  _Scene(
    'radio-mic-denied',
    () => _radio(microphone: () async => MicPermission.denied),
    prepare: _startRadio(),
  ),
  _Scene(
    'radio-mic-settings',
    () => _radio(microphone: () async => MicPermission.permanentlyDenied),
    prepare: _startRadio(),
  ),

  // Stops.
  _Scene('stops-empty', () => _stops(seeded: false)),
  _Scene('stops-leader', () => _stops(leader: true)),
  _Scene('stops-member', _stops),
  _Scene(
    'stops-suggestions-sheet',
    () => _stops(places: (_) => _gasStations()),
    prepare: (tester, f, size) async {
      await _tap(tester, find.byKey(const Key('stop-category-gas')));
      await pumpFor(tester, const Duration(seconds: 1));
    },
  ),
  _Scene(
    'stops-suggestions-resting',
    () => _stops(places: (_) => null),
    prepare: (tester, f, size) async {
      await _tap(tester, find.byKey(const Key('stop-category-food')));
      await pumpFor(tester, const Duration(seconds: 1));
    },
  ),

  // Chat.
  _Scene('chat-empty', _chat),
  _Scene(
    'chat-messages',
    () => _chat(seeded: true),
    prepare: (tester, f, size) => _voiceNotes(tester, f),
  ),
  _Scene(
    'chat-keyboard',
    () => _chat(seeded: true),
    prepare: (tester, f, size) async {
      await _voiceNotes(tester, f);
      _keyboard(tester, size);
    },
  ),
  _Scene(
    'chat-recording',
    () => _chat(seeded: true),
    prepare: (tester, f, size) async {
      await _voiceNotes(tester, f);
      await _tap(tester, find.byKey(const Key('record-voice')));
      _keyboard(tester, size);
    },
  ),
  _Scene(
    'chat-driving',
    () => _chat(seeded: true, driving: true),
    prepare: (tester, f, size) => _voiceNotes(tester, f),
  ),

  // Music.
  _Scene('music-unavailable', _music),
  _Scene('music-dj-connect', () => _music(dj: true)),
  _Scene(
    'music-dj-other',
    () => _music(dj: true, connected: true),
    prepare: (tester, f, size) async {
      f.bus.connect(_lead);
      f.bus.inject(_lead, 'dj', {'cmd': 'claim'});
      await pumpFor(tester, const Duration(milliseconds: 300));
      f.bus.inject(_lead, 'dj', {
        'cmd': 'play',
        'uri': _track1.uri,
        'positionMs': 0,
        'atT': DateTime.now().millisecondsSinceEpoch + 60000,
        'track': _track1.toJson(),
      });
      await pumpFor(tester, const Duration(milliseconds: 300));
      _dj(tester).voteSkip();
      await pumpFor(tester, const Duration(milliseconds: 300));
    },
  ),
  _Scene(
    'music-dj-me',
    () => _music(dj: true, connected: true),
    prepare: (tester, f, size) async {
      f.bus.connect(_lead);
      await pumpFor(tester, const Duration(milliseconds: 300));
      _dj(tester)
        ..claim()
        ..addToQueue(_track1)
        ..addToQueue(_track2);
      await pumpFor(tester, const Duration(milliseconds: 400));
    },
  ),

  // Games.
  _Scene('games-driver-gate', () => _games(driving: true)),
  _Scene(
    'games-plates',
    _games,
    prepare: (tester, f, size) async {
      await _tap(tester, find.byKey(const Key('plate-CA')));
      await _tap(tester, find.byKey(const Key('plate-AL')));
      f.bus.inject(_lead, 'game', {
        'game': 'plates',
        'event': 'mark',
        'state': ['CA', 'TX', 'NV'],
      });
      await pumpFor(tester, const Duration(milliseconds: 300));
    },
  ),
  _Scene('games-trivia', _games, prepare: (t, f, size) => _openTrivia(t, f)),
  _Scene(
    'games-trivia-result',
    _games,
    prepare: (tester, f, size) async {
      await _openTrivia(tester, f);
      await _tap(tester, find.text('Reveal now'));
    },
  ),
  _Scene(
    'games-spy',
    _games,
    prepare: (tester, f, size) async {
      await _tap(tester, find.text('I spy'));
      await _tap(tester, find.byKey(const Key('spot-Red barn')));
      f.bus.inject(_lead, 'game', {
        'game': 'scavenger',
        'event': 'claim',
        'item': 'Horse',
        't': 1,
      });
      await pumpFor(tester, const Duration(milliseconds: 300));
    },
  ),
  _Scene(
    'games-smoothest-empty',
    _games,
    prepare: (tester, f, size) => _tap(tester, find.text('Smoothest')),
  ),
  _Scene(
    'games-smoothest',
    _games,
    prepare: (tester, f, size) async {
      final hub = _container(
        tester,
        ConvoyGamesScreen,
      ).read(peerPositionHubProvider(_id));
      for (var i = 0; i < 6; i++) {
        for (final (user, speed, wobble) in [
          (_lead, 25.0, 0.1),
          (_priya, 8.0, 7.0),
          (_jordan, 20.0, 2.0),
        ]) {
          hub.push(
            PeerPosition(
              userId: user,
              t: i * 1000,
              lat: 38,
              lon: -120,
              speed: speed + (i.isEven ? wobble : -wobble),
              source: PositionSource.mesh,
            ),
          );
        }
      }
      await pumpFor(tester, const Duration(milliseconds: 300));
      await _tap(tester, find.text('Smoothest'));
    },
  ),

  // Expenses.
  _Scene('expenses-empty', () => _expenses(seeded: false)),
  _Scene('expenses-populated', _expenses),
  _Scene(
    'expenses-add-sheet',
    _expenses,
    prepare: (tester, f, size) async {
      await _tap(tester, find.byKey(const Key('add-expense')));
      await tester.enterText(find.byKey(const Key('expense-amount')), '42.50');
      await pumpFor(tester, const Duration(milliseconds: 300));
      _keyboard(tester, size);
    },
  ),

  // Album.
  _Scene('album-empty', _album),
  _Scene('album-populated', () => _album(photos: 7)),
  _Scene(
    'album-add-sheet',
    _album,
    prepare: (tester, f, size) =>
        _tap(tester, find.byKey(const Key('add-photo'))),
  ),

  // Recap.
  _Scene('recap', _recap),
  _Scene('recap-missing', () => _recap(seeded: false)),
];

void main() {
  // Fonts come from the Flutter cache, which CI does not populate; only load
  // them when the audit actually runs.
  setUpAll(() async {
    if (layoutShots) await loadArtFonts();
  });
  setUp(() => Haptics.enabled = false);
  final sqliteSkip = skipWithoutSqlite();

  for (final scene in _scenes) {
    for (final size in phoneSizes) {
      testWidgets(
        '${scene.name} lays out on $size',
        (tester) async {
          final (f, app) = await scene.build();
          try {
            final report = await auditLayout(
              tester,
              name: 'convoy-${scene.name}',
              app: app,
              size: size,
              prepare: scene.prepare == null
                  ? null
                  : (t) => scene.prepare!(t, f, size),
            );
            final visible = _visibleRects(tester);
            await unmountAndSettle(tester);
            final seen = LayoutReport(report.name, report.size, [
              for (final i in report.issues)
                if (_onScreen(i, visible)) i,
            ], report.pngPath);
            expect(seen.blocking, isEmpty, reason: seen.summary());
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
