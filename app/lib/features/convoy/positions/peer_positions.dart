import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a position came from, best first. The hub keeps the freshest fix per
/// car regardless of source.
enum PositionSource { mesh, broadcast, presence }

/// One car's latest known position inside a convoy.
class PeerPosition {
  const PeerPosition({
    required this.userId,
    required this.t,
    required this.lat,
    required this.lon,
    required this.source,
    this.speed,
    this.heading,
    this.accuracy,
    this.battery,
  });

  final String userId;

  /// Epoch milliseconds when the fix was taken.
  final int t;
  final double lat;
  final double lon;
  final double? speed;
  final double? heading;
  final double? accuracy;

  /// 0–1 when known.
  final double? battery;
  final PositionSource source;

  Map<String, Object?> toJson() => {
    'lat': lat,
    'lon': lon,
    'speed': ?speed,
    'heading': ?heading,
    'acc': ?accuracy,
    'battery': ?battery,
  };

  /// Parses a `pos` payload from the data channel or the broadcast fallback.
  static PeerPosition? fromPayload(
    String userId,
    int t,
    Map<String, dynamic> p,
    PositionSource source,
  ) {
    final lat = p['lat'];
    final lon = p['lon'];
    if (lat is! num || lon is! num) return null;
    return PeerPosition(
      userId: userId,
      t: t,
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      speed: (p['speed'] as num?)?.toDouble(),
      heading: (p['heading'] as num?)?.toDouble(),
      accuracy: (p['acc'] as num?)?.toDouble(),
      battery: (p['battery'] as num?)?.toDouble(),
      source: source,
    );
  }
}

/// Merges positions from every transport into one "latest per car" view.
/// The radio (mesh) and the convoy screen (broadcast fallback, presence) both
/// push into it; the map, ETAs, lost-sheep and the recap read from it.
class PeerPositionHub {
  final Map<String, PeerPosition> _latest = {};
  final _controller = StreamController<Map<String, PeerPosition>>.broadcast();

  Map<String, PeerPosition> get latest => Map.unmodifiable(_latest);

  Stream<Map<String, PeerPosition>> get stream => _controller.stream;

  /// Accepts a position unless an equal-or-newer one is already known.
  void push(PeerPosition p) {
    final cur = _latest[p.userId];
    if (cur != null && cur.t >= p.t) return;
    _latest[p.userId] = p;
    _controller.add(latest);
  }

  void remove(String userId) {
    if (_latest.remove(userId) != null) _controller.add(latest);
  }

  void clear() {
    _latest.clear();
    _controller.add(latest);
  }

  void dispose() => _controller.close();
}

/// One hub per convoy id, alive while something watches it.
final peerPositionHubProvider = Provider.family<PeerPositionHub, String>((
  ref,
  convoyId,
) {
  final hub = PeerPositionHub();
  ref.onDispose(hub.dispose);
  return hub;
});

/// Latest position per car for a convoy, live.
final peerPositionsProvider =
    StreamProvider.family<Map<String, PeerPosition>, String>((ref, convoyId) {
      final hub = ref.watch(peerPositionHubProvider(convoyId));
      return Stream.multi((controller) {
        controller.add(hub.latest);
        final sub = hub.stream.listen(controller.add);
        controller.onCancel = sub.cancel;
      });
    });
