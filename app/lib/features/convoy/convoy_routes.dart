import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'album/convoy_album_screen.dart';
import 'chat/convoy_chat_screen.dart';
import 'convoy_detail_screen.dart';
import 'convoy_screen.dart';
import 'create_convoy_screen.dart';
import 'expenses/convoy_expenses_screen.dart';
import 'games/convoy_games_screen.dart';
import 'join_convoy_screen.dart';
import 'music/convoy_music_screen.dart';
import 'radio/convoy_radio_screen.dart';
import 'recap/convoy_recap_screen.dart';
import 'stops/convoy_stops_screen.dart';

String _id(GoRouterState s) => s.pathParameters['id'] ?? '';

/// The Convoy tab: my convoys, then one convoy and its sub-screens.
List<RouteBase> convoyBranchRoutes() => [
  GoRoute(
    path: Routes.convoy,
    builder: (_, _) => const ConvoyScreen(),
    routes: [
      GoRoute(path: 'new', builder: (_, _) => const CreateConvoyScreen()),
      GoRoute(
        path: ':id',
        builder: (_, s) => ConvoyDetailScreen(convoyId: _id(s)),
        routes: [
          GoRoute(
            path: 'radio',
            builder: (_, s) => ConvoyRadioScreen(
              convoyId: _id(s),
              // The Talk button opens the radio already running.
              autoStart: s.uri.queryParameters['start'] == '1',
            ),
          ),
          GoRoute(
            path: 'stops',
            builder: (_, s) => ConvoyStopsScreen(convoyId: _id(s)),
          ),
          GoRoute(
            path: 'chat',
            builder: (_, s) => ConvoyChatScreen(convoyId: _id(s)),
          ),
          GoRoute(
            path: 'music',
            builder: (_, s) => ConvoyMusicScreen(convoyId: _id(s)),
          ),
          GoRoute(
            path: 'games',
            builder: (_, s) => ConvoyGamesScreen(convoyId: _id(s)),
          ),
          GoRoute(
            path: 'expenses',
            builder: (_, s) => ConvoyExpensesScreen(convoyId: _id(s)),
          ),
          GoRoute(
            path: 'album',
            builder: (_, s) => ConvoyAlbumScreen(convoyId: _id(s)),
          ),
          GoRoute(
            path: 'recap',
            builder: (_, s) => ConvoyRecapScreen(convoyId: _id(s)),
          ),
        ],
      ),
    ],
  ),
];

/// Outside the shell: convoy invite links join through the RPC.
List<RouteBase> convoyTopLevelRoutes() => [
  GoRoute(
    path: '/join/convoy/:code',
    builder: (_, s) => JoinConvoyScreen(code: s.pathParameters['code'] ?? ''),
  ),
];
