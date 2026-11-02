import 'package:flutter/material.dart';

import '../../widgets/placeholder_screen.dart';

/// Friends, the public roast feed, and circles (location sharing).
class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Friends',
      tagline: 'The feed where roasts land, and the circles that share '
          'where everyone is.',
      planned: [
        'Public roast feed with reactions and comments',
        'Friend handles, invites and requests',
        'Circles map with precise location by default',
        'Per-member hiding toggle that everyone can see',
        'Place alerts (arrived home, left work)',
      ],
    );
  }
}
