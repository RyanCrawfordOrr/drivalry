/// The slice of WebRTC the mesh needs, behind an interface so the mesh can
/// be tested with fakes and the real implementation stays in one file
/// (`webrtc_peer_link.dart`).
library;

import 'dart:async';

/// An ICE candidate as it travels over signaling.
class IceCandidateData {
  const IceCandidateData({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  Map<String, Object?> toJson() => {
    'candidate': candidate,
    'sdpMid': ?sdpMid,
    'sdpMLineIndex': ?sdpMLineIndex,
  };

  static IceCandidateData? fromJson(Object? v) {
    if (v is! Map) return null;
    final c = v['candidate'];
    if (c is! String) return null;
    return IceCandidateData(
      candidate: c,
      sdpMid: v['sdpMid'] as String?,
      sdpMLineIndex: (v['sdpMLineIndex'] as num?)?.toInt(),
    );
  }
}

/// Something a link reports back to the mesh.
sealed class PeerLinkEvent {
  const PeerLinkEvent();
}

final class LinkIceCandidate extends PeerLinkEvent {
  const LinkIceCandidate(this.candidate);
  final IceCandidateData candidate;
}

/// Coarse connection state, derived from the ICE and peer connection states.
enum LinkState { connecting, connected, disconnected, failed, closed }

final class LinkStateChanged extends PeerLinkEvent {
  const LinkStateChanged(this.state);
  final LinkState state;
}

final class LinkDataOpen extends PeerLinkEvent {
  const LinkDataOpen();
}

final class LinkDataClosed extends PeerLinkEvent {
  const LinkDataClosed();
}

final class LinkDataText extends PeerLinkEvent {
  const LinkDataText(this.text);
  final String text;
}

/// Snapshot from `getStats`: whether the selected candidate pair is relayed
/// (TURN) and the byte counters on it.
final class LinkStats extends PeerLinkEvent {
  const LinkStats({
    required this.relayed,
    required this.bytesSent,
    required this.bytesReceived,
  });
  final bool relayed;
  final int bytesSent;
  final int bytesReceived;
}

/// One peer connection plus its `drivalry` data channel.
abstract class PeerLink {
  String get peerId;
  Stream<PeerLinkEvent> get events;
  bool get dataOpen;

  /// Offerer side: creates the data channel, the offer, sets it locally.
  Future<String> createOffer();

  /// Offerer side: applies the peer's answer.
  Future<void> setRemoteAnswer(String sdp);

  /// Answerer side: applies the offer, creates and sets the answer.
  Future<String> createAnswer(String offerSdp);

  Future<void> addIceCandidate(IceCandidateData candidate);

  /// Offerer side: ICE restart followed by a new offer (returned).
  Future<String> restartIce();

  /// Sends one text frame on the data channel; false when it is not open.
  bool sendText(String text);

  /// Polls stats; the link emits a [LinkStats] event when available.
  Future<void> pollStats();

  /// Mutes or unmutes what we hear from this peer (their track stays live).
  set incomingMuted(bool value);

  Future<void> close();
}

/// The one local microphone track shared by every link.
abstract class LocalAudio {
  /// Opens the microphone (prompts for permission on first use). The track
  /// starts muted.
  Future<void> acquire();

  bool get acquired;
  bool get muted;
  set muted(bool value);

  Future<void> release();
}

/// Creates links. The real one wraps `createPeerConnection`; tests inject
/// fakes.
abstract class PeerLinkFactory {
  Future<PeerLink> create(
    String peerId, {
    required bool offerer,
    required List<Map<String, Object?>> iceServers,
    required LocalAudio audio,
  });
}
