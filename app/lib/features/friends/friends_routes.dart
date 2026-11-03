import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import 'add_friend_screen.dart';
import 'friend_requests_screen.dart';
import 'friends_screen.dart';
import 'join_circle_screen.dart';
import 'post_detail_screen.dart';

/// The Friends tab (feed, friends list, requests, add, post detail).
List<RouteBase> friendsBranchRoutes() => [
  GoRoute(
    path: Routes.friends,
    builder: (_, _) => const FriendsScreen(),
    routes: [
      GoRoute(
        path: 'add',
        builder: (_, state) =>
            AddFriendScreen(initialUserId: state.uri.queryParameters['user']),
      ),
      GoRoute(
        path: 'requests',
        builder: (_, _) => const FriendRequestsScreen(),
      ),
      GoRoute(
        path: 'post/:id',
        builder: (_, state) =>
            PostDetailScreen(postId: state.pathParameters['id']!),
      ),
    ],
  ),
];

/// Outside the shell: circle invite links land on a holding screen until
/// circles ship. Friend links open the profile route; league invites are
/// handled by the leagues feature.
List<RouteBase> friendsTopLevelRoutes() => [
  GoRoute(
    path: '/join/circle/:code',
    builder: (_, state) =>
        JoinCircleScreen(code: state.pathParameters['code'] ?? ''),
  ),
];
