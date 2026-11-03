import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../stats/stats_screen.dart';
import '../stats/wrapped_screen.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';

/// Sign-in and profiles are pushed over the shell (no bottom bar).
List<RouteBase> profileRoutes() => [
  GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
  GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
  // Static paths first: `/profile/:id` would otherwise swallow them.
  GoRoute(path: Routes.stats, builder: (_, _) => const StatsScreen()),
  GoRoute(path: Routes.wrapped, builder: (_, _) => const WrappedScreen()),
  GoRoute(
    path: '/profile/:id',
    builder: (_, state) => ProfileScreen(userId: state.pathParameters['id']),
  ),
];
