import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/providers.dart';
import 'spotify_auth.dart';
import 'spotify_client.dart';

final spotifyTokenStoreProvider = Provider<SpotifyTokenStore>(
  (ref) => SecureSpotifyTokenStore(),
);

final spotifyAuthProvider = Provider<SpotifyAuth>(
  (ref) => SpotifyAuth(
    ref.watch(httpClientProvider),
    ref.watch(spotifyTokenStoreProvider),
  ),
);

final spotifyClientProvider = Provider<SpotifyClient>(
  (ref) => SpotifyClient(
    ref.watch(httpClientProvider),
    ref.watch(spotifyAuthProvider),
  ),
);

/// Whether this phone has a Spotify account connected. Invalidate after
/// sign-in or sign-out.
final spotifySignedInProvider = FutureProvider<bool>(
  (ref) => ref.watch(spotifyAuthProvider).isSignedIn,
);
