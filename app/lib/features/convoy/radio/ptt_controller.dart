import 'dart:async';

import '../channel/convoy_channel.dart';
import 'peer_link.dart';
import 'signaling.dart';

/// Who is talking, and whether I am holding the button.
class PttState {
  const PttState({this.holding = false, this.talking = const {}});
  final bool holding;

  /// Other members currently transmitting.
  final Set<String> talking;

  PttState copyWith({bool? holding, Set<String>? talking}) => PttState(
    holding: holding ?? this.holding,
    talking: talking ?? this.talking,
  );
}

/// Push-to-talk (docs/10 §4): the local track is muted until the button is
/// held; a `ptt` broadcast tells the others who is speaking. A hold is cut
/// at [maxHold] so a pocketed phone cannot transmit forever.
class PttController {
  PttController({
    required this.audio,
    required this.channel,
    this.maxHold = const Duration(seconds: 20),
    this.talkerTimeout = const Duration(seconds: 25),
    this.haptic,
  });

  final LocalAudio audio;
  final ConvoyChannel channel;
  final Duration maxHold;

  /// A talker whose `ptt off` never arrived is dropped after this.
  final Duration talkerTimeout;
  final void Function(bool on)? haptic;

  final _state = StreamController<PttState>.broadcast();
  final Map<String, Timer> _talkerTimers = {};
  Timer? _holdTimer;
  PttState _current = const PttState();

  PttState get state => _current;
  Stream<PttState> get changes => _state.stream;

  Future<void> press() async {
    if (_current.holding) return;
    audio.muted = false;
    _set(_current.copyWith(holding: true));
    haptic?.call(true);
    _holdTimer?.cancel();
    _holdTimer = Timer(maxHold, release);
    try {
      await channel.sendPtt(on: true);
    } catch (_) {}
  }

  Future<void> release() async {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_current.holding) return;
    audio.muted = true;
    _set(_current.copyWith(holding: false));
    haptic?.call(false);
    try {
      await channel.sendPtt(on: false);
    } catch (_) {}
  }

  /// Feed every channel message here; only `ptt` is used.
  void onMessage(ConvoyMessage m) {
    if (m.type != RadioSignal.ptt) return;
    final talking = {..._current.talking};
    _talkerTimers.remove(m.from)?.cancel();
    if (m.pttOn) {
      talking.add(m.from);
      _talkerTimers[m.from] = Timer(talkerTimeout, () => _expire(m.from));
    } else {
      talking.remove(m.from);
    }
    _set(_current.copyWith(talking: talking));
  }

  /// A peer that left stops showing as talking.
  void forget(String userId) {
    _talkerTimers.remove(userId)?.cancel();
    if (!_current.talking.contains(userId)) return;
    _set(_current.copyWith(talking: {..._current.talking}..remove(userId)));
  }

  void _expire(String userId) {
    _talkerTimers.remove(userId);
    if (!_current.talking.contains(userId)) return;
    _set(_current.copyWith(talking: {..._current.talking}..remove(userId)));
  }

  void _set(PttState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  Future<void> dispose() async {
    _holdTimer?.cancel();
    for (final t in _talkerTimers.values) {
      t.cancel();
    }
    _talkerTimers.clear();
    if (_current.holding) audio.muted = true;
    unawaited(_state.close());
  }
}
