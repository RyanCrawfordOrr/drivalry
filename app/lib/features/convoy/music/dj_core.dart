import 'dart:math' as math;

import '../../../data/spotify/spotify_client.dart';

/// A `dj` command received from a peer (docs/10 §6).
class DjCommand {
  const DjCommand({required this.from, required this.t, required this.payload});
  final String from;
  final int t;
  final Map<String, dynamic> payload;
  String get cmd => payload['cmd'] as String? ?? '';
}

/// Something the core wants sent or done. The controller turns these into
/// data-bus messages and Spotify calls; keeping them as values makes the
/// protocol testable without a mesh.
sealed class DjEffect {
  const DjEffect();
}

class SendDj extends DjEffect {
  const SendDj(this.payload, {this.to});
  final Map<String, Object?> payload;
  final String? to;
}

/// Start [uri] at [positionMs] when the local clock reads [atLocalMs].
class SchedulePlay extends DjEffect {
  const SchedulePlay({
    required this.uri,
    required this.positionMs,
    required this.atLocalMs,
  });
  final String uri;
  final int positionMs;
  final int atLocalMs;
}

class PauseAll extends DjEffect {
  const PauseAll();
}

/// Estimates how far ahead (positive) a peer's clock is from ours, from
/// `ping`/`pong` round trips. Median of the last five samples.
class ClockOffset {
  final List<int> _samples = [];
  static const keep = 5;

  int get offsetMs {
    if (_samples.isEmpty) return 0;
    final sorted = [..._samples]..sort();
    return sorted[sorted.length ~/ 2];
  }

  int get sampleCount => _samples.length;

  /// [sentAt] is our clock when we pinged, [peerNow] the peer's clock when it
  /// answered, [receivedAt] our clock when the pong arrived.
  void addSample({
    required int sentAt,
    required int peerNow,
    required int receivedAt,
  }) {
    final rtt = receivedAt - sentAt;
    final offset = peerNow - (sentAt + rtt ~/ 2);
    _samples.add(offset);
    if (_samples.length > keep) _samples.removeAt(0);
  }
}

/// The Convoy DJ state machine: who is DJ, the queue, clock offsets, play
/// scheduling, skip votes and the per-DJ track count. Pure and clock-injected.
class DjCore {
  DjCore({
    required this.selfId,
    required int Function() now,
    this.leadMs = 1500,
    this.resyncThresholdMs = 500,
    // ignore: prefer_initializing_formals
  }) : _now = now;

  final String selfId;
  final int Function() _now;

  /// How far ahead a play command is scheduled so everyone can prepare.
  final int leadMs;
  final int resyncThresholdMs;

  String? dj;
  final List<SpotifyTrack> queue = [];
  final Map<String, ClockOffset> offsets = {};
  final Map<String, int> _pendingPings = {};
  final Set<String> skipVotes = {};
  final Map<String, int> tracksByDj = {};

  /// What everyone should be playing right now, as last commanded.
  SpotifyTrack? current;
  int? _currentStartedLocalMs;
  int _currentPositionAtStart = 0;

  bool get isDj => dj == selfId;

  /// Expected playback position of [current] at this instant.
  int? expectedPositionMs() {
    final started = _currentStartedLocalMs;
    if (started == null) return null;
    return _currentPositionAtStart + (_now() - started);
  }

  // ------------------------------------------------------------- claiming --

  /// I want to be DJ. Lower user id wins a conflict, deterministically.
  List<DjEffect> claim() {
    if (dj == null || selfId.compareTo(dj!) < 0) dj = selfId;
    return [
      SendDj({'cmd': 'claim'}),
    ];
  }

  List<DjEffect> release() {
    if (!isDj) return const [];
    dj = null;
    return [
      SendDj({'cmd': 'release'}),
    ];
  }

  // ------------------------------------------------------------- the queue --

  void enqueue(SpotifyTrack t) => queue.add(t);

  void removeFromQueue(String uri) => queue.removeWhere((t) => t.uri == uri);

  /// DJ only: play the next queued track (or a specific one) in lockstep.
  List<DjEffect> playNext({SpotifyTrack? track}) {
    if (!isDj) return const [];
    final t = track ?? (queue.isEmpty ? null : queue.removeAt(0));
    if (t == null) {
      return [
        const PauseAll(),
        SendDj({'cmd': 'pause'}),
      ];
    }
    queue.remove(t);
    final atT = _now() + leadMs;
    _startLocal(t, 0, atT);
    tracksByDj[selfId] = (tracksByDj[selfId] ?? 0) + 1;
    skipVotes.clear();
    return [
      SendDj({
        'cmd': 'play',
        'uri': t.uri,
        'positionMs': 0,
        'atT': atT,
        'track': t.toJson(),
      }),
      SchedulePlay(uri: t.uri, positionMs: 0, atLocalMs: atT),
    ];
  }

  /// Anyone: vote to skip. The DJ skips when a majority of [participants]
  /// (everyone in the mesh, DJ included) has voted.
  List<DjEffect> voteSkip(Set<String> participants) {
    skipVotes.add(selfId);
    final effects = <DjEffect>[
      SendDj({'cmd': 'skip-vote'}),
    ];
    if (isDj && hasMajority(participants)) effects.addAll(playNext());
    return effects;
  }

  bool hasMajority(Set<String> participants) {
    final total = {...participants, selfId, ?dj}.length;
    return skipVotes.length * 2 > total;
  }

  // ------------------------------------------------------------ clock sync --

  /// Send a ping to [peer]; call every 30 s per peer.
  List<DjEffect> ping(String peer) {
    final t = _now();
    _pendingPings[peer] = t;
    return [
      SendDj({'cmd': 'ping', 't': t}, to: peer),
    ];
  }

  // ------------------------------------------------------------- receiving --

  /// Handle a `dj` message from a peer.
  List<DjEffect> onCommand(DjCommand c, {required Set<String> participants}) {
    final p = c.payload;
    switch (c.cmd) {
      case 'claim':
        if (dj == null || c.from.compareTo(dj!) < 0) {
          dj = c.from;
          return const [];
        }
        // Someone with a higher id claimed while a lower id holds it: re-assert
        // only if I am that lower id.
        return isDj
            ? [
                SendDj({'cmd': 'claim'}),
              ]
            : const [];
      case 'release':
        if (dj == c.from) dj = null;
        return const [];
      case 'ping':
        return [
          SendDj({'cmd': 'pong', 't': p['t'], 'rt': _now()}, to: c.from),
        ];
      case 'pong':
        final sentAt = (p['t'] as num?)?.toInt();
        final peerNow = (p['rt'] as num?)?.toInt();
        if (sentAt == null || peerNow == null) return const [];
        if (_pendingPings[c.from] != sentAt) return const [];
        _pendingPings.remove(c.from);
        (offsets[c.from] ??= ClockOffset()).addSample(
          sentAt: sentAt,
          peerNow: peerNow,
          receivedAt: _now(),
        );
        return const [];
      case 'play':
        if (c.from != dj) {
          // Only the DJ drives playback; a stale DJ's command is ignored.
          return const [];
        }
        final uri = p['uri'] as String?;
        final atT = (p['atT'] as num?)?.toInt();
        if (uri == null || atT == null) return const [];
        final positionMs = (p['positionMs'] as num?)?.toInt() ?? 0;
        final offset = offsets[c.from]?.offsetMs ?? 0;
        // Peer clock → mine.
        final atLocal = atT - offset;
        final trackJson = p['track'];
        final track = trackJson is Map<String, dynamic>
            ? SpotifyTrack.fromJson(trackJson)
            : SpotifyTrack(uri: uri, name: uri, artists: '', durationMs: 0);
        _startLocal(track, positionMs, atLocal);
        tracksByDj[c.from] = (tracksByDj[c.from] ?? 0) + 1;
        skipVotes.clear();
        return [
          SchedulePlay(uri: uri, positionMs: positionMs, atLocalMs: atLocal),
        ];
      case 'pause':
        if (c.from != dj) return const [];
        _currentStartedLocalMs = null;
        return const [PauseAll()];
      case 'skip-vote':
        skipVotes.add(c.from);
        if (isDj && hasMajority(participants)) return playNext();
        return const [];
      default:
        return const [];
    }
  }

  void _startLocal(SpotifyTrack t, int positionMs, int atLocalMs) {
    current = t;
    _currentPositionAtStart = positionMs;
    _currentStartedLocalMs = atLocalMs;
  }

  /// Given what Spotify reports is playing, decide whether to seek. Returns the
  /// position to seek to, or null when within tolerance (or nothing is
  /// expected to play).
  int? resyncTarget(NowPlaying? np) {
    final expected = expectedPositionMs();
    final cur = current;
    if (expected == null || cur == null || expected < 0) return null;
    if (np == null || np.track?.uri != cur.uri || !np.isPlaying) {
      return expected;
    }
    final drift = (np.progressMs - expected).abs();
    return drift > resyncThresholdMs ? expected : null;
  }

  /// Local time to start a track that should begin at peer time [atT] from a
  /// peer with a known [offset]; adds the catch-up when we are already late.
  static ({int atLocalMs, int positionMs}) localStart({
    required int atT,
    required int positionMs,
    required int offsetMs,
    required int nowMs,
  }) {
    final atLocal = atT - offsetMs;
    if (atLocal >= nowMs) return (atLocalMs: atLocal, positionMs: positionMs);
    return (atLocalMs: nowMs, positionMs: positionMs + (nowMs - atLocal));
  }

  static int median(List<int> values) {
    if (values.isEmpty) return 0;
    final s = [...values]..sort();
    return s[s.length ~/ 2];
  }

  static int clampPosition(int ms) => math.max(0, ms);
}
