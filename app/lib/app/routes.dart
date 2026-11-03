import 'package:flutter/material.dart';

/// Route paths. One source for navigation, deep links and tests. Feature
/// folders own their `GoRoute` trees (`<feature>_routes.dart`); this file
/// only names the paths.
abstract final class Routes {
  // Tab roots (shell branches, in nav-bar order).
  static const drive = '/drive';
  static const leagues = '/leagues';
  static const friends = '/friends';
  static const convoy = '/convoy';
  static const garage = '/garage';

  // Drive branch.
  static const packs = '/drive/packs';
  static const diagnostics = '/drive/diagnostics';
  static const friendsMap = '/drive/map';
  static String tripDetail(String id) => '/drive/trip/$id';

  // Leagues branch.
  static const createLeague = '/leagues/new';
  static String league(String id) => '/leagues/$id';

  // Friends branch.
  static const addFriend = '/friends/add';
  static const friendRequests = '/friends/requests';
  static String post(String id) => '/friends/post/$id';

  // Top-level (pushed over the shell, no bottom bar).
  static const settings = '/settings';
  static const notificationsSettings = '/settings/notifications';
  static const attribution = '/settings/attribution';
  static const signIn = '/sign-in';
  static const profile = '/profile';
  static String userProfile(String id) => '/profile/$id';
  static String joinLeague(String code) => '/join/league/$code';
  static String joinCircle(String code) => '/join/circle/$code';

  /// Custom URL scheme used by invite links: `drivalry://join/league/<code>`.
  static const scheme = 'drivalry';
}

/// One tab per bottom-navigation destination. Order matters: it is the
/// branch order in the shell and the destination order in the nav bar.
enum AppTab {
  drive(
    Routes.drive,
    'Drive',
    Icons.directions_car_outlined,
    Icons.directions_car,
  ),
  leagues(
    Routes.leagues,
    'Leagues',
    Icons.emoji_events_outlined,
    Icons.emoji_events,
  ),
  friends(Routes.friends, 'Friends', Icons.people_outline, Icons.people),
  convoy(Routes.convoy, 'Convoy', Icons.route_outlined, Icons.route),
  garage(Routes.garage, 'Garage', Icons.garage_outlined, Icons.garage);

  const AppTab(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
