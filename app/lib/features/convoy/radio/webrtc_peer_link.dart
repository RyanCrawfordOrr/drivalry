import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'peer_link.dart';

/// Appends the Opus settings from docs/10 §4 to every `a=fmtp` line of an
/// Opus payload in [sdp]: 24 kbps average, DTX on (silence costs nothing),
/// mono. Pure, so it is unit-tested.
String tuneOpus(String sdp) {
  final lines = sdp.split(RegExp(r'\r?\n'));
  final opusPts = <String>{};
  for (final l in lines) {
    final m = RegExp(
      r'^a=rtpmap:(\d+) opus/48000',
      caseSensitive: false,
    ).firstMatch(l);
    if (m != null) opusPts.add(m.group(1)!);
  }
  if (opusPts.isEmpty) return sdp;
  const extra = 'maxaveragebitrate=24000;usedtx=1;stereo=0;sprop-stereo=0';
  final out = <String>[];
  final seen = <String>{};
  for (final l in lines) {
    final m = RegExp(r'^a=fmtp:(\d+) (.*)$').firstMatch(l);
    if (m != null && opusPts.contains(m.group(1))) {
      seen.add(m.group(1)!);
      var params = m.group(2)!;
      for (final kv in extra.split(';')) {
        final key = kv.split('=').first;
        if (!params.contains('$key=')) params = '$params;$kv';
      }
      out.add('a=fmtp:${m.group(1)} $params');
    } else {
      out.add(l);
    }
  }
  // Opus without an fmtp line: add one after its rtpmap.
  for (final pt in opusPts.difference(seen)) {
    final idx = out.indexWhere((l) => l.startsWith('a=rtpmap:$pt '));
    if (idx >= 0) out.insert(idx + 1, 'a=fmtp:$pt $extra');
  }
  return out.join('\r\n');
}

/// The one microphone track. Starts muted; PTT flips `muted`.
class WebRtcLocalAudio implements LocalAudio {
  MediaStream? _stream;
  MediaStreamTrack? _track;

  MediaStream? get stream => _stream;
  MediaStreamTrack? get track => _track;

  @override
  bool get acquired => _track != null;

  @override
  Future<void> acquire() async {
    if (_track != null) return;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    final tracks = stream.getAudioTracks();
    if (tracks.isEmpty) {
      await stream.dispose();
      throw StateError('no microphone track');
    }
    _stream = stream;
    _track = tracks.first..enabled = false;
    // Use whatever the phone is routing to (car Bluetooth, CarPlay, earpiece)
    // rather than forcing the loudspeaker. Remote tracks play through the
    // same route automatically once they arrive; no renderer is needed for
    // audio-only.
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (e) {
      debugPrint('setSpeakerphoneOn failed: $e');
    }
  }

  @override
  bool get muted => !(_track?.enabled ?? false);

  @override
  set muted(bool value) {
    final t = _track;
    if (t != null) t.enabled = !value;
  }

  @override
  Future<void> release() async {
    final t = _track;
    final s = _stream;
    _track = null;
    _stream = null;
    try {
      await t?.stop();
    } catch (_) {}
    try {
      await s?.dispose();
    } catch (_) {}
  }
}

/// Real links over `flutter_webrtc`.
class WebRtcPeerLinkFactory implements PeerLinkFactory {
  const WebRtcPeerLinkFactory();

  @override
  Future<PeerLink> create(
    String peerId, {
    required bool offerer,
    required List<Map<String, Object?>> iceServers,
    required LocalAudio audio,
  }) async {
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    final link = WebRtcPeerLink._(peerId, pc, offerer: offerer);
    await link._init(audio);
    return link;
  }
}

class WebRtcPeerLink implements PeerLink {
  WebRtcPeerLink._(this.peerId, this._pc, {required this.offerer});

  @override
  final String peerId;
  final bool offerer;
  final RTCPeerConnection _pc;
  RTCDataChannel? _dc;
  final _events = StreamController<PeerLinkEvent>.broadcast();
  final List<IceCandidateData> _pendingIce = [];
  final List<MediaStreamTrack> _remoteTracks = [];
  bool _remoteSet = false;
  bool _incomingMuted = false;
  bool _closed = false;

  @override
  Stream<PeerLinkEvent> get events => _events.stream;

  @override
  bool get dataOpen => _dc?.state == RTCDataChannelState.RTCDataChannelOpen;

  Future<void> _init(LocalAudio audio) async {
    if (audio is WebRtcLocalAudio && audio.track != null) {
      await _pc.addTrack(audio.track!, audio.stream!);
    }
    _pc.onIceCandidate = (c) {
      final s = c.candidate;
      if (s == null || s.isEmpty) return;
      _emit(
        LinkIceCandidate(
          IceCandidateData(
            candidate: s,
            sdpMid: c.sdpMid,
            sdpMLineIndex: c.sdpMLineIndex,
          ),
        ),
      );
    };
    _pc.onConnectionState = (s) {
      _emit(
        LinkStateChanged(switch (s) {
          RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
            LinkState.connected,
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
            LinkState.disconnected,
          RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
            LinkState.failed,
          RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
            LinkState.closed,
          RTCPeerConnectionState.RTCPeerConnectionStateNew ||
          RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
            LinkState.connecting,
        }),
      );
    };
    _pc.onTrack = (e) {
      if (e.track.kind == 'audio') {
        _remoteTracks.add(e.track);
        e.track.enabled = !_incomingMuted;
      }
    };
    if (offerer) {
      final dc = await _pc.createDataChannel(
        'drivalry',
        RTCDataChannelInit()..ordered = true,
      );
      _wire(dc);
    } else {
      _pc.onDataChannel = _wire;
    }
  }

  void _wire(RTCDataChannel dc) {
    _dc = dc;
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _emit(const LinkDataOpen());
      } else if (s == RTCDataChannelState.RTCDataChannelClosed ||
          s == RTCDataChannelState.RTCDataChannelClosing) {
        _emit(const LinkDataClosed());
      }
    };
    dc.onMessage = (m) {
      if (!m.isBinary) _emit(LinkDataText(m.text));
    };
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      _emit(const LinkDataOpen());
    }
  }

  @override
  Future<String> createOffer() async {
    final offer = await _pc.createOffer({});
    final sdp = tuneOpus(offer.sdp ?? '');
    await _pc.setLocalDescription(RTCSessionDescription(sdp, 'offer'));
    return sdp;
  }

  @override
  Future<void> setRemoteAnswer(String sdp) async {
    await _pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    await _flushIce();
  }

  @override
  Future<String> createAnswer(String offerSdp) async {
    await _pc.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    await _flushIce();
    final answer = await _pc.createAnswer({});
    final sdp = tuneOpus(answer.sdp ?? '');
    await _pc.setLocalDescription(RTCSessionDescription(sdp, 'answer'));
    return sdp;
  }

  Future<void> _flushIce() async {
    _remoteSet = true;
    final pending = List.of(_pendingIce);
    _pendingIce.clear();
    for (final c in pending) {
      await addIceCandidate(c);
    }
  }

  @override
  Future<void> addIceCandidate(IceCandidateData c) async {
    if (!_remoteSet) {
      _pendingIce.add(c);
      return;
    }
    await _pc.addCandidate(
      RTCIceCandidate(c.candidate, c.sdpMid, c.sdpMLineIndex),
    );
  }

  @override
  Future<String> restartIce() async {
    await _pc.restartIce();
    return createOffer();
  }

  @override
  bool sendText(String text) {
    final dc = _dc;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      return false;
    }
    dc.send(RTCDataChannelMessage(text)).catchError((e) {
      debugPrint('data channel send failed: $e');
    });
    return true;
  }

  @override
  set incomingMuted(bool value) {
    _incomingMuted = value;
    for (final t in _remoteTracks) {
      t.enabled = !value;
    }
  }

  @override
  Future<void> pollStats() async {
    if (_closed) return;
    final reports = await _pc.getStats();
    Map<dynamic, dynamic>? pair;
    for (final r in reports) {
      if (r.type == 'candidate-pair' &&
          (r.values['state'] == 'succeeded' || r.values['nominated'] == true)) {
        pair = r.values;
        if (r.values['nominated'] == true) break;
      }
    }
    if (pair == null) return;
    final localId = pair['localCandidateId'];
    var relayed = false;
    for (final r in reports) {
      if (r.id == localId && r.type == 'local-candidate') {
        relayed = r.values['candidateType'] == 'relay';
      }
    }
    _emit(
      LinkStats(
        relayed: relayed,
        bytesSent: _asInt(pair['bytesSent']),
        bytesReceived: _asInt(pair['bytesReceived']),
      ),
    );
  }

  static int _asInt(Object? v) => switch (v) {
    int i => i,
    num n => n.toInt(),
    String s => int.tryParse(s) ?? 0,
    _ => 0,
  };

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _dc?.close();
    } catch (_) {}
    try {
      await _pc.close();
    } catch (_) {}
    try {
      await _pc.dispose();
    } catch (_) {}
    unawaited(_events.close());
  }

  void _emit(PeerLinkEvent e) {
    if (!_events.isClosed) _events.add(e);
  }
}
