import 'dart:async';

import 'package:drivalry/data/convoy/eta.dart';
import 'package:drivalry/data/convoy/positions_link.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/features/convoy/channel/convoy_channel.dart';
import 'package:drivalry/features/convoy/positions/peer_positions.dart';
import 'package:drivalry/features/convoy/radio/data_bus.dart';
import 'package:drivalry/tracking/tracking_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sqlite_support.dart';

/// In-memory channel: records sends, lets the test inject messages.
class FakeConvoyChannel implements ConvoyChannel {
  FakeConvoyChannel(this.convoyId);

  @override
  final String convoyId;
  final _messages = StreamController<ConvoyMessage>.broadcast();
  final _present = StreamController<Set<String>>.broadcast();
  final List<(String, Map<String, Object?>)> sent = [];
  bool joined = false;

  @override
  Stream<ConvoyMessage> get messages => _messages.stream;
  @override
  Stream<Set<String>> get present => _present.stream;
  @override
  Set<String> get presentNow => const {};

  @override
  Future<void> join() async => joined = true;
  @override
  Future<void> leave() async => joined = false;

  @override
  Future<void> send(
    String type,
    Map<String, Object?> payload, {
    String? to,
  }) async => sent.add((type, payload));

  void inject(ConvoyMessage m) => _messages.add(m);

  Future<void> close() async {
    await _messages.close();
    await _present.close();
  }
}

Fix _fix(int t, double lat, double lon) =>
    Fix(t: t, lat: lat, lon: lon, accuracy: 5, speed: 20, heading: 90);

void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  late FakeConvoyChannel channel;
  late LoopbackDataBus bus;
  late PeerPositionHub hub;
  late int now;
  late ConvoyPositionLink link;

  setUp(() {
    db = memoryDatabase();
    channel = FakeConvoyChannel('c1');
    bus = LoopbackDataBus('me', now: () => now);
    hub = PeerPositionHub();
    now = 1000000;
    link = ConvoyPositionLink(
      convoyId: 'c1',
      me: 'me',
      channel: channel,
      bus: bus,
      hub: hub,
      db: db,
      now: () => now,
    );
  });
  tearDown(() async {
    await link.dispose();
    await channel.close();
    hub.dispose();
    await db.close();
  });

  test('my fixes broadcast every 15 s only while the mesh is down', () async {
    await link.onFix(_fix(now, 40, -100));
    expect(channel.sent.map((s) => s.$1), ['pos']);
    expect(hub.latest['me']?.lat, 40);

    now += 5000;
    await link.onFix(_fix(now, 40.001, -100));
    expect(channel.sent.length, 1, reason: 'throttled');

    now += 11000;
    await link.onFix(_fix(now, 40.002, -100));
    expect(channel.sent.length, 2);

    bus.connect('peer');
    now += 20000;
    await link.onFix(_fix(now, 40.003, -100));
    expect(channel.sent.length, 2, reason: 'mesh up: no broadcast');
    expect(hub.latest['me']?.lat, 40.003, reason: 'still in the hub');
  }, skip: skip);

  test('broadcast and mesh positions land in the hub', () async {
    link.onChannelMessage(
      ConvoyMessage(
        type: 'pos',
        from: 'p1',
        t: now,
        payload: {'lat': 41.0, 'lon': -101.0, 'speed': 10},
      ),
    );
    link.onBusMessage(
      DataMessage(
        type: 'pos',
        from: 'p2',
        t: now,
        payload: {'lat': 42.0, 'lon': -102.0},
      ),
    );
    expect(hub.latest['p1']?.source, PositionSource.broadcast);
    expect(hub.latest['p2']?.source, PositionSource.mesh);
    expect(hub.latest['p1']?.speed, 10);
  }, skip: skip);

  test('a mesh frame the bus already pushed is not pushed again', () async {
    // MeshDataBus pushes every pos frame into the hub with the GPS fix time
    // before the link sees it; the link must agree on that timestamp or the
    // same fix lands twice with a later (send) time.
    final fixT = now - 2000;
    hub.push(
      PeerPosition.fromPayload('p2', fixT, {
        'lat': 42.0,
        'lon': -102.0,
      }, PositionSource.mesh)!,
    );
    var updates = 0;
    final sub = hub.stream.listen((_) => updates++);
    link.onBusMessage(
      DataMessage(
        type: 'pos',
        from: 'p2',
        t: now,
        payload: {'fixT': fixT, 'lat': 42.0, 'lon': -102.0},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(hub.latest['p2']?.t, fixT, reason: 'fix time, not send time');
    expect(updates, 0, reason: 'same fix: no second hub update');
    await sub.cancel();
  }, skip: skip);

  test('etas from both transports are kept per user', () async {
    final seen = <Map<String, EtaInfo>>[];
    final sub = link.etaStream.listen(seen.add);
    link.onChannelMessage(
      ConvoyMessage(
        type: 'eta',
        from: 'p1',
        t: now,
        payload: {'seconds': 600, 'estimated': true},
      ),
    );
    link.onBusMessage(
      DataMessage(
        type: 'eta',
        from: 'p2',
        t: now,
        payload: {'seconds': 120, 'estimated': false, 'toStopId': 's1'},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(link.etas['p1']?.label, '10 min');
    expect(link.etas['p2']?.toStopId, 's1');
    expect(seen.length, 2);
    await sub.cancel();
  }, skip: skip);

  test('publishEta prefers the mesh when peers are connected', () async {
    final e = EtaInfo(userId: 'me', seconds: 300, estimated: false, at: now);
    await link.publishEta(e);
    expect(channel.sent.map((s) => s.$1), ['eta']);
    bus.connect('peer');
    await link.publishEta(e);
    expect(channel.sent.length, 1);
    expect(bus.sent.map((m) => m.type), ['eta']);
  }, skip: skip);

  test('hub updates are written to ConvoyTracks at most every 10 s', () async {
    Future<void> push(String id, int t, double lat) async {
      hub.push(
        PeerPosition(
          userId: id,
          t: t,
          lat: lat,
          lon: -100,
          source: PositionSource.mesh,
        ),
      );
      await link.onHubUpdate(hub.latest);
    }

    await push('p1', now, 40.0);
    await push('p1', now + 3000, 40.001); // too soon
    await push('p1', now + 10000, 40.002);
    await push('p2', now + 10000, 50.0);
    final rows = await db.convoyTracksFor('c1');
    expect(rows.length, 3);
    expect(rows.where((r) => r.userId == 'p1').map((r) => r.lat), [
      40.0,
      40.002,
    ]);

    // A restart picks up the last stored time per peer.
    final again = ConvoyPositionLink(
      convoyId: 'c1',
      me: 'me',
      channel: channel,
      bus: bus,
      hub: hub,
      db: db,
      now: () => now,
    );
    await again.start(const Stream.empty());
    hub.push(
      PeerPosition(
        userId: 'p1',
        t: now + 12000,
        lat: 40.003,
        lon: -100,
        source: PositionSource.mesh,
      ),
    );
    await again.onHubUpdate(hub.latest);
    expect((await db.convoyTracksFor('c1')).length, 3, reason: 'throttled');
    await again.dispose();

    expect(await db.purgeOldConvoyTracks(now + 5000), 1);
    final latest = await db.convoyTrackLatest('c1');
    expect(latest['p1'], now + 10000);
  }, skip: skip);
}
