import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/brand/drivalry_mark.dart';
import '../../app/ui/ui.dart';

/// About: the mark, one line on what Drivalry is, then a section per free
/// data source: the source as the kicker, one plain sentence on what it gives
/// you, and the credit or link as a caption (ADR-012, docs/12 §7).
class AttributionScreen extends StatelessWidget {
  const AttributionScreen({super.key});

  static const String licenceUrl =
      'https://github.com/RyanCrawfordOrr/drivalry/blob/main/LICENSE';

  /// (source, sentence, credit shown as a caption, full URL).
  static const List<(String, String, String, String)> entries = [
    (
      'OpenStreetMap',
      'Road shapes and speed limits, drawn by volunteer mappers around the '
          'world.',
      '© OpenStreetMap contributors',
      'https://www.openstreetmap.org/copyright',
    ),
    (
      'Google',
      'The maps you see, and the stops and arrival times in a convoy.',
      'cloud.google.com/maps-platform',
      'https://cloud.google.com/maps-platform/terms',
    ),
    (
      'Open-Meteo',
      'The weather at the start of each trip.',
      'open-meteo.com',
      'https://open-meteo.com/',
    ),
    (
      'Nominatim',
      'Names for the places you save.',
      'nominatim.org',
      'https://nominatim.org/',
    ),
    (
      'Geofabrik',
      'Where the roads for each region come from.',
      'download.geofabrik.de',
      'https://download.geofabrik.de/',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: EdgeInsets.only(
          top: Space.lg,
          bottom: Space.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Reveal(
            child: Padding(
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
          ),
          const SizedBox(height: Space.section),
          for (var i = 0; i < entries.length; i++)
            Reveal(
              delay: Reveal.stagger(i + 1),
              child: EditorialSection(
                kicker: entries[i].$1,
                child: _SourceTile(
                  sentence: entries[i].$2,
                  credit: entries[i].$3,
                  url: entries[i].$4,
                ),
              ),
            ),
          Reveal(
            delay: Reveal.stagger(entries.length + 1),
            child: EditorialSection(
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
    required this.credit,
    required this.url,
  });

  final String sentence;
  final String credit;
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
                Text(credit, style: context.caption),
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
