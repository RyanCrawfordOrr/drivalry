import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'crash_countdown_screen.dart';

/// The crash countdown is pushed over everything, including the shell.
List<RouteBase> crashRoutes() => [
  GoRoute(path: Routes.crash, builder: (_, _) => const CrashCountdownScreen()),
];
