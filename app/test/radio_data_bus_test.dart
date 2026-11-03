import 'dart:convert';

import 'package:drivalry/features/convoy/positions/peer_positions.dart';
import 'package:drivalry/features/convoy/radio/data_bus.dart';
import 'package:drivalry/features/convoy/radio/mesh.dart';
import 'package:drivalry/features/convoy/radio/mesh_data_bus.dart';
import 'package:drivalry/features/convoy/radio/peer_link.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/radio_fakes.dart';

void main() {
  late FakeConvoyChannel channel;
  late FakePeerLinkFactory factory;
  late ConvoyMesh mesh;

  setUp(() async {
    channel = FakeConvoyChannel('c1', present: {'a', 'b', 'c'});
    factory = FakePeerLinkFactory();
    mesh = ConvoyMesh(
      selfId: 'b',
      channel: channel,
      linkFactory: factory,
      audio: FakeLocalAudio(),
      iceServers: const [],
      now: () => 0,
      tickInterval: const Duration(hours: 1),
    );
    await mesh.join();
    factory.links['a']!.emit(const LinkDataOpen());
    factory.links['c']!.emit(const LinkDataOpen());
    await settle();
  });

  tearDown(() async {
    await mesh.dispose();
    channel.dispose();
  });

  test('send fans out v1 JSON frames, or to one peer', () async {
    final bus = MeshDataBus(mesh, now: () => 42);
    bus.send('eta', {'seconds': 90});
    expect(factory.links['a']!.sentTexts, hasLength(1));
    expect(factory.links['c']!.sentTexts, hasLength(1));
    final frame = jsonDecode(factory.links['a']!.sentTexts.single) as Map;
    expect(frame, {'v': 1, 'type': 'eta', 't': 42, 'seconds': 90});
    bus.send('game', {'x': 1}, to: 'c');
    expect(factory.links['a']!.sentTexts, hasLength(1));
    expect(factory.links['c']!.sentTexts, hasLength(2));
    expect(bus.connectedPeers, {'a', 'c'});
    await bus.dispose();
  });

  test('oversize frames are dropped, not sent', () async {
    final bus = MeshDataBus(mesh);
    bus.send('voice', {'bytes': 'x' * (17 * 1024)});
    expect(factory.links['a']!.sentTexts, isEmpty);
    expect(bus.dropped, 1);
    await bus.dispose();
  });

  test(
    'incoming frames are parsed, pos goes to the hub, junk is dropped',
    () async {
      final hub = PeerPositionHub();
      final bus = MeshDataBus(mesh, hub: hub);
      final got = <DataMessage>[];
      bus.messages.listen(got.add);
      final link = factory.links['a']!;
      link.emit(
        LinkDataText(
          jsonEncode({
            'v': 1,
            'type': 'pos',
            't': 1000,
            'fixT': 900,
            'lat': 38.9,
            'lon': -77.0,
            'speed': 12.5,
          }),
        ),
      );
      link.emit(const LinkDataText('not json'));
      link.emit(const LinkDataText('{"v":2,"type":"pos"}'));
      link.emit(const LinkDataText('{"v":1,"type":"dj","t":5,"cmd":"play"}'));
      await settle();
      expect(got.map((m) => m.type), ['pos', 'dj']);
      expect(got.first.payload['lat'], 38.9);
      expect(got.first.payload.containsKey('v'), isFalse);
      expect(got.last.payload, {'cmd': 'play'});
      expect(bus.dropped, 2);
      final p = hub.latest['a']!;
      expect(p.t, 900, reason: 'fixT wins over the frame time');
      expect(p.source, PositionSource.mesh);
      expect(p.speed, 12.5);
      await bus.dispose();
      hub.dispose();
    },
  );

  test('registry decides what convoyDataBusProvider returns', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(convoyDataBusProvider('c1')), isA<NoopDataBus>());
    final bus = MeshDataBus(mesh);
    container.read(radioBusRegistryProvider.notifier).register('c1', bus);
    expect(container.read(convoyDataBusProvider('c1')), same(bus));
    expect(container.read(convoyDataBusProvider('other')), isA<NoopDataBus>());
    container.read(radioBusRegistryProvider.notifier).unregister('c1');
    expect(container.read(convoyDataBusProvider('c1')), isA<NoopDataBus>());
    await bus.dispose();
  });
}
