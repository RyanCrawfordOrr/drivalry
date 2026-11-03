import 'package:drivalry/app/deep_links.dart';
import 'package:drivalry/app/router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every deep-link target resolves to a registered route', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    for (final link in [
      'drivalry://join/circle/abc12345',
      'drivalry://join/league/k7x2p9',
      'drivalry://friend/user-1',
      'drivalry://post/p1',
    ]) {
      final route = deepLinkToRoute(Uri.parse(link));
      expect(route, isNotNull, reason: link);
      final match = router.configuration.findMatch(Uri.parse(route!));
      expect(match.isError, isFalse, reason: '$link -> $route');
      expect(match.matches, isNotEmpty, reason: '$link -> $route');
    }
  });
}
