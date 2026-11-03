import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/supabase/supabase_providers.dart';

/// One broadcast on a convoy channel (docs/10-convoy-protocol.md §3).
///
/// `to` is a unicast hint: messages carrying a `to` for someone else are
/// dropped by [ConvoyChannel] before they reach listeners.
class ConvoyMessage {
  const ConvoyMessage({
    required this.type,
    required this.from,
    required this.t,
    required this.payload,
    this.to,
  });

  final String type;
  final String from;
  final int t;
  final String? to;
  final Map<String, dynamic> payload;

  static ConvoyMessage? fromWire(Map<String, dynamic> m) {
    if (m['v'] != 1) return null;
    final type = m['type'];
    final from = m['from'];
    if (type is! String || from is! String) return null;
    return ConvoyMessage(
      type: type,
      from: from,
      t: (m['t'] as num?)?.toInt() ?? 0,
      to: m['to'] as String?,
      payload: Map<String, dynamic>.from(m)
        ..remove('v')
        ..remove('type')
        ..remove('from')
        ..remove('t')
        ..remove('to'),
    );
  }
}

/// The ephemeral side of a convoy: Realtime Broadcast for signaling, pins,
/// chat and the position fallback, and Realtime Presence for "who is here".
/// Durable state (members, stops, votes) lives in Postgres, not here.
abstract class ConvoyChannel {
  String get convoyId;

  /// Parsed broadcasts addressed to everyone or to me, in arrival order.
  Stream<ConvoyMessage> get messages;

  /// User ids currently present on the channel (Realtime presence).
  Stream<Set<String>> get present;

  /// Latest presence snapshot.
  Set<String> get presentNow;

  Future<void> join();
  Future<void> leave();

  /// Sends `{v:1, type, from, t, to?, ...payload}` to the channel.
  Future<void> send(String type, Map<String, Object?> payload, {String? to});
}

/// Shares one underlying connection between several consumers (the convoy
/// live wiring and the radio): [join] opens on the first consumer, [leave]
/// closes on the last, so neither consumer can tear the other's channel
/// down. [shutdown] closes regardless, for provider disposal.
abstract class RefCountedConvoyChannel implements ConvoyChannel {
  int _listeners = 0;

  /// Consumers currently joined.
  int get listeners => _listeners;

  @override
  Future<void> join() async {
    _listeners++;
    if (_listeners == 1) await open();
  }

  @override
  Future<void> leave() async {
    if (_listeners == 0) return;
    _listeners--;
    if (_listeners == 0) await close();
  }

  /// Closes the connection whatever the count (the owning provider is gone).
  Future<void> shutdown() async {
    _listeners = 0;
    await close();
  }

  /// Opens the underlying connection (first consumer).
  @protected
  Future<void> open();

  /// Closes the underlying connection (last consumer or shutdown).
  @protected
  Future<void> close();
}

/// Supabase-backed implementation. One channel object per convoy per app
/// lifetime; every consumer (convoy screen, radio) calls [join] when it needs
/// the channel and [leave] when it is done; the socket lives while anyone is
/// joined.
class SupabaseConvoyChannel extends RefCountedConvoyChannel {
  SupabaseConvoyChannel(this._client, this.convoyId, this._userId);

  final SupabaseClient _client;
  @override
  final String convoyId;
  final String _userId;

  RealtimeChannel? _channel;
  final _messages = StreamController<ConvoyMessage>.broadcast();
  final _present = StreamController<Set<String>>.broadcast();
  Set<String> _presentNow = const {};
  static const _event = 'msg';

  @override
  Stream<ConvoyMessage> get messages => _messages.stream;

  @override
  Stream<Set<String>> get present => _present.stream;

  @override
  Set<String> get presentNow => _presentNow;

  @override
  Future<void> open() async {
    if (_channel != null) return;
    final ch = _client.channel(
      'convoy:$convoyId',
      opts: const RealtimeChannelConfig(self: false),
    );
    ch
        .onBroadcast(
          event: _event,
          callback: (payload) {
            final m = ConvoyMessage.fromWire(payload);
            if (m == null) return;
            if (m.to != null && m.to != _userId) return;
            if (m.from == _userId) return;
            _messages.add(m);
          },
        )
        .onPresenceSync((_) => _syncPresence(ch))
        .onPresenceJoin((_) => _syncPresence(ch))
        .onPresenceLeave((_) => _syncPresence(ch));
    _channel = ch;
    final completer = Completer<void>();
    ch.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await ch.track({
            'user_id': _userId,
            'at': DateTime.now().toIso8601String(),
          });
        } catch (e) {
          debugPrint('convoy presence track failed: $e');
        }
        if (!completer.isCompleted) completer.complete();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        debugPrint('convoy channel $status: $error');
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => debugPrint('convoy channel subscribe timed out'),
    );
  }

  void _syncPresence(RealtimeChannel ch) {
    final state = ch.presenceState();
    final ids = <String>{};
    for (final entry in state) {
      for (final p in entry.presences) {
        final id = p.payload['user_id'];
        if (id is String) ids.add(id);
      }
    }
    _presentNow = ids;
    _present.add(ids);
  }

  @override
  Future<void> close() async {
    final ch = _channel;
    _channel = null;
    if (ch == null) return;
    try {
      await ch.untrack();
    } catch (_) {}
    await _client.removeChannel(ch);
    _presentNow = const {};
    _present.add(const {});
  }

  @override
  Future<void> send(
    String type,
    Map<String, Object?> payload, {
    String? to,
  }) async {
    final ch = _channel;
    if (ch == null) return;
    await ch.sendBroadcastMessage(
      event: _event,
      payload: {
        'v': 1,
        'type': type,
        'from': _userId,
        't': DateTime.now().millisecondsSinceEpoch,
        'to': ?to,
        ...payload,
      },
    );
  }

  void dispose() {
    _messages.close();
    _present.close();
  }
}

/// A channel per convoy id. Returns null when the build has no Supabase
/// project or nobody is signed in.
final convoyChannelProvider = Provider.family<ConvoyChannel?, String>((
  ref,
  convoyId,
) {
  final client = ref.watch(supabaseProvider);
  final uid = ref.watch(currentUserIdProvider);
  if (client == null || uid == null) return null;
  final ch = SupabaseConvoyChannel(client, convoyId, uid);
  ref.onDispose(() {
    ch.shutdown();
    ch.dispose();
  });
  return ch;
});
