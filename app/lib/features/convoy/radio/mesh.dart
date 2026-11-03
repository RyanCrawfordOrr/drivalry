import 'dart:async';

import 'package:flutter/foundation.dart';

import '../channel/convoy_channel.dart';
import '../channel/safe_send.dart';
import 'mesh_plan.dart';
import 'peer_link.dart';
import 'signaling.dart';

/// What the UI and the data bus see for one peer.
class PeerStatus {
  const PeerStatus({
    required this.peerId,
    required this.offerer,
    this.state = LinkState.connecting,
    this.dataOpen = false,
    this.relayed = false,
    this.bytesSent = 0,
    this.bytesReceived = 0,
  });

  final String peerId;
  final bool offerer;
  final LinkState state;
  final bool dataOpen;
  final bool relayed;
  final int bytesSent;
  final int bytesReceived;

  PeerStatus copyWith({
    LinkState? state,
    bool? dataOpen,
    bool? relayed,
    int? bytesSent,
    int? bytesReceived,
  }) => PeerStatus(
    peerId: peerId,
    offerer: offerer,
    state: state ?? this.state,
    dataOpen: dataOpen ?? this.dataOpen,
    relayed: relayed ?? this.relayed,
    bytesSent: bytesSent ?? this.bytesSent,
    bytesReceived: bytesReceived ?? this.bytesReceived,
  );
}

/// A text frame received on a peer's data channel.
class DataFrame {
  const DataFrame(this.from, this.text);
  final String from;
  final String text;
}

/// The full mesh for one convoy (docs/10 §4): one [PeerLink] per other car,
/// signaling over the [ConvoyChannel], decisions from [MeshPlan].
class ConvoyMesh {
  ConvoyMesh({
    required this.selfId,
    required this.channel,
    required this.linkFactory,
    required this.audio,
    required this.iceServers,
    int Function()? now,
    this.tickInterval = const Duration(seconds: 1),
    this.statsEvery = 10,
    MeshPlan? plan,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       plan = plan ?? MeshPlan(selfId);

  final String selfId;
  final ConvoyChannel channel;
  final PeerLinkFactory linkFactory;
  final LocalAudio audio;
  final List<Map<String, Object?>> iceServers;
  final int Function() _now;
  final Duration tickInterval;

  /// Poll `getStats` every this many ticks.
  final int statsEvery;
  final MeshPlan plan;

  final Map<String, PeerLink> _links = {};
  final Map<String, StreamSubscription<PeerLinkEvent>> _linkSubs = {};
  final Map<String, PeerStatus> _status = {};
  final Map<String, int> _relayedBytesSeen = {};
  final _peers = StreamController<Map<String, PeerStatus>>.broadcast();
  final _frames = StreamController<DataFrame>.broadcast();
  final _openPeers = StreamController<Set<String>>.broadcast();
  final _relayedDelta = StreamController<int>.broadcast();
  StreamSubscription<ConvoyMessage>? _msgSub;
  StreamSubscription<Set<String>>? _presenceSub;
  Timer? _tick;
  int _ticks = 0;
  bool _joined = false;
  bool _incomingMuted = false;

  bool get joined => _joined;
  Map<String, PeerStatus> get peersNow => Map.unmodifiable(_status);
  Stream<Map<String, PeerStatus>> get peers => _peers.stream;
  Stream<DataFrame> get frames => _frames.stream;
  Set<String> get openDataPeers => {
    for (final s in _status.values)
      if (s.dataOpen) s.peerId,
  };
  Stream<Set<String>> get openDataPeersStream => _openPeers.stream;

  /// Newly observed relayed bytes (sent + received), for the stats ledger.
  Stream<int> get relayedBytesDelta => _relayedDelta.stream;

  Future<void> join() async {
    if (_joined) return;
    _joined = true;
    await channel.join();
    _msgSub = channel.messages.listen(_onMessage);
    _presenceSub = channel.present.listen(
      (present) => _apply(plan.onPresence(present, _now())),
    );
    await _apply(plan.onJoined(channel.presentNow, _now()));
    await channel.sendHello();
    _tick = Timer.periodic(tickInterval, (_) => _onTick());
  }

  Future<void> leave() async {
    if (!_joined) return;
    _joined = false;
    _tick?.cancel();
    _tick = null;
    try {
      await channel.sendBye();
    } catch (_) {}
    // Broadcast-stream cancels and closes take effect synchronously; awaiting
    // them can stall under a fake event loop, so nothing below waits on one.
    unawaited(_msgSub?.cancel());
    unawaited(_presenceSub?.cancel());
    await _apply(plan.onLeave());
    await channel.leave();
  }

  /// Force an ICE restart on one peer (the "Reconnect" button). The offerer
  /// side restarts; the other side asks the offerer by re-sending hello.
  Future<void> reconnect(String peerId) async {
    if (!_links.containsKey(peerId)) return;
    if (plan.isOfferer(peerId)) {
      await _apply([MeshAction(MeshActionKind.restart, peerId)]);
    } else {
      await safeSend('hello', channel.sendHello);
    }
  }

  /// Sends one frame to one peer or to everyone with an open channel.
  bool sendText(String text, {String? to}) {
    if (to != null) return _links[to]?.sendText(text) ?? false;
    var any = false;
    for (final link in _links.values) {
      if (link.sendText(text)) any = true;
    }
    return any;
  }

  set incomingMuted(bool value) {
    _incomingMuted = value;
    for (final link in _links.values) {
      link.incomingMuted = value;
    }
  }

  bool get incomingMuted => _incomingMuted;

  Future<void> dispose() async {
    await leave();
    unawaited(_peers.close());
    unawaited(_frames.close());
    unawaited(_openPeers.close());
    unawaited(_relayedDelta.close());
  }

  // ----------------------------------------------------------------------

  Future<void> _onMessage(ConvoyMessage m) async {
    try {
      switch (m.type) {
        case RadioSignal.hello:
          await _apply(plan.onHello(m.from, _now()));
        case RadioSignal.bye:
          await _apply(plan.onBye(m.from));
        case RadioSignal.offer:
          final sdp = m.sdp;
          if (sdp == null) return;
          if (!_links.containsKey(m.from)) {
            await _apply(plan.onUnsolicitedOffer(m.from, _now()));
          }
          final link = _links[m.from];
          if (link == null || plan.isOfferer(m.from)) return; // glare guard
          final answer = await link.createAnswer(sdp);
          await channel.sendAnswer(m.from, answer);
        case RadioSignal.answer:
          final sdp = m.sdp;
          final link = _links[m.from];
          if (sdp == null || link == null) return;
          await link.setRemoteAnswer(sdp);
        case RadioSignal.ice:
          final c = m.iceCandidate;
          final link = _links[m.from];
          if (c == null || link == null) return;
          await link.addIceCandidate(c);
        default:
          break;
      }
    } catch (e) {
      debugPrint('mesh: ${m.type} from ${m.from} failed: $e');
    }
  }

  Future<void> _apply(List<MeshAction> actions) async {
    for (final a in actions) {
      try {
        switch (a.kind) {
          case MeshActionKind.offer:
            final link = await _open(a.peerId, offerer: true);
            final sdp = await link.createOffer();
            await channel.sendOffer(a.peerId, sdp);
          case MeshActionKind.await_:
            await _open(a.peerId, offerer: false);
          case MeshActionKind.remove:
            await _close(a.peerId);
          case MeshActionKind.restart:
            final link = _links[a.peerId];
            if (link == null) break;
            final sdp = await link.restartIce();
            await channel.sendOffer(a.peerId, sdp);
        }
      } catch (e) {
        debugPrint('mesh: ${a.kind.name} ${a.peerId} failed: $e');
      }
    }
  }

  Future<PeerLink> _open(String peerId, {required bool offerer}) async {
    await _close(peerId, forget: false);
    final link = await linkFactory.create(
      peerId,
      offerer: offerer,
      iceServers: iceServers,
      audio: audio,
    );
    link.incomingMuted = _incomingMuted;
    _links[peerId] = link;
    _status[peerId] = PeerStatus(peerId: peerId, offerer: offerer);
    _linkSubs[peerId] = link.events.listen((e) => _onLinkEvent(peerId, e));
    _emitPeers();
    return link;
  }

  Future<void> _close(String peerId, {bool forget = true}) async {
    final link = _links.remove(peerId);
    unawaited(_linkSubs.remove(peerId)?.cancel());
    if (link != null) {
      try {
        await link.close();
      } catch (_) {}
    }
    if (forget) {
      final had = _status.remove(peerId) != null;
      _relayedBytesSeen.remove(peerId);
      if (had) {
        _emitPeers();
        _openPeers.add(openDataPeers);
      }
    }
  }

  void _onLinkEvent(String peerId, PeerLinkEvent e) {
    final cur = _status[peerId];
    if (cur == null) return;
    switch (e) {
      case LinkIceCandidate(:final candidate):
        unawaited(safeSend('ice', () => channel.sendIce(peerId, candidate)));
      case LinkStateChanged(:final state):
        _status[peerId] = cur.copyWith(state: state);
        plan.onHealth(peerId, switch (state) {
          LinkState.connected => LinkHealth.connected,
          LinkState.connecting => LinkHealth.connecting,
          LinkState.disconnected => LinkHealth.stalled,
          LinkState.failed || LinkState.closed => LinkHealth.failed,
        }, _now());
        _emitPeers();
      case LinkDataOpen():
        _status[peerId] = cur.copyWith(dataOpen: true);
        _emitPeers();
        _openPeers.add(openDataPeers);
      case LinkDataClosed():
        _status[peerId] = cur.copyWith(dataOpen: false);
        _emitPeers();
        _openPeers.add(openDataPeers);
      case LinkDataText(:final text):
        _frames.add(DataFrame(peerId, text));
      case LinkStats(:final relayed, :final bytesSent, :final bytesReceived):
        _status[peerId] = cur.copyWith(
          relayed: relayed,
          bytesSent: bytesSent,
          bytesReceived: bytesReceived,
        );
        if (relayed) {
          final total = bytesSent + bytesReceived;
          final seen = _relayedBytesSeen[peerId] ?? 0;
          if (total > seen) {
            _relayedDelta.add(total - seen);
            _relayedBytesSeen[peerId] = total;
          }
        }
        _emitPeers();
    }
  }

  void _onTick() {
    _ticks++;
    _apply(plan.onTick(_now()));
    if (_ticks % statsEvery == 0) {
      for (final link in _links.values) {
        link.pollStats().catchError((_) {});
      }
    }
  }

  void _emitPeers() {
    if (!_peers.isClosed) _peers.add(peersNow);
  }
}
