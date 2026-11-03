import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'convoy_screen.dart';

/// The Convoy tab.
List<RouteBase> convoyBranchRoutes() => [
  GoRoute(path: Routes.convoy, builder: (_, _) => const ConvoyScreen()),
];
