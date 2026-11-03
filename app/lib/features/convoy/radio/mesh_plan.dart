/// Pure mesh bookkeeping (docs/10-convoy-protocol.md §4), kept free of WebRTC
/// so it can be unit-tested: who offers to whom, when a link is replaced or
/// dropped, and when a stalled link should restart ICE.
library;

/// What the mesh should do next for one peer.
enum MeshActionKind {
  /// Create a link and send an offer (we have the lower user id).
  offer,

  /// Create a link and wait for the peer's offer (they have the lower id).
  await_,

  /// Close and forget the link.
  remove,

  /// Restart ICE on an existing link and send a fresh offer.
  restart,
}

class MeshAction {
  const MeshAction(this.kind, this.peerId);
  final MeshActionKind kind;
  final String peerId;

  @override
  bool operator ==(Object other) =>
      other is MeshAction && other.kind == kind && other.peerId == peerId;

  @override
  int get hashCode => Object.hash(kind, peerId);

  @override
  String toString() => 'MeshAction(${kind.name}, $peerId)';
}

/// Connection health as the plan sees it.
enum LinkHealth { connecting, connected, stalled, failed }

class _Link {
  _Link(this.peerId, {required this.offerer, required this.openedAt});
  final String peerId;
  final bool offerer;
  final int openedAt;
  LinkHealth health = LinkHealth.connecting;

  /// When the link last went stalled/failed, for the restart timer.
  int? stalledAt;
  int restarts = 0;
}

/// Decides, never acts. Feed it presence and signaling events and apply the
/// returned [MeshAction]s to real connections.
///
/// Peers become known two ways, in either order: Realtime presence (which
/// syncs a moment after joining) and their `hello`. Whichever arrives first
/// opens the link; the second is ignored while that link is still young.
class MeshPlan {
  MeshPlan(
    this.selfId, {
    this.restartAfterMs = 10_000,
    this.maxRestarts = 5,
    this.helloGraceMs = 10_000,
  });

  final String selfId;
  final int restartAfterMs;
  final int maxRestarts;

  /// A repeated `hello` from a peer whose link is younger than this and
  /// still connecting is the same join seen twice, not a restart.
  final int helloGraceMs;
  final Map<String, _Link> _links = {};

  Iterable<String> get peers => _links.keys;
  bool has(String peerId) => _links.containsKey(peerId);
  bool isOfferer(String peerId) => _links[peerId]?.offerer ?? false;
  LinkHealth? healthOf(String peerId) => _links[peerId]?.health;

  /// The lower user id creates the offer for a pair.
  bool offersTo(String peerId) => selfId.compareTo(peerId) < 0;

  /// We just joined: one action per peer already present.
  List<MeshAction> onJoined(Set<String> present, int nowMs) => [
    for (final p in present)
      if (p != selfId && !_links.containsKey(p)) _open(p, nowMs),
  ];

  /// A `hello` arrived. A newcomer gets a fresh link. A known peer saying
  /// hello again has restarted, so its link is replaced, unless the link is
  /// young and still connecting (presence beat the hello).
  List<MeshAction> onHello(String from, int nowMs) {
    if (from == selfId) return const [];
    final existing = _links[from];
    if (existing != null) {
      final young = nowMs - existing.openedAt < helloGraceMs;
      if (young && existing.health == LinkHealth.connecting) return const [];
      _links.remove(from);
      return [MeshAction(MeshActionKind.remove, from), _open(from, nowMs)];
    }
    return [_open(from, nowMs)];
  }

  /// An offer arrived from a peer we did not know about yet (their hello was
  /// lost). Accept it by opening an awaiting link.
  List<MeshAction> onUnsolicitedOffer(String from, int nowMs) {
    if (from == selfId || _links.containsKey(from)) return const [];
    _links[from] = _Link(from, offerer: false, openedAt: nowMs);
    return [MeshAction(MeshActionKind.await_, from)];
  }

  List<MeshAction> onBye(String from) => _drop(from);

  /// Presence changed: anyone who vanished is dropped and anyone new is
  /// opened. A set that does not include us is a partial sync (we track our
  /// own presence) and is ignored, so a Realtime hiccup cannot tear the mesh
  /// down.
  List<MeshAction> onPresence(Set<String> present, int nowMs) {
    if (!present.contains(selfId)) return const [];
    return [
      for (final p in _links.keys.toList())
        if (!present.contains(p)) ..._drop(p),
      for (final p in present)
        if (p != selfId && !_links.containsKey(p)) _open(p, nowMs),
    ];
  }

  /// Health report from the real connection.
  void onHealth(String peerId, LinkHealth health, int nowMs) {
    final link = _links[peerId];
    if (link == null) return;
    link.health = health;
    if (health == LinkHealth.stalled || health == LinkHealth.failed) {
      link.stalledAt ??= nowMs;
    } else {
      link.stalledAt = null;
      if (health == LinkHealth.connected) link.restarts = 0;
    }
  }

  /// Periodic tick: links stalled for [restartAfterMs] get an ICE restart
  /// from the offerer side; the other side waits. After [maxRestarts] the
  /// link is dropped and a fresh one will be opened on the next hello or
  /// presence sync.
  List<MeshAction> onTick(int nowMs) {
    final actions = <MeshAction>[];
    for (final link in _links.values.toList()) {
      final since = link.stalledAt;
      if (since == null || nowMs - since < restartAfterMs) continue;
      if (link.restarts >= maxRestarts) {
        actions.addAll(_drop(link.peerId));
        continue;
      }
      link.restarts++;
      link.stalledAt = nowMs; // wait another full period before the next
      if (link.offerer) {
        actions.add(MeshAction(MeshActionKind.restart, link.peerId));
      }
    }
    return actions;
  }

  /// Leaving: everything goes.
  List<MeshAction> onLeave() => [
    for (final p in _links.keys.toList()) ..._drop(p),
  ];

  MeshAction _open(String peerId, int nowMs) {
    final offerer = offersTo(peerId);
    _links[peerId] = _Link(peerId, offerer: offerer, openedAt: nowMs);
    return MeshAction(
      offerer ? MeshActionKind.offer : MeshActionKind.await_,
      peerId,
    );
  }

  List<MeshAction> _drop(String peerId) {
    if (_links.remove(peerId) == null) return const [];
    return [MeshAction(MeshActionKind.remove, peerId)];
  }
}
