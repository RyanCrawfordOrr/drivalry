import 'package:flutter/material.dart';

import '../../widgets/placeholder_screen.dart';

/// Home tab: live drive card, last trip, streak, today's distance credit.
class DriveScreen extends StatelessWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Drive',
      tagline: 'Drives start and stop on their own. This tab shows the one '
          'you are on and the one you just finished.',
      planned: [
        'Live card: speed vs limit, clean-so-far, current road',
        'Last trip: Drive Score ring, roast or praise, events timeline',
        'Passenger interstitial before a trip is scored',
        "Streak and today's distance credit (capped, never rewards distance)",
        'Simulate a drive from fixtures while native tracking is built',
      ],
    );
  }
}
