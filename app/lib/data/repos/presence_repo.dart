import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../tracking/tracking_models.dart';
import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import 'circles_sync.dart';
import 'friends_sync.dart';

/// One row of `presence` joined with the owner's profile: where a friend or
/// circle member is right now (ADR-018). RLS decides which rows come back.
class PresenceRow {
  const PresenceRow({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.lat,
    required this.lon,
    required this.driving,
    required this.updatedAt,
    this.avatarPath,
    this.speed,
    this.heading,
    this.battery,
  });

  factory PresenceRow.fromJson(Map<String, dynamic> j) {
    final profile =
        (j['profiles'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PresenceRow(
      userId: j['user_id'] as String,
      handle: profile['handle'] as String? ?? j['handle'] as String? ?? '',
      displayName:
          profile['display_name'] as String? ??
          j['display_name'] as String? ??
          '',
      avatarPath:
          profile['avatar_path'] as String? ?? j['avatar_path'] as String?,
      lat: (j['lat'] as num).toDouble(),
      lon: (j['lon'] as num).toDouble(),
      speed: (j['speed'] as num?)?.toDouble(),
      heading: (j['heading'] as num?)?.toDouble(),
      battery: (j['battery'] as num?)?.toDouble(),
      driving: j['driving'] as bool? ?? false,
      updatedAt: DateTime.parse(j['updated_at'] as String).toUtc(),
    );
  }

  final String userId;
  final String handle;
  final String displayName;
  final String? avatarPath;
  final double lat;
  final double lon;
  final double? speed;
  final double? heading;

  /// 0–1.
  final double? battery;
  final bool driving;
  final DateTime updatedAt;

  /// Display name, falling back to the handle.
  String get name => displayName.trim().isNotEmpty ? displayName : '@$handle';

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'handle': handle,
    'display_name': displayName,
    'avatar_path': avatarPath,
    'lat': lat,
    'lon': lon,
    'speed': speed,
    'heading': heading,
    'battery': battery,
    'driving': driving,
    'updated_at': updatedAt.toIso8601String(),
  };
}

/// What the owner publishes about themself.
class PresenceUpdate {
  const PresenceUpdate({
    required this.lat,
    required this.lon,
    required this.driving,
    this.speed,
    this.heading,
    this.battery,
  });

  final double lat;
  final double lon;
  final bool driving;
  final double? speed;
  final double? heading;
  final double? battery;

  Map<String, dynamic> toRow(String userId, DateTime now) => {
    'user_id': userId,
    'lat': lat,
    'lon': lon,
    'speed': speed,
    'heading': heading,
    'battery': battery,
    'driving': driving,
    'updated_at': now.toUtc().toIso8601String(),
  };
}

/// Reads and writes the `presence` table. Presence is ephemeral, so writes go
/// straight to Supabase (no outbox) and fail silently offline.
class PresenceRepo {
  PresenceRepo(this._client);

  final SupabaseClient _client;

  static const _select =
      'user_id, lat, lon, speed, heading, battery, driving, updated_at, '
      'profiles(handle, display_name, avatar_path)';

  Future<List<PresenceRow>> fetchVisible() async {
    final rows = await _client.from('presence').select(_select);
    return [for (final r in rows) PresenceRow.fromJson(r)];
  }

  Future<void> publish(String userId, PresenceUpdate update) => _client
      .from('presence')
      .upsert(update.toRow(userId, DateTime.now()), onConflict: 'user_id');

  /// Removes the owner's row (hiding turned on, signed out).
  Future<void> clear(String userId) =>
      _client.from('presence').delete().eq('user_id', userId);

  /// Everything the caller may see, refreshed on every Realtime change to
  /// `presence` and every [poll] as a fallback, only while listened to
  /// (docs/03 §7: subscribe only for what is on screen).
  Stream<List<PresenceRow>> watchVisible({
    Duration poll = const Duration(seconds: 60),
  }) {
    late StreamController<List<PresenceRow>> controller;
    RealtimeChannel? channel;
    Timer? timer;
    Timer? debounce;
    var closed = false;

    Future<void> refresh() async {
      if (closed) return;
      try {
        final rows = await fetchVisible();
        if (!closed) controller.add(rows);
      } catch (e) {
        debugPrint('presence fetch failed: $e');
      }
    }

    void scheduleRefresh() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 400), refresh);
    }

    controller = StreamController<List<PresenceRow>>(
      onListen: () {
        unawaited(refresh());
        timer = Timer.periodic(poll, (_) => refresh());
        try {
          channel = _client
              .channel('presence-${DateTime.now().microsecondsSinceEpoch}')
              .onPostgresChanges(
                event: PostgresChangeEvent.all,
                schema: 'public',
                table: 'presence',
                callback: (_) => scheduleRefresh(),
              )
              .subscribe();
        } catch (e) {
          debugPrint('presence realtime unavailable: $e');
        }
      },
      onCancel: () async {
        closed = true;
        timer?.cancel();
        debounce?.cancel();
        final c = channel;
        if (c != null) {
          try {
            await _client.removeChannel(c);
          } catch (_) {}
        }
      },
    );
    return controller.stream;
  }
}

/// Decides when the owner's position is published (docs/03 §6.2, §7):
/// at most every [minInterval] while driving, on parked fixes, on
/// foreground, and once more when a trip ends so friends see "parked". Never
/// when [isAllowed] is false (signed out, or hiding). Pure logic; the
/// provider below wires the sources.
class PresencePublisher {
  PresencePublisher({
    required this.send,
    required this.now,
    required this.isAllowed,
    this.battery,
    this.minInterval = const Duration(seconds: 30),
  });

  final Future<void> Function(PresenceUpdate update) send;
  final int Function() now;
  final bool Function() isAllowed;
  final Future<double?> Function()? battery;
  final Duration minInterval;

  int? _lastSentAt;
  bool _driving = false;
  Fix? _lastFix;

  /// The last position that was actually published, for tests and the
  /// diagnostics screen.
  PresenceUpdate? lastPublished;
  int sentCount = 0;

  Future<void> onEvent(TrackingEvent e) async {
    switch (e) {
      case PhaseEvent(phase: TripPhaseSignal.active):
        _driving = true;
      case PhaseEvent(phase: TripPhaseSignal.ended):
      case PhaseEvent(phase: TripPhaseSignal.discarded):
        _driving = false;
        final f = _lastFix;
        if (f != null) await _publish(f, driving: false, force: true);
      case FixesEvent():
        if (e.fixes.isEmpty) return;
        final f = e.fixes.last;
        _lastFix = f;
        await _publish(f, driving: _driving || (f.speed ?? 0) > 2);
      case ParkedFixEvent():
        _driving = false;
        await _publish(
          Fix(
            t: e.t,
            lat: e.lat,
            lon: e.lon,
            accuracy: e.accuracy,
            speed: e.speed,
            heading: e.heading,
          ),
          driving: false,
        );
      default:
        break;
    }
  }

  /// App came to the foreground: publish where the phone is now.
  Future<void> onForeground(
    Future<LastKnownLocation?> Function() locate,
  ) async {
    if (!isAllowed()) return;
    LastKnownLocation? l;
    try {
      l = await locate();
    } catch (e) {
      debugPrint('getLastKnownLocation failed: $e');
      return;
    }
    if (l == null) return;
    await _publish(
      Fix(
        t: l.t,
        lat: l.lat,
        lon: l.lon,
        accuracy: l.accuracy,
        speed: l.speed,
        heading: l.heading,
      ),
      driving: _driving,
    );
  }

  Future<void> _publish(
    Fix f, {
    required bool driving,
    bool force = false,
  }) async {
    if (!isAllowed()) return;
    final t = now();
    final last = _lastSentAt;
    if (!force && last != null && t - last < minInterval.inMilliseconds) {
      return;
    }
    _lastSentAt = t;
    double? b;
    try {
      b = await battery?.call();
    } catch (_) {}
    final update = PresenceUpdate(
      lat: f.lat,
      lon: f.lon,
      speed: f.speed,
      heading: f.heading,
      battery: b,
      driving: driving,
    );
    try {
      await send(update);
      lastPublished = update;
      sentCount++;
    } catch (e) {
      // Offline or signed out mid-flight: the next window retries.
      debugPrint('presence publish failed: $e');
    }
  }
}

/// What the publisher should do when the hide switch or the session changes.
enum PresenceGateAction { none, clear, publish }

/// Tracks whether publishing is allowed. The hide switch starts as *unknown*
/// (null) and unknown counts as hidden, so nothing is published before the
/// setting has been read. A foreground publish happens only on the
/// transition to visible, not on every emission of the setting stream.
class PresenceGate {
  PresenceGate({this.hidden, this.userId, this.hasAudience});

  bool? hidden;
  String? userId;

  /// Whether anyone could see the row: an accepted friend, or a circle the
  /// user is not hiding in. Null while the friend and circle lists are still
  /// loading, which counts as "someone might", so a slow load never blocks
  /// publishing. False means hiding in every audience: publish nothing.
  bool? hasAudience;

  bool get allowed => userId != null && hidden == false && hasAudience != false;

  /// Audience appears or vanishes. Vanishing clears the row (nobody could
  /// see it, so it should not sit in the table); appearing publishes.
  PresenceGateAction onAudienceChanged(bool? next) {
    final prev = hasAudience;
    hasAudience = next;
    if (userId == null || hidden != false) return PresenceGateAction.none;
    if (next == false && prev != false) return PresenceGateAction.clear;
    if (next != false && prev == false) return PresenceGateAction.publish;
    return PresenceGateAction.none;
  }

  PresenceGateAction onHiddenChanged(bool? next) {
    final prev = hidden;
    hidden = next;
    if (next == true && prev != true && userId != null) {
      return PresenceGateAction.clear;
    }
    if (next == false && prev != false && userId != null) {
      return PresenceGateAction.publish;
    }
    return PresenceGateAction.none;
  }

  PresenceGateAction onUserChanged(String? next) {
    userId = next;
    return allowed ? PresenceGateAction.publish : PresenceGateAction.none;
  }
}

// ---------------------------------------------------------------- providers --

final presenceRepoProvider = Provider<PresenceRepo?>((ref) {
  final client = ref.watch(supabaseProvider);
  return client == null ? null : PresenceRepo(client);
});

/// The global "Hide my location" switch, mirrored in the local `Settings`
/// table under `location_hidden` (the profile screen writes both).
final locationHiddenProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting('location_hidden')
      .map((v) => v == 'true'),
);

/// Whether anyone could see the owner's position: at least one accepted
/// friend, or one circle the owner is not hiding in (the circle's own
/// `hiding` flag, honoured by RLS). Null until both lists have loaded.
final presenceAudienceProvider = Provider<bool?>((ref) {
  final friends = ref.watch(friendsSnapshotProvider).value;
  final circles = ref.watch(myCirclesProvider).value;
  if (friends == null || circles == null) return null;
  return friends.friends.isNotEmpty || circles.any((c) => !c.myHiding);
});

/// Starts publishing the owner's presence for the life of the app. Watched by
/// the Drive tab. Null without a Supabase project.
final presencePublisherProvider = Provider<PresencePublisher?>((ref) {
  final repo = ref.watch(presenceRepoProvider);
  if (repo == null) return null;

  // Unknown until the setting stream has emitted: treated as hidden.
  final gate = PresenceGate(
    hidden: ref.read(locationHiddenProvider).value,
    userId: ref.read(currentUserIdProvider),
    hasAudience: ref.read(presenceAudienceProvider),
  );

  final publisher = PresencePublisher(
    send: (u) async {
      final uid = gate.userId;
      if (uid == null) return;
      await repo.publish(uid, u);
    },
    now: () => DateTime.now().millisecondsSinceEpoch,
    isAllowed: () => gate.allowed,
    battery: () async =>
        (await ref.read(trackingPortProvider).getDiagnostics()).batteryLevel,
  );

  Future<LastKnownLocation?> locate() =>
      ref.read(trackingPortProvider).getLastKnownLocation();

  void act(PresenceGateAction action, String? previousUser) {
    switch (action) {
      case PresenceGateAction.clear:
        final uid = previousUser ?? gate.userId;
        if (uid != null) unawaited(repo.clear(uid).catchError((_) {}));
      case PresenceGateAction.publish:
        unawaited(publisher.onForeground(locate));
      case PresenceGateAction.none:
        break;
    }
  }

  ref.listen(locationHiddenProvider, (_, next) {
    if (next.hasValue) act(gate.onHiddenChanged(next.value), null);
  });
  ref.listen(currentUserIdProvider, (prev, next) {
    act(gate.onUserChanged(next), prev);
  });
  // Hiding in every circle with no friends: stop publishing and drop the row.
  ref.listen(presenceAudienceProvider, (_, next) {
    act(gate.onAudienceChanged(next), null);
  });

  final events = ref
      .read(trackingControllerProvider.notifier)
      .handledEvents
      .listen(publisher.onEvent);
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(publisher.onForeground(locate)),
  );
  // The setting was already known (another screen read it): publish now.
  // Otherwise the first emission of the setting stream does it.
  if (gate.allowed) unawaited(publisher.onForeground(locate));

  ref.onDispose(() {
    events.cancel();
    lifecycle.dispose();
  });
  return publisher;
});

/// Everyone the signed-in user may see on the map, live while watched.
final visiblePresenceProvider = StreamProvider<List<PresenceRow>>((ref) {
  final repo = ref.watch(presenceRepoProvider);
  if (repo == null || ref.watch(currentUserIdProvider) == null) {
    return Stream.value(const <PresenceRow>[]);
  }
  return repo.watchVisible();
});
