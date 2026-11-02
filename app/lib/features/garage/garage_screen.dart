import 'package:flutter/material.dart';

import '../../widgets/placeholder_screen.dart';

/// Vehicles, settings, privacy controls, data, attribution.
class GarageScreen extends StatelessWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Garage',
      tagline: 'Your cars, your settings, your data.',
      planned: [
        'Vehicles and fuel type (feeds efficiency scoring)',
        'Units (mph or km/h from locale, overridable)',
        'Spoken cues (off by default) and roast voice',
        'Emergency contacts for crash detection',
        'Speed-limit packs: downloaded regions and storage',
        'Raw trip data: on this phone only, 90-day retention, export, delete',
        'Attribution: OpenStreetMap, Google, Open-Meteo, Nominatim',
      ],
    );
  }
}
