import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'garage_screen.dart';

/// The Garage tab.
List<RouteBase> garageBranchRoutes() => [
  GoRoute(path: Routes.garage, builder: (_, _) => const GarageScreen()),
];
