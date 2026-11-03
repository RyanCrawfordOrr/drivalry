import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'attribution_screen.dart';
import 'notifications_settings_screen.dart';
import 'settings_screen.dart';

/// Settings is pushed over the shell (no bottom bar).
List<RouteBase> settingsRoutes() => [
  GoRoute(
    path: Routes.settings,
    builder: (_, _) => const SettingsScreen(),
    routes: [
      GoRoute(
        path: 'notifications',
        builder: (_, _) => const NotificationsSettingsScreen(),
      ),
      GoRoute(
        path: 'attribution',
        builder: (_, _) => const AttributionScreen(),
      ),
    ],
  ),
];
