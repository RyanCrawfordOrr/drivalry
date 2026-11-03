import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/router.dart';
import '../../config/env.dart';
import '../db/database.dart';
import '../supabase/supabase_providers.dart';
import '../sync/outbox.dart';
import 'local_notifications.dart';
import 'quiet_hours.dart';

/// Where push registration stands, for Settings › Notifications.
sealed class PushStatus {
  const PushStatus();
}

/// No Firebase configuration in this build (docs/09 §7), or the platform
/// has no messaging.
class PushUnavailable extends PushStatus {
  const PushUnavailable(this.reason);
  final String reason;
}

class PushPermissionDenied extends PushStatus {
  const PushPermissionDenied();
}

class PushPending extends PushStatus {
  const PushPending();
}

class PushRegistered extends PushStatus {
  const PushRegistered(this.token);
  final String token;
}

/// The shared notification sink: one place that knows about quiet hours and
/// the per-category switches.
final localNotificationsProvider = Provider<LocalNotifications>((ref) {
  return LocalNotifications(
    onTap: (route) {
      try {
        ref.read(routerProvider).go(route);
      } catch (e) {
        debugPrint('notification route failed: $e');
      }
    },
  );
});

/// Decides whether a notification may be shown right now.
class NotificationGate {
  const NotificationGate(this._db, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  Future<bool> allows(NotificationCategory category) async {
    if (category == NotificationCategory.crash) return true;
    if (await _db.getSetting(category.settingsKey) == 'false') return false;
    final quiet = QuietHours.fromJson(
      await _db.getSetting(QuietHours.settingsKey),
    );
    return !quiet.isQuiet(_now());
  }
}

final notificationGateProvider = Provider<NotificationGate>(
  (ref) => NotificationGate(ref.watch(databaseProvider)),
);

/// FCM registration on both platforms (ADR note in docs/09 §7), token upload
/// through the outbox, and foreground display through [LocalNotifications].
class PushController extends Notifier<PushStatus> {
  /// Outbox kind `push_token`: `{token, platform, device_label}`.
  static const String kindToken = 'push_token';
  static const String _savedTokenKey = 'push_token';

  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  bool _started = false;

  @override
  PushStatus build() {
    ref.onDispose(() {
      _refresh?.cancel();
      _foreground?.cancel();
      _opened?.cancel();
    });
    _registerHandler();
    return Env.hasFirebase
        ? const PushPending()
        : const PushUnavailable('Push is not configured in this build.');
  }

  void _registerHandler() {
    ref.read(outboxWorkerProvider).register(kindToken, (p) async {
      final c = ref.read(supabaseProvider);
      final uid = c?.auth.currentUser?.id;
      if (c == null || uid == null) throw const OutboxRetryLater('signed out');
      await c.from('push_tokens').upsert({
        'token': p['token'],
        'user_id': uid,
        'platform': p['platform'],
        'device_label': p['device_label'],
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    });
  }

  /// Initialises Firebase and registers the device. Idempotent. No-op
  /// without configuration.
  Future<void> start() async {
    if (_started || !Env.hasFirebase) return;
    _started = true;
    final notifications = ref.read(localNotificationsProvider);
    await notifications.init();
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: Env.firebaseApiKey,
            appId: Platform.isIOS
                ? Env.firebaseAppIdIos
                : Env.firebaseAppIdAndroid,
            messagingSenderId: Env.firebaseSenderId,
            projectId: Env.firebaseProjectId,
          ),
        );
      }
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        state = const PushPermissionDenied();
        return;
      }
      await notifications.requestPermission();

      // onRegistered fires once registration completes and again on every
      // token refresh.
      _refresh = messaging.onRegistered.listen(_register);
      await messaging.register();
      _foreground = FirebaseMessaging.onMessage.listen(_onForeground);
      _opened = FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _navigate(m.data['route']),
      );
      final initial = await messaging.getInitialMessage();
      if (initial != null) _navigate(initial.data['route']);
    } catch (e) {
      debugPrint('push start failed: $e');
      state = PushUnavailable('Push could not start: $e');
    }
  }

  Future<void> _register(String token) async {
    final db = ref.read(databaseProvider);
    await db.setSetting(_savedTokenKey, token);
    final label = Platform.isIOS ? 'iPhone' : 'Android';
    await ref.read(outboxWorkerProvider).enqueue(kindToken, {
      'token': token,
      'platform': Platform.isIOS ? 'ios' : 'android',
      'device_label': label,
    }, id: '$kindToken:$token');
    state = PushRegistered(token);
  }

  /// Removes this device's token server-side. Call before signing out,
  /// while the session still exists.
  Future<void> unregister() async {
    final db = ref.read(databaseProvider);
    final token = await db.getSetting(_savedTokenKey);
    final c = ref.read(supabaseProvider);
    if (token != null && c != null && c.auth.currentUser != null) {
      try {
        await c.from('push_tokens').delete().eq('token', token);
      } catch (e) {
        debugPrint('push token delete failed: $e');
      }
    }
    if (Env.hasFirebase && Firebase.apps.isNotEmpty) {
      try {
        await FirebaseMessaging.instance.unregister();
      } catch (_) {}
    }
    await db.setSetting(_savedTokenKey, '');
    if (Env.hasFirebase) state = const PushPending();
  }

  Future<void> _onForeground(RemoteMessage m) async {
    final category = NotificationCategory.fromWire(m.data['category']);
    if (!await ref.read(notificationGateProvider).allows(category)) return;
    final title = m.notification?.title ?? m.data['title'] ?? 'Drivalry';
    final body = m.notification?.body ?? m.data['body'] ?? '';
    await ref
        .read(localNotificationsProvider)
        .show(
          category: category,
          title: title,
          body: body,
          route: m.data['route'],
        );
  }

  void _navigate(Object? route) {
    if (route is! String || route.isEmpty) return;
    try {
      ref.read(routerProvider).go(route);
    } catch (e) {
      debugPrint('push route failed: $e');
    }
  }
}

final pushControllerProvider = NotifierProvider<PushController, PushStatus>(
  PushController.new,
);

/// Platform label used in `push_tokens.platform`.
String pushPlatformLabel() => Platform.isIOS ? 'ios' : 'android';

/// Signed-in client helper for tests.
bool hasSession(SupabaseClient? c) => c?.auth.currentUser != null;
