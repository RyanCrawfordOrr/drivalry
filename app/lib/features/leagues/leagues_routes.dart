import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../badges/badges_screen.dart';
import 'create_league_screen.dart';
import 'join_league_screen.dart';
import 'league_screen.dart';
import 'leagues_screen.dart';

/// Badges live under the Leagues tab.
const String badgesPath = '/leagues/badges';

/// The Leagues tab: list, create, badges, one league.
List<RouteBase> leaguesBranchRoutes() => [
  GoRoute(
    path: Routes.leagues,
    builder: (_, _) => const LeaguesScreen(),
    routes: [
      GoRoute(path: 'new', builder: (_, _) => const CreateLeagueScreen()),
      GoRoute(path: 'badges', builder: (_, _) => const BadgesScreen()),
      GoRoute(
        path: ':id',
        builder: (_, state) =>
            LeagueScreen(leagueId: state.pathParameters['id']!),
      ),
    ],
  ),
];

/// Invite deep links (`drivalry://join/league/<code>`) land outside the shell.
List<RouteBase> leaguesTopLevelRoutes() => [
  GoRoute(
    path: '/join/league/:code',
    builder: (_, state) =>
        JoinLeagueScreen(code: state.pathParameters['code']!),
  ),
];
