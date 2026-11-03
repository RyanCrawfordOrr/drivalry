import 'package:drivalry/app/deep_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deepLinkToRoute', () {
    test('friend link opens the profile', () {
      expect(
        deepLinkToRoute(Uri.parse('drivalry://friend/abc-123')),
        '/profile/abc-123',
      );
    });

    test('league and circle invites', () {
      expect(
        deepLinkToRoute(Uri.parse('drivalry://join/league/k7x2p9')),
        '/join/league/k7x2p9',
      );
      expect(
        deepLinkToRoute(Uri.parse('DRIVALRY://join/circle/abcdef')),
        '/join/circle/abcdef',
      );
    });

    test('post link', () {
      expect(
        deepLinkToRoute(Uri.parse('drivalry://post/p1')),
        '/friends/post/p1',
      );
    });

    test('other schemes and unknown shapes are ignored', () {
      expect(
        deepLinkToRoute(Uri.parse('https://example.com/friend/x')),
        isNull,
      );
      expect(deepLinkToRoute(Uri.parse('drivalry://friend')), isNull);
      expect(deepLinkToRoute(Uri.parse('drivalry://join/league')), isNull);
      expect(deepLinkToRoute(Uri.parse('drivalry://nope/1/2/3')), isNull);
    });
  });
}
