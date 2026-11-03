import 'dart:async';

import 'package:drivalry/features/convoy/channel/convoy_channel.dart';
import 'package:drivalry/features/convoy/radio/peer_link.dart';

/// In-memory convoy channel: records what was sent, lets tests inject
/// messages and presence.
class FakeConvoyChannel implements ConvoyChannel {
  FakeConvoyChannel(this.convoyId, {Set<String> present = const {}})
    : _presentNow = present;

  @override
  final String convoyId;
  final _messages = StreamController<ConvoyMessage>.broadcast();
  final _present = StreamController<Set<String>>.broadcast();
  Set<String> _presentNow;
  final List<({String type, Map<String, Object?> payload, String? to})> sent =
      [];
  int joins = 0;
  int leaves = 0;

  @override
  Stream<ConvoyMessage> get messages => _messages.stream;

  @override
  Stream<Set<String>> get present => _present.stream;

  @override
  Set<String> get presentNow => _presentNow;

  @override
  Future<void> join() async => joins++;

  @override
  Future<void> leave() async => leaves++;

  @override
  Future<void> send(
    String type,
    Map<String, Object?> payload, {
    String? to,
  }) async {
    sent.add((type: type, payload: payload, to: to));
  }

  Iterable<String> sentTypes() => sent.map((s) => s.type);

  void inject(
    String type,
    String from, {
    Map<String, dynamic> payload = const {},
    String? to,
    int t = 0,
  }) {
    _messages.add(
      ConvoyMessage(type: type, from: from, t: t, to: to, payload: payload),
    );
  }

  void setPresent(Set<String> ids) {
    _presentNow = ids;
    _present.add(ids);
  }

  void dispose() {
    _messages.close();
    _present.close();
  }
}

class FakeLocalAudio implements LocalAudio {
  bool _acquired = false;
  bool _muted = true;
  int releases = 0;

  @override
  bool get acquired => _acquired;

  @override
  Future<void> acquire() async => _acquired = true;

  @override
  bool get muted => _muted;

  @override
  set muted(bool value) => _muted = value;

  @override
  Future<void> release() async {
    _acquired = false;
    releases++;
  }
}

class FakePeerLink implements PeerLink {
  FakePeerLink(this.peerId, {required this.offerer});

  @override
  final String peerId;
  final bool offerer;
  final _events = StreamController<PeerLinkEvent>.broadcast();
  final List<String> calls = [];
  final List<IceCandidateData> ice = [];
  final List<String> sentTexts = [];
  bool _dataOpen = false;
  bool incomingMutedValue = false;
  bool closed = false;

  @override
  Stream<PeerLinkEvent> get events => _events.stream;

  @override
  bool get dataOpen => _dataOpen;

  @override
  Future<String> createOffer() async {
    calls.add('offer');
    return 'offer-from-$peerId-link';
  }

  @override
  Future<void> setRemoteAnswer(String sdp) async => calls.add('answer:$sdp');

  @override
  Future<String> createAnswer(String offerSdp) async {
    calls.add('createAnswer:$offerSdp');
    return 'answer-sdp';
  }

  @override
  Future<void> addIceCandidate(IceCandidateData candidate) async =>
      ice.add(candidate);

  @override
  Future<String> restartIce() async {
    calls.add('restart');
    return 'restart-offer';
  }

  @override
  bool sendText(String text) {
    if (!_dataOpen) return false;
    sentTexts.add(text);
    return true;
  }

  @override
  Future<void> pollStats() async => calls.add('stats');

  @override
  set incomingMuted(bool value) => incomingMutedValue = value;

  @override
  Future<void> close() async {
    closed = true;
    calls.add('close');
    unawaited(_events.close());
  }

  void emit(PeerLinkEvent e) {
    if (e is LinkDataOpen) _dataOpen = true;
    if (e is LinkDataClosed) _dataOpen = false;
    if (!_events.isClosed) _events.add(e);
  }
}

class FakePeerLinkFactory implements PeerLinkFactory {
  final Map<String, FakePeerLink> links = {};
  final List<String> created = [];

  @override
  Future<PeerLink> create(
    String peerId, {
    required bool offerer,
    required List<Map<String, Object?>> iceServers,
    required LocalAudio audio,
  }) async {
    final link = FakePeerLink(peerId, offerer: offerer);
    links[peerId] = link;
    created.add(peerId);
    return link;
  }
}

/// Lets the event loop run pending microtasks and timers queued so far.
Future<void> settle() => Future<void>.delayed(Duration.zero);
