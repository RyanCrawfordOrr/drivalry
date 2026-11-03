import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routes.dart';
import '../../../data/convoy/eta.dart';
import '../../../data/convoy/lost_sheep.dart';
import '../../../data/convoy/positions_link.dart';
import '../../../data/db/database.dart';
import '../../../data/google/routes_client.dart';
import '../../../data/push/local_notifications.dart';
import '../../../data/push/push_service.dart';
import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../tracking/tracking_controller.dart';
import '../../../tracking/tracking_models.dart';
import '../channel/convoy_channel.dart';
import '../channel/safe_send.dart';
import '../positions/peer_positions.dart';
import '../radio/data_bus.dart';

/// The leader's "regroup here" pin (docs/10 §3 `regroup`).
class RegroupPin {
  const RegroupPin({
    required this.lat,
    required this.lon,
    required this.setBy,
    required this.at,
    this.name,
  });

  final double lat;
  final double lon;
  final String setBy;
  final int at;
  final String? name;

  Map<String, Object?> toPayload() => {'lat': lat, 'lon': lon, 'name': ?name};

  static RegroupPin? fromPayload(String from, int t, Map<String, dynamic> p) {
    final lat = p['lat'];
    final lon = p['lon'];
    if (lat is! num || lon is! num) return null;
    return RegroupPin(
      lat: lat.toDouble(),
      lon: lon.toDouble(),
      setBy: from,
      at: t,
      name: p['name'] as String?,
    );
  }
}

/// Where I am heading next: an accepted stop, else the destination.
class NextTarget {
  const NextTarget({required this.point, required this.name, this.stopId});
  final LatLon point;
  final String name;
  final String? stopId;
}

/// Everything live about one convoy while it is watched: the broadcast
/// channel is joined, positions flow through [ConvoyPositionLink], my ETA is
/// published, regroup pins are received and lost sheep are detected. Pure
/// wiring: the pieces it drives are unit-tested on their own.
class ConvoyLive {
  ConvoyLive({
    required this.convoyId,
    required this.me,
    required this.channel,
    required this.link,
    required this.eta,
    required this.detector,
    required this.now,
    required this.notify,
    this.lostSheepEvery = const Duration(seconds: 30),
  });

  final String convoyId;
  final String me;
  final ConvoyChannel channel;
  final ConvoyPositionLink link;
  final EtaTracker eta;
  final LostSheepDetector detector;
  final int Function() now;
  final Future<void> Function(String title, String body) notify;
  final Duration lostSheepEvery;

  final _regroup = StreamController<RegroupPin?>.broadcast();
  RegroupPin? regroupPin;
  Stream<RegroupPin?> get regroupStream => _regroup.stream;

  final _lost = StreamController<Map<String, LostSheep>>.broadcast();
  Stream<Map<String, LostSheep>> get lostStream => _lost.stream;

  /// Supplied by the provider: who leads, who is present, where next.
  String Function() leaderId = () => '';
  Set<String> Function() members = () => const {};
  NextTarget? Function() nextTarget = () => null;

  StreamSubscription<ConvoyMessage>? _msgs;
  StreamSubscription<TrackingEvent>? _fixes;
  Timer? _timer;
  bool _started = false;

  Future<void> start(Stream<TrackingEvent> fixes) async {
    if (_started) return;
    _started = true;
    try {
      await channel.join();
    } catch (e) {
      debugPrint('convoy channel join failed: $e');
    }
    await link.start(fixes);
    _msgs = channel.messages.listen(onMessage);
    _fixes = fixes.listen(onEvent);
    _timer = Timer.periodic(lostSheepEvery, (_) => checkLostSheep());
  }

  void onMessage(ConvoyMessage m) {
    if (m.type == 'regroup') {
      if (m.from != leaderId() && m.from != me) return;
      final pin = RegroupPin.fromPayload(m.from, m.t, m.payload);
      if (pin == null) return;
      regroupPin = pin;
      _regroup.add(pin);
      if (m.from != me) {
        unawaited(
          notify(
            'Regroup',
            pin.name == null
                ? 'The leader set a regroup point.'
                : 'Regroup at ${pin.name}.',
          ),
        );
      }
    } else if (m.type == 'regroup_clear') {
      regroupPin = null;
      _regroup.add(null);
    }
  }

  void onEvent(TrackingEvent e) {
    if (e is FixesEvent && e.fixes.isNotEmpty) {
      unawaited(_updateEta(e.fixes.last));
    }
  }

  Future<void> _updateEta(Fix f) async {
    final target = nextTarget();
    if (target == null) return;
    try {
      final est = await eta.maybeUpdate(
        me: LatLon(f.lat, f.lon),
        speedMps: f.speed,
        target: target.point,
      );
      if (est == null) return;
      await link.publishEta(
        EtaInfo(
          userId: me,
          seconds: est.seconds,
          estimated: est.estimated,
          at: now(),
          distanceM: est.distanceM,
          toStopId: target.stopId,
        ),
      );
    } catch (err) {
      debugPrint('eta update failed: $err');
    }
  }

  /// Leader only: pins a regroup point for everyone. The pin shows locally
  /// either way; the result says whether the broadcast went out.
  Future<bool> setRegroup(double lat, double lon, {String? name}) async {
    final pin = RegroupPin(
      lat: lat,
      lon: lon,
      setBy: me,
      at: now(),
      name: name,
    );
    regroupPin = pin;
    _regroup.add(pin);
    return safeSend('regroup', () => channel.send('regroup', pin.toPayload()));
  }

  Future<bool> clearRegroup() async {
    regroupPin = null;
    _regroup.add(null);
    return safeSend(
      'regroup_clear',
      () => channel.send('regroup_clear', const {}),
    );
  }

  /// Evaluates lost sheep from the hub; the leader gets a notification once
  /// per episode. Everyone sees the badge on the map.
  void checkLostSheep() {
    final leader = leaderId();
    if (leader.isEmpty) return;
    final started = detector.evaluate(
      leaderId: leader,
      positions: link.hub.latest,
      members: members(),
      nowMs: now(),
      me: me,
    );
    _lost.add(detector.current);
    if (started.isNotEmpty && leader == me) {
      final who = started.length == 1 ? 'A car' : '${started.length} cars';
      final why = started.first.reason == 'silent'
          ? 'stopped sharing their position'
          : 'fell more than five minutes behind';
      unawaited(notify('Lost sheep', '$who $why.'));
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    unawaited(_msgs?.cancel());
    unawaited(_fixes?.cancel());
    await link.dispose();
    unawaited(_regroup.close());
    unawaited(_lost.close());
    try {
      await channel.leave();
    } catch (_) {}
  }
}

/// Live wiring for one convoy. Null without a cloud session. Kept alive by
/// [activeConvoyLiveProvider] for the active convoy and by the detail screen
/// for whichever convoy is open.
final convoyLiveProvider = Provider.autoDispose.family<ConvoyLive?, String>((
  ref,
  id,
) {
  final me = ref.watch(currentUserIdProvider);
  final channel = ref.watch(convoyChannelProvider(id));
  if (me == null || channel == null) return null;
  final hub = ref.watch(peerPositionHubProvider(id));
  final bus = ref.watch(convoyDataBusProvider(id));
  final db = ref.watch(databaseProvider);
  final gate = ref.watch(notificationGateProvider);
  final notifications = ref.watch(localNotificationsProvider);
  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  final live = ConvoyLive(
    convoyId: id,
    me: me,
    channel: channel,
    link: ConvoyPositionLink(
      convoyId: id,
      me: me,
      channel: channel,
      bus: bus,
      hub: hub,
      db: db,
      now: nowMs,
    ),
    eta: EtaTracker(routes: ref.watch(routesClientProvider), now: nowMs),
    detector: LostSheepDetector(),
    now: nowMs,
    notify: (title, body) async {
      try {
        if (!await gate.allows(NotificationCategory.convoy)) return;
        await notifications.show(
          category: NotificationCategory.convoy,
          title: title,
          body: body,
          route: Routes.convoyDetail(id),
        );
      } catch (e) {
        debugPrint('convoy notification failed: $e');
      }
    },
  );
  live.leaderId = () => ref.read(convoyLeaderProvider(id)) ?? '';
  live.members = () => ref.read(convoyMemberIdsProvider(id));
  live.nextTarget = () {
    final convoy = ref.read(convoyProvider(id));
    final stops = ref.read(convoyStopsProvider(id)).value ?? const [];
    for (final s in stops) {
      if (s.status == StopStatus.accepted) {
        return NextTarget(
          point: LatLon(s.lat, s.lon),
          name: s.name,
          stopId: s.id,
        );
      }
    }
    final d = convoy?.destination;
    if (d == null) return null;
    return NextTarget(point: LatLon(d.lat, d.lon), name: d.name);
  };
  // Keep the stop list warm so nextTarget has data without a screen open.
  ref.listen(convoyStopsProvider(id), (_, _) {});
  ref.listen(convoyMembersProvider(id), (_, _) {});

  final events = ref.read(trackingControllerProvider.notifier).handledEvents;
  unawaited(live.start(events));
  ref.onDispose(() => unawaited(live.dispose()));
  return live;
});

/// Keeps the active convoy live for the app's life (watched from the convoy
/// sync provider), so positions and ETAs flow with the convoy screen closed.
final activeConvoyLiveProvider = Provider<ConvoyLive?>((ref) {
  final active = ref.watch(activeConvoyProvider);
  if (active == null || !active.isActive) return null;
  return ref.watch(convoyLiveProvider(active.id));
});

final regroupPinProvider = StreamProvider.autoDispose
    .family<RegroupPin?, String>((ref, id) {
      final live = ref.watch(convoyLiveProvider(id));
      if (live == null) return const Stream.empty();
      final controller = StreamController<RegroupPin?>();
      controller.add(live.regroupPin);
      final sub = live.regroupStream.listen(controller.add);
      ref.onDispose(() async {
        await sub.cancel();
        await controller.close();
      });
      return controller.stream;
    });

final lostSheepProvider = StreamProvider.autoDispose
    .family<Map<String, LostSheep>, String>((ref, id) {
      final live = ref.watch(convoyLiveProvider(id));
      if (live == null) return const Stream.empty();
      final controller = StreamController<Map<String, LostSheep>>();
      controller.add(live.detector.current);
      final sub = live.lostStream.listen(controller.add);
      ref.onDispose(() async {
        await sub.cancel();
        await controller.close();
      });
      return controller.stream;
    });

final convoyEtasProvider = StreamProvider.autoDispose
    .family<Map<String, EtaInfo>, String>((ref, id) {
      final live = ref.watch(convoyLiveProvider(id));
      if (live == null) return const Stream.empty();
      final controller = StreamController<Map<String, EtaInfo>>();
      controller.add(Map.unmodifiable(live.link.etas));
      final sub = live.link.etaStream.listen(controller.add);
      ref.onDispose(() async {
        await sub.cancel();
        await controller.close();
      });
      return controller.stream;
    });
