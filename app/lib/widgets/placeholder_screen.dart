import 'package:flutter/material.dart';

import '../app/ui/ui.dart';

/// Temporary body for tabs whose feature has not been built yet: the same
/// empty-state grammar as the rest of the app, then what is coming.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    super.key,
    required this.title,
    required this.tagline,
    required this.planned,
  });

  final String title;
  final String tagline;
  final List<String> planned;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxxl),
        children: [
          EmptyState(
            kicker: title,
            headline: 'Not available in this version yet.',
            body: tagline,
          ),
          EditorialSection(
            kicker: 'Coming soon',
            gap: 0,
            child: Tile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < planned.length; i++) ...[
                    if (i > 0) const SizedBox(height: Space.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Container(
                            width: Space.sm,
                            height: Space.sm,
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(child: Text(planned[i], style: context.body)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
