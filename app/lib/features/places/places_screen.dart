import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/repos/places_repo.dart';
import '../../tracking/providers.dart';
import '../../widgets/units.dart';
import '../friends/feed_view.dart' show fabClearance;
import 'radius_text.dart';
import 'save_place_sheet.dart';

/// Saved places (Home, Work, School) with per-friend arrive/leave alerts.
/// Adding where you are is the empty state's one button, then the FAB.
class PlacesScreen extends ConsumerWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placesProvider);
    final alerts = ref.watch(allPlaceAlertsProvider).value ?? const [];
    final list = places.value ?? const <Place>[];
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final skeletons = places.isLoading && list.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Places')),
      body: ListView(
        padding: const EdgeInsets.only(top: Space.lg, bottom: fabClearance),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.section,
            ),
            child: Text(
              'Saved on this phone only. Long-press the map to add one, or '
              'add where you are.',
              style: context.bodyMuted,
            ),
          ),
          StateSwitcher(
            child: skeletons
                ? const Padding(
                    key: ValueKey('skeleton'),
                    padding: Space.screen,
                    child: SkeletonTile(),
                  )
                : list.isEmpty
                ? EmptyState(
                    key: const ValueKey('empty'),
                    kicker: 'Places',
                    headline: 'No places yet.',
                    body: 'Start with Home. It powers check-ins and alerts.',
                    actionLabel: 'Add where I am',
                    onAction: () => _addHere(context, ref),
                  )
                : EditorialSection(
                    key: const ValueKey('list'),
                    kicker: 'Saved',
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          Reveal(
                            delay: Reveal.stagger(i),
                            child: _PlaceTile(
                              place: list[i],
                              alerts: alerts
                                  .where((a) => a.placeId == list[i].id)
                                  .length,
                              units: units,
                            ),
                          ),
                          if (i < list.length - 1)
                            const SizedBox(height: Space.md),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: list.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addHere(context, ref),
              icon: const Icon(Icons.my_location),
              label: const Text('Add where I am'),
            ),
    );
  }

  Future<void> _addHere(BuildContext context, WidgetRef ref) async {
    final loc = await ref.read(trackingPortProvider).getLastKnownLocation();
    if (!context.mounted) return;
    if (loc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No location yet. Allow location in Drive, or long-press the map.',
          ),
        ),
      );
      return;
    }
    await showSavePlaceSheet(context, lat: loc.lat, lon: loc.lon);
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.place,
    required this.alerts,
    required this.units,
  });

  final Place place;
  final int alerts;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context) {
    final kind = PlaceKind.fromWire(place.kind);
    return Tile(
      onTap: () => context.push(Routes.place(place.id)),
      child: Row(
        children: [
          Icon(kind.icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.label,
                  style: context.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  '${radiusText(place.radiusM, units)} · '
                  '$alerts alert${alerts == 1 ? '' : 's'}',
                  style: context.caption,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
