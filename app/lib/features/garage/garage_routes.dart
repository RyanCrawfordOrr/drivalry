import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'garage_screen.dart';
import 'vehicle_detail_screen.dart';
import 'vehicle_edit_screen.dart';

/// The Garage tab: vehicles, add, detail, edit.
List<RouteBase> garageBranchRoutes() => [
  GoRoute(
    path: Routes.garage,
    builder: (_, _) => const GarageScreen(),
    routes: [
      GoRoute(
        path: 'vehicle/new',
        builder: (_, _) => const VehicleEditScreen(),
      ),
      GoRoute(
        path: 'vehicle/:id',
        builder: (_, state) =>
            VehicleDetailScreen(vehicleId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (_, state) =>
                VehicleEditScreen(vehicleId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  ),
];
