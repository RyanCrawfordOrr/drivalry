import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'profile_screen.dart';
import 'sign_in_screen.dart';

/// Sign-in and profiles are pushed over the shell (no bottom bar).
List<RouteBase> profileRoutes() => [
  GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
  GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen()),
  GoRoute(
    path: '/profile/:id',
    builder: (_, state) => ProfileScreen(userId: state.pathParameters['id']),
  ),
];
