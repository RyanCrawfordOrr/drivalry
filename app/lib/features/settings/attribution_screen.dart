import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/brand/drivalry_mark.dart';
import '../../app/ui/ui.dart';

/// About: the mark, one line on what Drivalry is, then a section per free
/// data source with one plain sentence each (ADR-012, docs/12 §7).
class AttributionScreen extends StatelessWidget {
  const AttributionScreen({super.key});

  static const String licenceUrl =
      'https://github.com/RyanCrawfordOrr/drivalry/blob/main/LICENSE';

  /// (name, sentence, link shown as a caption, full URL).
  static const List<(String, String, String, String)> entries = [
    (
      'OpenStreetMap',
      'Road shapes and speed limits come from OpenStreetMap contributors.',
      'openstreetmap.org/copyright',
      'https://www.openstreetmap.org/copyright',
    ),
    (
      'Google Maps Platform',
      'Maps, convoy stops and arrival times come from Google.',
      'cloud.google.com/maps-platform',
      'https://cloud.google.com/maps-platform/terms',
    ),
    (
      'Open-Meteo',
      'The weather at the start of each trip comes from Open-Meteo.',
      'open-meteo.com',
      'https://open-meteo.com/',
    ),
    (
      'Nominatim',
      'Names for your saved places come from Nominatim, part of '
          'OpenStreetMap.',
      'nominatim.org',
      'https://nominatim.org/',
    ),
    (
      'Geofabrik',
      'The regional road files behind the speed-limit packs come from '
          'Geofabrik.',
      'download.geofabrik.de',
      'https://download.geofabrik.de/',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xxxl),
        children: [
          Padding(
            padding: Space.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DrivalryMark.tile(size: 72),
                const SizedBox(height: Space.lg),
                Text('Drivalry', style: context.headline),
                const SizedBox(height: Space.sm),
                Text(
                  'Free, open source, built on free services.',
                  style: context.body,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.section),
          for (final (name, sentence, link, url) in entries)
            EditorialSection(
              kicker: name,
              child: _SourceTile(sentence: sentence, link: link, url: url),
            ),
          EditorialSection(
            kicker: 'Licence',
            gap: 0,
            child: Tile(
              onTap: () => _open(licenceUrl),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Free to use, read and change.',
                          style: context.body,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'Raw GPS never leaves your phone.',
                          style: context.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  const Pill('MIT'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.sentence,
    required this.link,
    required this.url,
  });

  final String sentence;
  final String link;
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tile(
      onTap: () => AttributionScreen._open(url),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sentence, style: context.body),
                const SizedBox(height: Space.xs),
                Text(link, style: context.caption),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Icon(Icons.open_in_new, size: 18, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
