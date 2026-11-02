import 'package:flutter/material.dart';

import '../../widgets/placeholder_screen.dart';

/// Road-trip convoys: shared map, push-to-talk, stops, music, expenses.
class ConvoyScreen extends StatelessWidget {
  const ConvoyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Convoy',
      tagline: 'Two to six cars, one trip. Everyone sees everyone, and the '
          'radio is one button away.',
      planned: [
        'Live convoy map with ETAs for every car',
        'Push-to-talk radio (peer-to-peer)',
        'Stop suggestions and votes',
        'Convoy DJ and Spotify Jam / SharePlay links',
        'Shared expenses and photo roll',
      ],
    );
  }
}
