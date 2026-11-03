import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../audio/convoy_audio_session.dart';
import '../positions/peer_positions.dart';
import '../radio/data_bus.dart';
import 'games_core.dart';

/// A snapshot for the games screen. The cores are mutable and owned by the
/// controller; [version] bumps so widgets rebuild.
class GamesState {
  const GamesState({
    required this.version,
    required this.peers,
    this.lastResult,
  });
  final int version;
  final Set<String> peers;
  final String? lastResult;
}

/// Runs the four passenger games over the convoy data bus and announces
/// results aloud for drivers (docs/01 §4.6).
class GamesController extends Notifier<GamesState> {
  GamesController(this.convoyId);

  final String convoyId;
  late PlatesBingo plates;
  late Trivia trivia;
  late Scavenger scavenger;
  final smoothest = SmoothestLeg();
  final Map<String, int> _lastSpeedT = {};
  final List<StreamSubscription<void>> _subs = [];
  final List<StreamSubscription<void>> _busSubs = [];
  Map<String, String> _names = const {};
  Timer? _revealTimer;
  int _version = 0;

  @override
  GamesState build() {
    final me = ref.watch(currentUserIdProvider) ?? 'me';
    plates = PlatesBingo(me);
    trivia = Trivia(me);
    scavenger = Scavenger(me);
    // Follow the bus as the radio starts and stops without rebuilding: a
    // rebuild would wipe every board and score.
    final bus = ref.read(convoyDataBusProvider(convoyId));
    _attachBus(bus);
    ref.listen(convoyDataBusProvider(convoyId), (_, next) {
      _attachBus(next);
      _bump(peers: next.connectedPeers);
    });
    _subs.add(
      ref.watch(peerPositionHubProvider(convoyId)).stream.listen((latest) {
        // The hub re-emits every car on each update; sample each fix once.
        for (final p in latest.values) {
          final speed = p.speed;
          if (speed == null || (_lastSpeedT[p.userId] ?? -1) >= p.t) continue;
          _lastSpeedT[p.userId] = p.t;
          smoothest.addSpeed(p.userId, p.t, speed);
        }
        _bump();
      }),
    );
    ref.onDispose(() {
      for (final s in [..._subs, ..._busSubs]) {
        s.cancel();
      }
      _revealTimer?.cancel();
    });
    unawaited(_refreshNames());
    return GamesState(version: 0, peers: bus.connectedPeers);
  }

  void _attachBus(ConvoyDataBus bus) {
    for (final s in _busSubs) {
      s.cancel();
    }
    _busSubs
      ..clear()
      ..add(bus.messages.where((m) => m.type == 'game').listen(_onMessage))
      ..add(bus.connectedPeersStream.listen((p) => _bump(peers: p)));
  }

  /// Names for spoken results come from the cached member list.
  Future<void> _refreshNames() async {
    final names = await ref.read(convoyRepoProvider).memberNames(convoyId);
    if (ref.mounted) _names = names;
  }

  ConvoyDataBus get _bus => ref.read(convoyDataBusProvider(convoyId));
  Set<String> get _participants => {..._bus.connectedPeers};

  void _bump({Set<String>? peers, String? result}) {
    _version++;
    state = GamesState(
      version: _version,
      peers: peers ?? state.peers,
      lastResult: result ?? state.lastResult,
    );
  }

  void _send(Map<String, Object?>? payload) {
    if (payload == null || payload.isEmpty) return;
    _bus.send('game', payload);
  }

  // ---------------------------------------------------------------- plates --

  void togglePlate(String code) {
    _send(plates.toggle(code));
    _bump();
  }

  // ---------------------------------------------------------------- trivia --

  bool get amTriviaHost => trivia.isHost(_participants);

  void askNextQuestion() {
    if (!amTriviaHost) return;
    _send(trivia.nextQuestion());
    _revealTimer?.cancel();
    _revealTimer = Timer(
      Duration(milliseconds: trivia.questionMs + 500),
      revealTrivia,
    );
    _bump();
  }

  void answerTrivia(int choice) {
    _send(trivia.answer(choice));
    _bump();
  }

  void revealTrivia() {
    if (!amTriviaHost) return;
    final payload = trivia.reveal();
    _send(payload);
    unawaited(_announce(payload.cast<String, dynamic>()));
  }

  Future<void> _announce(Map<String, dynamic> reveal) async {
    if (reveal.isEmpty) return;
    await _refreshNames();
    if (!ref.mounted) return;
    final text = trivia.spokenResult(reveal, _nameOf);
    _bump(result: text);
    unawaited(ref.read(speakerProvider).say(text));
  }

  // ------------------------------------------------------------- scavenger --

  void claimItem(String item) {
    final payload = scavenger.claim(
      item,
      DateTime.now().millisecondsSinceEpoch,
    );
    _send(payload);
    _bump(result: payload == null ? null : 'You spotted $item');
  }

  // ---------------------------------------------------------------- inbound --

  void _onMessage(DataMessage m) {
    // A bus may echo our own sends; the cores already applied them.
    if (m.from == plates.selfId) return;
    final g = GameMessage(from: m.from, t: m.t, payload: m.payload);
    plates.onMessage(g);
    trivia.onMessage(g);
    scavenger.onMessage(g);
    if (g.game == 'trivia' && g.event == 'reveal') {
      unawaited(_announce(m.payload));
      return;
    }
    if (g.game == 'scavenger' && g.event == 'claim') {
      final item = m.payload['item'];
      unawaited(
        _refreshNames().then((_) {
          if (ref.mounted) _bump(result: '${_nameOf(m.from)} spotted $item');
        }),
      );
      return;
    }
    _bump();
  }

  /// "You", the member's display name, or "Someone": never a UUID.
  String _nameOf(String id) {
    if (id == plates.selfId) return 'You';
    return _names[id] ?? 'Someone';
  }
}

final gamesControllerProvider =
    NotifierProvider.family<GamesController, GamesState, String>(
      GamesController.new,
    );
