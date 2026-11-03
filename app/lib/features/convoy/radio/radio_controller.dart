import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../tracking/tracking_models.dart';
import '../../../widgets/friendly_error.dart';
import '../channel/convoy_channel.dart';
import '../positions/peer_positions.dart';
import 'ice_servers.dart';
import 'mesh.dart';
import 'mesh_data_bus.dart';
import 'peer_link.dart';
import 'position_sender.dart';
import 'ptt_controller.dart';
import 'radio_stats.dart';
import 'webrtc_peer_link.dart';

/// Result of asking for the microphone.
enum MicPermission { granted, denied, permanentlyDenied }

/// Platform-touching pieces the radio needs, bundled so tests can swap them
/// for fakes in one override.
class RadioDeps {
  const RadioDeps({
    required this.linkFactory,
    required this.newAudio,
    required this.requestMicrophone,
    this.haptic,
  });

  final PeerLinkFactory linkFactory;
  final LocalAudio Function() newAudio;
  final Future<MicPermission> Function() requestMicrophone;
  final void Function(bool on)? haptic;
}

final radioDepsProvider = Provider<RadioDeps>(
  (ref) => RadioDeps(
    linkFactory: const WebRtcPeerLinkFactory(),
    newAudio: WebRtcLocalAudio.new,
    requestMicrophone: () async {
      final s = await Permission.microphone.request();
      return switch (s) {
        PermissionStatus.granted ||
        PermissionStatus.limited ||
        PermissionStatus.provisional => MicPermission.granted,
        PermissionStatus.permanentlyDenied => MicPermission.permanentlyDenied,
        _ => MicPermission.denied,
      };
    },
    haptic: (on) =>
        on ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact(),
  ),
);

/// Native audio-session work around a radio session (Android foreground
/// service with microphone + playback types, iOS AVAudioSession). The
/// default does nothing; the native wrapper, when present, is wired in by
/// overriding [convoyAudioSessionHookProvider].
abstract class ConvoyAudioSessionHook {
  Future<void> start();
  Future<void> stop();

  /// Fires when the platform ended the session on its own: Stop on the
  /// Android service notification, or iOS reclaiming the audio session. The
  /// radio tears down when it fires so the UI never shows a dead session.
  Stream<void> get stopped => const Stream.empty();
}

class NoAudioSessionHook implements ConvoyAudioSessionHook {
  const NoAudioSessionHook();
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<void> get stopped => const Stream.empty();
}

final convoyAudioSessionHookProvider = Provider<ConvoyAudioSessionHook>(
  (_) => const NoAudioSessionHook(),
);

enum RadioPhase { off, starting, noPermission, on, error }

class RadioState {
  const RadioState({
    this.phase = RadioPhase.off,
    this.error,
    this.peers = const {},
    this.talking = const {},
    this.holding = false,
    this.muteIncoming = false,
    this.relayAvailable = false,
    this.permanentlyDenied = false,
  });

  final RadioPhase phase;
  final String? error;
  final Map<String, PeerStatus> peers;
  final Set<String> talking;
  final bool holding;
  final bool muteIncoming;

  /// True when a TURN relay was configured for this session.
  final bool relayAvailable;
  final bool permanentlyDenied;

  bool get on => phase == RadioPhase.on;

  RadioState copyWith({
    RadioPhase? phase,
    String? error,
    bool clearError = false,
    Map<String, PeerStatus>? peers,
    Set<String>? talking,
    bool? holding,
    bool? muteIncoming,
    bool? relayAvailable,
    bool? permanentlyDenied,
  }) => RadioState(
    phase: phase ?? this.phase,
    error: clearError ? null : error ?? this.error,
    peers: peers ?? this.peers,
    talking: talking ?? this.talking,
    holding: holding ?? this.holding,
    muteIncoming: muteIncoming ?? this.muteIncoming,
    relayAvailable: relayAvailable ?? this.relayAvailable,
    permanentlyDenied: permanentlyDenied ?? this.permanentlyDenied,
  );
}

/// Owns one convoy's radio session: microphone, ICE, mesh, data bus, PTT and
/// outgoing positions. Lives as long as something watches it or the session
/// is on; `stop()` tears everything down.
class RadioController extends Notifier<RadioState> {
  RadioController(this.convoyId);

  final String convoyId;

  ConvoyMesh? _mesh;
  MeshDataBus? _bus;
  PttController? _ptt;
  LocalAudio? _audio;
  PositionSender? _sender;
  final List<StreamSubscription<Object?>> _subs = [];
  ProviderSubscription<AsyncValue<TrackingEvent>>? _eventsSub;

  // Captured at start so teardown never touches `ref` while disposing.
  RadioBusRegistry? _registry;
  ConvoyAudioSessionHook? _hook;
  StreamSubscription<void>? _hookSub;

  @override
  RadioState build() {
    ref.onDispose(() {
      _teardown();
    });
    return const RadioState();
  }

  Future<void> start() async {
    if (state.phase == RadioPhase.on || state.phase == RadioPhase.starting) {
      return;
    }
    final channel = ref.read(convoyChannelProvider(convoyId));
    final uid = ref.read(currentUserIdProvider);
    if (channel == null || uid == null) {
      state = state.copyWith(
        phase: RadioPhase.error,
        error: 'Sign in to use the convoy radio.',
      );
      return;
    }
    state = state.copyWith(phase: RadioPhase.starting, clearError: true);
    final deps = ref.read(radioDepsProvider);
    try {
      final perm = await deps.requestMicrophone();
      if (perm != MicPermission.granted) {
        state = state.copyWith(
          phase: RadioPhase.noPermission,
          permanentlyDenied: perm == MicPermission.permanentlyDenied,
        );
        return;
      }
      final audio = deps.newAudio();
      await audio.acquire();
      audio.muted = true;
      _audio = audio;

      final hook = ref.read(convoyAudioSessionHookProvider);
      _hook = hook;
      await hook.start();
      _hookSub = hook.stopped.listen((_) {
        debugPrint('radio: audio session ended by the system; stopping');
        unawaited(stop());
      });

      final ice = await ref.read(iceServersProvider).servers();
      final mesh = ConvoyMesh(
        selfId: uid,
        channel: channel,
        linkFactory: deps.linkFactory,
        audio: audio,
        iceServers: ice.servers,
      );
      _mesh = mesh;
      mesh.incomingMuted = state.muteIncoming;

      final bus = MeshDataBus(
        mesh,
        hub: ref.read(peerPositionHubProvider(convoyId)),
      );
      _bus = bus;
      final registry = ref.read(radioBusRegistryProvider.notifier);
      _registry = registry;
      registry.register(convoyId, bus);

      final ptt = PttController(
        audio: audio,
        channel: channel,
        haptic: deps.haptic,
      );
      _ptt = ptt;

      final stats = ref.read(radioStatsProvider);
      _subs.add(
        mesh.peers.listen((p) {
          state = state.copyWith(peers: p);
          for (final id in state.talking) {
            if (!p.containsKey(id)) ptt.forget(id);
          }
        }),
      );
      _subs.add(
        mesh.relayedBytesDelta.listen((b) => stats.addRelayed(convoyId, b)),
      );
      _subs.add(
        ptt.changes.listen((s) {
          state = state.copyWith(holding: s.holding, talking: s.talking);
        }),
      );
      _subs.add(channel.messages.listen(ptt.onMessage));

      _sender = PositionSender(bus);
      _eventsSub = ref.listen(trackingEventsProvider, (_, next) {
        final e = next.value;
        if (e != null) _sender?.onEvent(e);
      });

      await mesh.join();
      state = state.copyWith(
        phase: RadioPhase.on,
        relayAvailable: ice.relay,
        peers: mesh.peersNow,
      );
    } catch (e) {
      debugPrint('radio start failed: $e');
      await _teardown();
      state = state.copyWith(
        phase: RadioPhase.error,
        error: friendlyError(e, doing: 'start the radio'),
      );
    }
  }

  Future<void> stop() async {
    await _teardown();
    state = const RadioState();
  }

  Future<void> press() => _ptt?.press() ?? Future.value();
  Future<void> release() => _ptt?.release() ?? Future.value();

  Future<void> reconnect(String peerId) =>
      _mesh?.reconnect(peerId) ?? Future.value();

  void setMuteIncoming(bool value) {
    _mesh?.incomingMuted = value;
    state = state.copyWith(muteIncoming: value);
  }

  Future<void> _teardown() async {
    _eventsSub?.close();
    _eventsSub = null;
    // Subscription cancels are not awaited. Every stream here is a broadcast
    // stream, whose cancel takes effect synchronously, and when the audio
    // hook itself triggered this teardown we are inside its event dispatch,
    // where awaiting the cancel would stall the whole shutdown.
    unawaited(_hookSub?.cancel());
    _hookSub = null;
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _subs.clear();
    _sender = null;
    await _ptt?.dispose();
    _ptt = null;
    try {
      _registry?.unregister(convoyId);
    } catch (_) {}
    _registry = null;
    await _bus?.dispose();
    _bus = null;
    await _mesh?.dispose();
    _mesh = null;
    await _audio?.release();
    _audio = null;
    final hook = _hook;
    _hook = null;
    try {
      await hook?.stop();
    } catch (_) {}
  }
}

final radioControllerProvider =
    NotifierProvider.family<RadioController, RadioState, String>(
      RadioController.new,
    );
