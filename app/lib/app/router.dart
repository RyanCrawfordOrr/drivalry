import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/convoy/convoy_screen.dart';
import '../features/drive/drive_screen.dart';
import '../features/drive/packs_screen.dart';
import '../features/drive/trip_detail_screen.dart';
import '../features/friends/friends_screen.dart';
import '../features/garage/garage_screen.dart';
import '../features/leagues/leagues_screen.dart';
import '../features/settings/diagnostics_screen.dart';
import 'shell.dart';

/// Route paths. Keep them here so deep links and tests share one source.
abstract final class Routes {
  static const drive = '/drive';
  static const leagues = '/leagues';
  static const friends = '/friends';
  static const convoy = '/convoy';
  static const garage = '/garage';

  static const packs = '/drive/packs';
  static const diagnostics = '/drive/diagnostics';
  static String tripDetail(String id) => '/drive/trip/$id';
}

/// One tab per bottom-navigation destination. Order matters: it is the
/// branch order in the shell and the destination order in the nav bar.
enum AppTab {
  drive(
    Routes.drive,
    'Drive',
    Icons.directions_car_outlined,
    Icons.directions_car,
  ),
  leagues(
    Routes.leagues,
    'Leagues',
    Icons.emoji_events_outlined,
    Icons.emoji_events,
  ),
  friends(Routes.friends, 'Friends', Icons.people_outline, Icons.people),
  convoy(Routes.convoy, 'Convoy', Icons.route_outlined, Icons.route),
  garage(Routes.garage, 'Garage', Icons.garage_outlined, Icons.garage);

  const AppTab(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.drive,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.drive,
                builder: (_, _) => const DriveScreen(),
                routes: [
                  GoRoute(
                    path: 'trip/:id',
                    builder: (_, state) =>
                        TripDetailScreen(tripId: state.pathParameters['id']!),
                  ),
                  GoRoute(
                    path: 'packs',
                    builder: (_, _) => const PacksScreen(),
                  ),
                  GoRoute(
                    path: 'diagnostics',
                    builder: (_, _) => const DiagnosticsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.leagues,
                builder: (_, _) => const LeaguesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.friends,
                builder: (_, _) => const FriendsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.convoy,
                builder: (_, _) => const ConvoyScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.garage,
                builder: (_, _) => const GarageScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
