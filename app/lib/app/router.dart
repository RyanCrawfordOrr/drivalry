import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/convoy/convoy_routes.dart';
import '../features/crash/crash_routes.dart';
import '../features/drive/drive_routes.dart';
import '../features/friends/friends_routes.dart';
import '../features/garage/garage_routes.dart';
import '../features/leagues/leagues_routes.dart';
import '../features/profile/profile_routes.dart';
import '../features/settings/settings_routes.dart';
import 'shell.dart';

export 'routes.dart';

/// Composes the route tree. Each feature folder owns its own routes file, so
/// features can grow without editing this file.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/drive',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: driveBranchRoutes()),
          StatefulShellBranch(routes: leaguesBranchRoutes()),
          StatefulShellBranch(routes: friendsBranchRoutes()),
          StatefulShellBranch(routes: convoyBranchRoutes()),
          StatefulShellBranch(routes: garageBranchRoutes()),
        ],
      ),
      ...settingsRoutes(),
      ...crashRoutes(),
      ...profileRoutes(),
      ...friendsTopLevelRoutes(),
      ...leaguesTopLevelRoutes(),
    ],
  );
});
