import 'package:flutter/material.dart';

import '../../widgets/placeholder_screen.dart';

/// Weekly leagues, XP, tiers and badges.
class LeaguesScreen extends StatelessWidget {
  const LeaguesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Leagues',
      tagline: 'Weekly tables with your friends. Score and consistency climb '
          'the table. Speed never does.',
      planned: [
        "This week's table with promotion and relegation zones",
        'XP, tiers and streak bonuses',
        'Badges earned and badges in reach',
        'Head-to-head duels',
      ],
    );
  }
}
