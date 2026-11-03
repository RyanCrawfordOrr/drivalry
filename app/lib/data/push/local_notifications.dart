import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification channels (docs/01 §4.10). `crash` is the only one that is
/// allowed through quiet hours.
enum NotificationCategory {
  social('social', 'Reactions and comments'),
  friends('friends', 'Friend requests'),
  crash('crash', 'Crash alerts'),
  tripScored('trip_scored', 'Trip scored');

  const NotificationCategory(this.channelId, this.channelName);
  final String channelId;
  final String channelName;

  static NotificationCategory fromWire(String? wire) => switch (wire) {
    'friends' => friends,
    'crash' => crash,
    'trip_scored' => tripScored,
    _ => social,
  };

  /// `Settings` key for the per-category toggle (`'false'` disables).
  String get settingsKey => 'notify_$channelId';
}

/// Thin wrapper over flutter_local_notifications. Safe to construct in tests:
/// nothing touches the platform until [init] is called.
class LocalNotifications {
  LocalNotifications({FlutterLocalNotificationsPlugin? plugin, this.onTap})
    : _injected = plugin;

  final FlutterLocalNotificationsPlugin? _injected;
  FlutterLocalNotificationsPlugin? _created;

  /// Created on first use so that merely building the provider graph (as
  /// widget tests do) never touches the platform plugin.
  FlutterLocalNotificationsPlugin get _plugin =>
      _injected ?? (_created ??= FlutterLocalNotificationsPlugin());

  /// Called with the route payload when the user taps a notification.
  final void Function(String route)? onTap;
  bool _ready = false;
  int _nextId = 1000;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) onTap?.call(payload);
        },
      );
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        for (final c in NotificationCategory.values) {
          await android.createNotificationChannel(
            AndroidNotificationChannel(
              c.channelId,
              c.channelName,
              importance: c == NotificationCategory.crash
                  ? Importance.max
                  : Importance.defaultImportance,
            ),
          );
        }
      }
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        onTap?.call(payload);
      }
      _ready = true;
    } catch (e) {
      debugPrint('LocalNotifications.init failed: $e');
    }
  }

  /// Asks for the OS permission (Android 13+, iOS). True when granted.
  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isIOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('notification permission failed: $e');
    }
    return false;
  }

  Future<void> show({
    required NotificationCategory category,
    required String title,
    required String body,
    String? route,
    int? id,
    bool fullScreen = false,
  }) async {
    if (!_ready) return;
    final crash = category == NotificationCategory.crash;
    try {
      await _plugin.show(
        id: id ?? _nextId++,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            category.channelId,
            category.channelName,
            importance: crash ? Importance.max : Importance.defaultImportance,
            priority: crash ? Priority.max : Priority.defaultPriority,
            category: crash ? AndroidNotificationCategory.alarm : null,
            // Crash countdown: wake the screen and show over the lock screen.
            // Needs USE_FULL_SCREEN_INTENT in the manifest; on Android 14+
            // the OS may revoke it for apps it does not deem call/alarm-like,
            // in which case this degrades to a heads-up notification.
            fullScreenIntent: fullScreen,
          ),
          iOS: DarwinNotificationDetails(
            threadIdentifier: category.channelId,
            interruptionLevel: crash
                ? InterruptionLevel.timeSensitive
                : InterruptionLevel.active,
          ),
        ),
        payload: route,
      );
    } catch (e) {
      debugPrint('notification show failed: $e');
    }
  }
}
