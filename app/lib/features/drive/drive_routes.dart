import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../settings/diagnostics_screen.dart';
import 'drive_screen.dart';
import 'friends_map/friends_map_screen.dart';
import 'packs_screen.dart';
import 'trip_detail_screen.dart';

/// The Drive tab and everything pushed inside it.
List<RouteBase> driveBranchRoutes() => [
  GoRoute(
    path: Routes.drive,
    builder: (_, _) => const DriveScreen(),
    routes: [
      GoRoute(
        path: 'trip/:id',
        builder: (_, state) =>
            TripDetailScreen(tripId: state.pathParameters['id']!),
      ),
      GoRoute(path: 'packs', builder: (_, _) => const PacksScreen()),
      GoRoute(path: 'map', builder: (_, _) => const FriendsMapScreen()),
      GoRoute(
        path: 'diagnostics',
        builder: (_, _) => const DiagnosticsScreen(),
      ),
    ],
  ),
];
