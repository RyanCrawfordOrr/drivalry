import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Credits for the free data and services Drivalry is built on (ADR-012).
class AttributionScreen extends StatelessWidget {
  const AttributionScreen({super.key});

  static const List<(String, String, String)> entries = [
    (
      'OpenStreetMap',
      'Speed limits and road geometry come from OpenStreetMap data, '
          '© OpenStreetMap contributors, available under the Open Database '
          'Licence (ODbL).',
      'https://www.openstreetmap.org/copyright',
    ),
    (
      'Google Maps Platform',
      'Maps are rendered by the Google Maps SDK. Place suggestions and '
          'route estimates in convoys use the Places and Routes APIs.',
      'https://cloud.google.com/maps-platform/terms',
    ),
    (
      'Open-Meteo',
      'Weather at the start of each trip comes from the Open-Meteo API '
          '(CC BY 4.0, non-commercial).',
      'https://open-meteo.com/',
    ),
    (
      'Nominatim',
      'Place names for saved places use the OpenStreetMap Nominatim '
          'geocoder, sparingly and cached.',
      'https://nominatim.org/',
    ),
    (
      'Geofabrik',
      'Regional OpenStreetMap extracts used to build the speed-limit packs.',
      'https://download.geofabrik.de/',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attribution')),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final (name, text, url) in entries)
            Card(
              child: ListTile(
                title: Text(name),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(text),
                ),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Drivalry is free, open source (MIT) and runs on free tiers. '
              'Raw GPS never leaves your phone.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
