import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../badges/badges_screen.dart';
import '../seasons/seasons_screen.dart';
import 'create_league_screen.dart';
import 'duels/duels_screen.dart';
import 'join_league_screen.dart';
import 'league_screen.dart';
import 'leagues_screen.dart';

/// Badges live under the Leagues tab.
const String badgesPath = '/leagues/badges';

/// Duels live under the Leagues tab too (docs/02 §12.1).
const String duelsPath = '/leagues/duels';

/// The Leagues tab: list, create, badges, duels, seasons, one league.
List<RouteBase> leaguesBranchRoutes() => [
  GoRoute(
    path: Routes.leagues,
    builder: (_, _) => const LeaguesScreen(),
    routes: [
      GoRoute(path: 'new', builder: (_, _) => const CreateLeagueScreen()),
      GoRoute(path: 'badges', builder: (_, _) => const BadgesScreen()),
      GoRoute(path: 'duels', builder: (_, _) => const DuelsScreen()),
      GoRoute(path: 'seasons', builder: (_, _) => const SeasonsScreen()),
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
