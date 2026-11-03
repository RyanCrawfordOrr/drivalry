import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../features/convoy/channel/convoy_channel.dart';
import '../../features/convoy/channel/safe_send.dart';
import '../../features/convoy/positions/peer_positions.dart';
import '../../features/convoy/radio/data_bus.dart';
import '../../tracking/tracking_models.dart';
import '../db/database.dart';
import 'eta.dart';

/// Ties the three position transports to the hub for one convoy (docs/10
/// §3, §5):
///
/// - my own fixes go out as broadcast `pos` every [fallbackInterval], but
///   **only while the data bus has no connected peers** (the mesh carries
///   positions when it is up);
/// - incoming broadcast `pos` and data-bus `pos` land in the hub;
/// - every hub update is written to `ConvoyTracks` at most once per peer per
///   [trackInterval], for the recap;
/// - `eta` messages from either transport are kept in [etas].
///
/// Everything is driven by [onFix], [onChannelMessage], [onBusMessage] and
/// [onHubUpdate], so it is testable with fakes and a fake clock.
class ConvoyPositionLink {
  ConvoyPositionLink({
    required this.convoyId,
    required this.me,
    required this.channel,
    required this.bus,
    required this.hub,
    required this.db,
    required this.now,
    this.fallbackInterval = const Duration(seconds: 15),
    this.trackInterval = const Duration(seconds: 10),
  });

  final String convoyId;
  final String me;
  final ConvoyChannel channel;
  final ConvoyDataBus bus;
  final PeerPositionHub hub;
  final AppDatabase db;
  final int Function() now;
  final Duration fallbackInterval;
  final Duration trackInterval;

  final Map<String, EtaInfo> etas = {};
  final _etaController = StreamController<Map<String, EtaInfo>>.broadcast();
  Stream<Map<String, EtaInfo>> get etaStream => _etaController.stream;

  int? _lastFallbackSentAt;
  final Map<String, int> _lastTrackAt = {};
  int broadcastsSent = 0;

  final List<StreamSubscription<Object?>> _subs = [];

  /// Wires the live streams. Call once; [dispose] undoes it.
  Future<void> start(Stream<TrackingEvent> fixes) async {
    _lastTrackAt.addAll(await db.convoyTrackLatest(convoyId));
    _subs.add(channel.messages.listen(onChannelMessage));
    _subs.add(bus.messages.listen(onBusMessage));
    _subs.add(hub.stream.listen(onHubUpdate));
    _subs.add(fixes.listen(onEvent));
  }

  void onEvent(TrackingEvent e) {
    if (e is FixesEvent && e.fixes.isNotEmpty) {
      unawaited(onFix(e.fixes.last));
    } else if (e is ParkedFixEvent) {
      unawaited(
        onFix(
          Fix(
            t: e.t,
            lat: e.lat,
            lon: e.lon,
            accuracy: e.accuracy,
            speed: e.speed,
            heading: e.heading,
          ),
        ),
      );
    }
  }

  /// My own position: into the hub (so the map shows me) and, when the mesh
  /// is down, out over the channel every [fallbackInterval].
  Future<void> onFix(Fix f, {double? battery}) async {
    final p = PeerPosition(
      userId: me,
      t: f.t,
      lat: f.lat,
      lon: f.lon,
      speed: f.speed,
      heading: f.heading,
      accuracy: f.accuracy,
      battery: battery,
      source: PositionSource.mesh,
    );
    hub.push(p);
    if (bus.connectedPeers.isNotEmpty) return;
    final t = now();
    if (_lastFallbackSentAt != null &&
        t - _lastFallbackSentAt! < fallbackInterval.inMilliseconds) {
      return;
    }
    _lastFallbackSentAt = t;
    broadcastsSent++;
    await safeSend('pos broadcast', () => channel.send('pos', p.toJson()));
  }

  void onChannelMessage(ConvoyMessage m) {
    switch (m.type) {
      case 'pos':
        final p = PeerPosition.fromPayload(
          m.from,
          m.t,
          m.payload,
          PositionSource.broadcast,
        );
        if (p != null) hub.push(p);
      case 'eta':
        final e = EtaInfo.fromPayload(m.from, m.t, m.payload);
        if (e != null) _setEta(e);
      default:
        break;
    }
  }

  void onBusMessage(DataMessage m) {
    switch (m.type) {
      case 'pos':
        // The mesh bus already pushed this frame with the fix time; using the
        // same timestamp here makes the hub ignore the duplicate instead of
        // overwriting it with the (later) send time.
        final fixT = (m.payload['fixT'] as num?)?.toInt() ?? m.t;
        final p = PeerPosition.fromPayload(
          m.from,
          fixT,
          m.payload,
          PositionSource.mesh,
        );
        if (p != null) hub.push(p);
      case 'eta':
        final e = EtaInfo.fromPayload(m.from, m.t, m.payload);
        if (e != null) _setEta(e);
      default:
        break;
    }
  }

  void _setEta(EtaInfo e) {
    etas[e.userId] = e;
    _etaController.add(Map.unmodifiable(etas));
  }

  /// Sends my ETA over the mesh when it is up, otherwise over the channel.
  Future<void> publishEta(EtaInfo e) async {
    _setEta(e);
    if (bus.connectedPeers.isNotEmpty) {
      bus.send('eta', e.toPayload());
    } else {
      await safeSend('eta broadcast', () => channel.send('eta', e.toPayload()));
    }
  }

  /// Persists the newest position per peer, throttled. My own position is
  /// kept too, so my line appears in the recap.
  Future<void> onHubUpdate(Map<String, PeerPosition> latest) async {
    for (final p in latest.values) {
      final last = _lastTrackAt[p.userId];
      if (last != null && p.t - last < trackInterval.inMilliseconds) continue;
      if (last != null && p.t <= last) continue;
      _lastTrackAt[p.userId] = p.t;
      await db.insertConvoyTrack(
        ConvoyTracksCompanion(
          convoyId: Value(convoyId),
          userId: Value(p.userId),
          t: Value(p.t),
          lat: Value(p.lat),
          lon: Value(p.lon),
          speed: Value(p.speed),
          heading: Value(p.heading),
        ),
      );
    }
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _etaController.close();
  }
}
