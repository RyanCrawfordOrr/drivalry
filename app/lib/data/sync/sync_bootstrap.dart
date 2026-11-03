import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/profile_repo.dart';
import '../badges/badges_sync.dart';
import '../push/push_service.dart';
import '../repos/circles_sync.dart';
import '../repos/convoy_sync.dart';
import '../repos/friends_sync.dart';
import '../push/trip_scored_notifications.dart';
import '../supabase/supabase_providers.dart';
import 'limit_flags_sync.dart';
import 'outbox.dart';
import 'trip_upload.dart';

/// Wires every cloud-sync piece together once per app run (docs/03 §7):
/// registers outbox handlers, starts the watchers, and drains the outbox on
/// start, on reconnect, on sign-in and every two minutes.
///
/// Sibling features register their own handlers from their own providers;
/// see the hooks at the bottom of [syncBootstrapProvider].
class SyncBootstrap {
  SyncBootstrap({
    required this.outbox,
    required this.uploader,
    required this.flags,
    required this.tripScored,
    required this.push,
    this.enabled = true,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  /// False for an offline build (no Supabase client) and in widget tests:
  /// handlers stay registered, but no watcher, timer, plugin or network
  /// activity starts. Nothing could be uploaded anyway.
  final bool enabled;

  final OutboxWorker outbox;
  final TripUploader uploader;
  final LimitFlagsSync flags;
  final TripScoredNotifier tripScored;
  final PushController push;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _net;
  Timer? _timer;
  bool _started = false;

  static const Duration period = Duration(minutes: 2);

  Future<void> start() async {
    if (_started || !enabled) return;
    _started = true;
    uploader.start();
    flags.start();
    tripScored.start();
    unawaited(push.start());
    try {
      _net = _connectivity.onConnectivityChanged.listen(
        (results) {
          if (results.any((r) => r != ConnectivityResult.none)) {
            unawaited(outbox.drain());
          }
        },
        // No connectivity plugin on this platform (tests): the timer covers it.
        onError: (Object e) => debugPrint('connectivity unavailable: $e'),
        cancelOnError: true,
      );
    } catch (e) {
      // No connectivity plugin on this platform (tests): the timer covers it.
      debugPrint('connectivity unavailable: $e');
    }
    _timer = Timer.periodic(period, (_) => unawaited(tick()));
    await tick();
  }

  /// One sync pass: drain the outbox, pull overrides when due.
  Future<void> tick() async {
    try {
      await outbox.drain();
    } catch (e) {
      debugPrint('outbox drain failed: $e');
    }
    try {
      await flags.pullIfDue();
    } catch (e) {
      debugPrint('overrides pull failed: $e');
    }
  }

  /// Called when a session appears: everything queued while signed out can
  /// go now, and the device token is (re)sent.
  Future<void> onSignedIn() async {
    await tick();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _net?.cancel();
    await uploader.stop();
    await flags.stop();
    await tripScored.stop();
  }
}

final syncBootstrapProvider = Provider<SyncBootstrap>((ref) {
  // Handlers owned here.
  ref.watch(profileRepoProvider).registerHandlers();
  final boot = SyncBootstrap(
    enabled: ref.watch(supabaseProvider) != null,
    outbox: ref.watch(outboxWorkerProvider),
    uploader: ref.watch(tripUploaderProvider),
    flags: ref.watch(limitFlagsSyncProvider),
    tripScored: ref.watch(tripScoredNotifierProvider),
    push: ref.watch(pushControllerProvider.notifier),
  );

  // Sibling features register their own outbox handlers when first read;
  // watching them here keeps them alive for the app's life.
  ref.watch(friendsSyncProvider);
  ref.watch(badgesSyncProvider);
  ref.watch(circlesSyncProvider);
  ref.watch(convoySyncProvider);

  ref.listen(authStateProvider, (prev, next) {
    final session = next.value?.session;
    if (session != null && prev?.value?.session?.user.id != session.user.id) {
      unawaited(boot.onSignedIn());
    }
  });
  ref.onDispose(boot.dispose);
  unawaited(boot.start());
  return boot;
});
