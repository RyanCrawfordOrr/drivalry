import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'mesh_data_bus.dart';

/// A message received on the convoy data channel (docs/10 §5).
class DataMessage {
  const DataMessage({
    required this.type,
    required this.from,
    required this.t,
    required this.payload,
  });

  final String type;
  final String from;
  final int t;
  final Map<String, dynamic> payload;
}

/// The car-to-car data channel as seen by features: positions, ETAs, voice
/// notes, games and DJ sync all ride on it. The radio implements it over the
/// WebRTC mesh; tests and offline builds use [LoopbackDataBus].
abstract class ConvoyDataBus {
  Stream<DataMessage> get messages;

  /// Peers with an open data channel right now.
  Set<String> get connectedPeers;
  Stream<Set<String>> get connectedPeersStream;

  /// Sends `{v:1, type, t, ...payload}` to every connected peer, or to one.
  /// Payloads must stay under 16 KB after JSON encoding.
  void send(String type, Map<String, Object?> payload, {String? to});
}

/// A bus with no peers: `send` is a no-op and nothing ever arrives. Lets every
/// convoy screen render without a mesh.
class NoopDataBus implements ConvoyDataBus {
  const NoopDataBus();

  @override
  Stream<DataMessage> get messages => const Stream.empty();

  @override
  Set<String> get connectedPeers => const {};

  @override
  Stream<Set<String>> get connectedPeersStream => const Stream.empty();

  @override
  void send(String type, Map<String, Object?> payload, {String? to}) {}
}

/// In-process bus for tests: every `send` is echoed back as a message from
/// [selfId] (so a single-phone test can watch its own traffic), and peers can
/// be injected with [inject].
class LoopbackDataBus implements ConvoyDataBus {
  LoopbackDataBus(this.selfId, {int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String selfId;
  final int Function() _now;
  final _messages = StreamController<DataMessage>.broadcast();
  final _peers = StreamController<Set<String>>.broadcast();
  final Set<String> _connected = {};
  final List<DataMessage> sent = [];

  @override
  Stream<DataMessage> get messages => _messages.stream;

  @override
  Set<String> get connectedPeers => Set.unmodifiable(_connected);

  @override
  Stream<Set<String>> get connectedPeersStream => _peers.stream;

  @override
  void send(String type, Map<String, Object?> payload, {String? to}) {
    final m = DataMessage(
      type: type,
      from: selfId,
      t: _now(),
      payload: Map<String, dynamic>.from(payload),
    );
    sent.add(m);
    _messages.add(m);
  }

  /// Simulates a message arriving from [from].
  void inject(String from, String type, Map<String, dynamic> payload) {
    _messages.add(
      DataMessage(type: type, from: from, t: _now(), payload: payload),
    );
  }

  void connect(String peer) {
    _connected.add(peer);
    _peers.add(connectedPeers);
  }

  void disconnect(String peer) {
    _connected.remove(peer);
    _peers.add(connectedPeers);
  }

  void dispose() {
    _messages.close();
    _peers.close();
  }
}

/// The live bus for a convoy. The radio overrides this with the mesh-backed
/// implementation while it is running; otherwise features see [NoopDataBus].
final convoyDataBusProvider = Provider.family<ConvoyDataBus, String>(
  (ref, convoyId) =>
      ref.watch(radioBusRegistryProvider)[convoyId] ?? const NoopDataBus(),
);
