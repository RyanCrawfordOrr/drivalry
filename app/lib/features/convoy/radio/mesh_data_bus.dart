import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../positions/peer_positions.dart';
import 'data_bus.dart';
import 'mesh.dart';

/// [ConvoyDataBus] over the WebRTC mesh (docs/10 §5). Frames are JSON
/// objects `{v:1, type, t, ...}` under 16 KB. Incoming `pos` frames are also
/// pushed into the convoy's [PeerPositionHub].
class MeshDataBus implements ConvoyDataBus {
  MeshDataBus(this._mesh, {this.hub, int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch) {
    _sub = _mesh.frames.listen(_onFrame);
  }

  static const maxBytes = 16 * 1024;

  final ConvoyMesh _mesh;
  final PeerPositionHub? hub;
  final int Function() _now;
  final _messages = StreamController<DataMessage>.broadcast();
  StreamSubscription<DataFrame>? _sub;

  /// Frames dropped for being oversize or unparsable, for diagnostics.
  int dropped = 0;

  @override
  Stream<DataMessage> get messages => _messages.stream;

  @override
  Set<String> get connectedPeers => _mesh.openDataPeers;

  @override
  Stream<Set<String>> get connectedPeersStream => _mesh.openDataPeersStream;

  @override
  void send(String type, Map<String, Object?> payload, {String? to}) {
    final text = jsonEncode({'v': 1, 'type': type, 't': _now(), ...payload});
    if (text.length > maxBytes) {
      dropped++;
      debugPrint('data bus: dropping oversize $type frame (${text.length} B)');
      return;
    }
    _mesh.sendText(text, to: to);
  }

  void _onFrame(DataFrame f) {
    final m = parse(f.from, f.text);
    if (m == null) {
      dropped++;
      return;
    }
    if (m.type == 'pos') {
      final fixT = (m.payload['fixT'] as num?)?.toInt() ?? m.t;
      final p = PeerPosition.fromPayload(
        m.from,
        fixT,
        m.payload,
        PositionSource.mesh,
      );
      if (p != null) hub?.push(p);
    }
    _messages.add(m);
  }

  /// Parses one frame; null when it is not a v1 message.
  static DataMessage? parse(String from, String text) {
    if (text.length > maxBytes) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['v'] != 1) return null;
    final type = decoded['type'];
    if (type is! String) return null;
    final payload = Map<String, dynamic>.from(decoded)
      ..remove('v')
      ..remove('type')
      ..remove('t');
    return DataMessage(
      type: type,
      from: from,
      t: (decoded['t'] as num?)?.toInt() ?? 0,
      payload: payload,
    );
  }

  Future<void> dispose() async {
    unawaited(_sub?.cancel());
    unawaited(_messages.close());
  }
}

/// Which convoys currently have a live mesh bus. The radio registers its
/// bus while running; `convoyDataBusProvider` reads this so every feature
/// sees the mesh when there is one and [NoopDataBus] otherwise.
class RadioBusRegistry extends Notifier<Map<String, ConvoyDataBus>> {
  @override
  Map<String, ConvoyDataBus> build() => const {};

  void register(String convoyId, ConvoyDataBus bus) {
    state = {...state, convoyId: bus};
  }

  void unregister(String convoyId) {
    if (!state.containsKey(convoyId)) return;
    state = {...state}..remove(convoyId);
  }
}

final radioBusRegistryProvider =
    NotifierProvider<RadioBusRegistry, Map<String, ConvoyDataBus>>(
      RadioBusRegistry.new,
    );
