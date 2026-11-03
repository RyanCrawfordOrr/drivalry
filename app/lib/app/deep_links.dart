import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Maps an invite or share link to an in-app route, or null when it is not
/// ours. Links use the custom scheme [Routes.scheme]:
///
/// - `drivalry://friend/<userId>`      → that user's profile
/// - `drivalry://join/league/<code>`   → join a league
/// - `drivalry://join/circle/<code>`   → join a circle
/// - `drivalry://post/<postId>`        → a feed post
String? deepLinkToRoute(Uri uri) {
  if (uri.scheme.toLowerCase() != Routes.scheme) return null;
  final parts = [
    uri.host,
    ...uri.pathSegments,
  ].where((s) => s.isNotEmpty).toList();
  switch (parts) {
    case ['friend', final id]:
      return Routes.userProfile(id);
    case ['join', 'league', final code]:
      return Routes.joinLeague(code);
    case ['join', 'circle', final code]:
      return Routes.joinCircle(code);
    case ['post', final id]:
      return Routes.post(id);
    default:
      return null;
  }
}

/// Where links come from. The app uses [AppLinksSource]; tests use
/// [NoDeepLinks].
abstract class DeepLinkSource {
  Future<Uri?> initialLink();
  Stream<Uri> get links;
}

class AppLinksSource implements DeepLinkSource {
  final AppLinks _links = AppLinks();

  @override
  Future<Uri?> initialLink() => _links.getInitialLink();

  @override
  Stream<Uri> get links => _links.uriLinkStream;
}

class NoDeepLinks implements DeepLinkSource {
  const NoDeepLinks();

  @override
  Future<Uri?> initialLink() async => null;

  @override
  Stream<Uri> get links => const Stream.empty();
}

final deepLinkSourceProvider = Provider<DeepLinkSource>(
  (ref) => AppLinksSource(),
);

/// Listens for links for the life of the app and pushes the matching route.
/// Watched by the Drive and Friends screens.
final deepLinksProvider = Provider<void>((ref) {
  final source = ref.watch(deepLinkSourceProvider);
  final router = ref.watch(routerProvider);

  void open(Uri uri) {
    final route = deepLinkToRoute(uri);
    if (route == null) {
      debugPrint('ignored link $uri');
      return;
    }
    router.push(route);
  }

  unawaited(
    source
        .initialLink()
        .then((uri) {
          if (uri != null) open(uri);
        })
        .catchError((Object e) {
          debugPrint('initial link unavailable: $e');
        }),
  );
  final sub = source.links.listen(
    open,
    onError: (Object e) => debugPrint('link stream error: $e'),
  );
  ref.onDispose(sub.cancel);
});
