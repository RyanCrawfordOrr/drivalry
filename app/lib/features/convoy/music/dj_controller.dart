import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/spotify/spotify_client.dart';
import '../../../data/spotify/spotify_providers.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../radio/data_bus.dart';
import 'dj_core.dart';

/// What the music screen renders.
class DjState {
  const DjState({
    this.dj,
    this.isDj = false,
    this.current,
    this.queue = const [],
    this.peers = const {},
    this.skipVotes = 0,
    this.spotifyConnected = false,
    this.error,
    this.nowPlaying,
  });

  final String? dj;
  final bool isDj;
  final SpotifyTrack? current;
  final List<SpotifyTrack> queue;
  final Set<String> peers;
  final int skipVotes;
  final bool spotifyConnected;
  final String? error;
  final NowPlaying? nowPlaying;

  DjState copyWith({
    String? dj,
    bool clearDj = false,
    bool? isDj,
    SpotifyTrack? current,
    List<SpotifyTrack>? queue,
    Set<String>? peers,
    int? skipVotes,
    bool? spotifyConnected,
    String? error,
    bool clearError = false,
    NowPlaying? nowPlaying,
  }) => DjState(
    dj: clearDj ? null : (dj ?? this.dj),
    isDj: isDj ?? this.isDj,
    current: current ?? this.current,
    queue: queue ?? this.queue,
    peers: peers ?? this.peers,
    skipVotes: skipVotes ?? this.skipVotes,
    spotifyConnected: spotifyConnected ?? this.spotifyConnected,
    error: clearError ? null : (error ?? this.error),
    nowPlaying: nowPlaying ?? this.nowPlaying,
  );
}

/// Drives [DjCore] with the convoy data bus and Spotify: pings peers every
/// 30 s, applies play commands at the right local instant, polls the player
/// every 30 s to re-sync when drift exceeds 500 ms, and persists the per-DJ
/// track count for the recap (docs/10 §6).
class DjController extends Notifier<DjState> {
  DjController(this.convoyId);

  final String convoyId;
  late DjCore core;
  final List<StreamSubscription<void>> _subs = [];
  final List<Timer> _timers = [];
  Timer? _pingTimer;
  Timer? _pollTimer;

  static String tracksKey(String convoyId) => 'convoy:$convoyId:dj_tracks';

  @override
  DjState build() {
    final uid = ref.watch(currentUserIdProvider) ?? 'me';
    core = DjCore(
      selfId: uid,
      now: () => DateTime.now().millisecondsSinceEpoch,
    );
    // Follow the bus as the radio starts and stops without rebuilding: a
    // rebuild would drop the queue, the DJ claim and every peer's clock offset.
    final bus = ref.read(convoyDataBusProvider(convoyId));
    _attachBus(bus);
    ref.listen(convoyDataBusProvider(convoyId), (_, next) {
      _attachBus(next);
      _onPeers(next.connectedPeers);
    });
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pingAll());
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      for (final t in _timers) {
        t.cancel();
      }
      _pingTimer?.cancel();
      _pollTimer?.cancel();
    });
    _refreshSpotify();
    return DjState(peers: bus.connectedPeers);
  }

  ConvoyDataBus get _bus => ref.read(convoyDataBusProvider(convoyId));
  SpotifyClient get _spotify => ref.read(spotifyClientProvider);

  void _attachBus(ConvoyDataBus bus) {
    for (final s in _subs) {
      s.cancel();
    }
    _subs
      ..clear()
      ..add(bus.messages.where((m) => m.type == 'dj').listen(_onMessage))
      ..add(bus.connectedPeersStream.listen(_onPeers));
  }

  Future<void> _refreshSpotify() async {
    final signedIn = await ref.read(spotifyAuthProvider).isSignedIn;
    state = state.copyWith(spotifyConnected: signedIn);
  }

  Future<void> connectSpotify() async {
    try {
      await ref.read(spotifyAuthProvider).signIn();
      ref.invalidate(spotifySignedInProvider);
      state = state.copyWith(spotifyConnected: true, clearError: true);
    } catch (e) {
      state = state.copyWith(error: 'Spotify sign-in failed: $e');
    }
  }

  Future<void> disconnectSpotify() async {
    await ref.read(spotifyAuthProvider).signOut();
    ref.invalidate(spotifySignedInProvider);
    state = state.copyWith(spotifyConnected: false);
  }

  void claim() => _apply(core.claim());
  void release() => _apply(core.release());
  void addToQueue(SpotifyTrack t) {
    core.enqueue(t);
    _publish();
  }

  void removeFromQueue(String uri) {
    core.removeFromQueue(uri);
    _publish();
  }

  void playNext({SpotifyTrack? track}) => _apply(core.playNext(track: track));
  void voteSkip() => _apply(core.voteSkip(_bus.connectedPeers));

  Future<List<SpotifyTrack>> search(String q) async {
    try {
      return await _spotify.search(q);
    } on SpotifyException catch (e) {
      state = state.copyWith(error: e.message);
      return const [];
    }
  }

  void _onPeers(Set<String> peers) {
    state = state.copyWith(peers: peers);
    for (final p in peers) {
      if (!core.offsets.containsKey(p)) _apply(core.ping(p));
    }
  }

  void _pingAll() {
    for (final p in _bus.connectedPeers) {
      _apply(core.ping(p));
    }
  }

  void _onMessage(DataMessage m) {
    // A bus may echo our own sends; the core already applied them.
    if (m.from == core.selfId) return;
    _apply(
      core.onCommand(
        DjCommand(from: m.from, t: m.t, payload: m.payload),
        participants: _bus.connectedPeers,
      ),
    );
  }

  void _apply(List<DjEffect> effects) {
    for (final e in effects) {
      switch (e) {
        case SendDj():
          _bus.send('dj', e.payload, to: e.to);
        case SchedulePlay():
          _schedule(e);
        case PauseAll():
          _spotifySafe(() => _spotify.pause());
      }
    }
    _publish();
    _persistCounts();
  }

  void _schedule(SchedulePlay e) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final start = DjCore.localStart(
      atT: e.atLocalMs,
      positionMs: e.positionMs,
      offsetMs: 0,
      nowMs: now,
    );
    final delay = Duration(milliseconds: start.atLocalMs - now);
    _timers.add(
      Timer(delay.isNegative ? Duration.zero : delay, () {
        _spotifySafe(() => _spotify.play(e.uri, positionMs: start.positionMs));
      }),
    );
  }

  Future<void> _poll() async {
    if (core.current == null || !state.spotifyConnected) return;
    try {
      final np = await _spotify.currentlyPlaying();
      state = state.copyWith(nowPlaying: np);
      final target = core.resyncTarget(np);
      if (target != null) {
        final cur = core.current!;
        if (np?.track?.uri == cur.uri && np!.isPlaying) {
          await _spotify.seek(target);
        } else {
          await _spotify.play(cur.uri, positionMs: target);
        }
      }
    } on SpotifyException catch (e) {
      state = state.copyWith(error: e.message);
    }
  }

  Future<void> _spotifySafe(Future<void> Function() call) async {
    if (!state.spotifyConnected) return;
    try {
      await call();
      if (state.error != null) state = state.copyWith(clearError: true);
    } on SpotifyException catch (e) {
      state = state.copyWith(error: e.message);
    } catch (e) {
      debugPrint('spotify call failed: $e');
    }
  }

  void _publish() {
    state = state.copyWith(
      dj: core.dj,
      clearDj: core.dj == null,
      isDj: core.isDj,
      current: core.current,
      queue: List.unmodifiable(core.queue),
      skipVotes: core.skipVotes.length,
    );
  }

  Future<void> _persistCounts() async {
    if (core.tracksByDj.isEmpty) return;
    try {
      await ref
          .read(databaseProvider)
          .setSetting(tracksKey(convoyId), jsonEncode(core.tracksByDj));
    } catch (e) {
      debugPrint('dj counts not saved: $e');
    }
  }
}

final djControllerProvider =
    NotifierProvider.family<DjController, DjState, String>(DjController.new);
