import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/db/database.dart';
import '../../data/repos/places_repo.dart';
import '../../tracking/providers.dart';
import 'save_place_sheet.dart';

/// Saved places (Home, Work, School) with per-friend arrive/leave alerts.
class PlacesScreen extends ConsumerWidget {
  const PlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final places = ref.watch(placesProvider);
    final alerts = ref.watch(allPlaceAlertsProvider).value ?? const [];
    final list = places.value ?? const <Place>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Places')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Places stay on this phone. Long-press the friends map to save '
              'one there, or add where you are now.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (!places.isLoading && list.isEmpty)
            const ListTile(
              leading: Icon(Icons.home_outlined),
              title: Text('No places yet'),
              subtitle: Text('Start with Home: it powers auto check-ins.'),
            ),
          for (final p in list)
            ListTile(
              leading: Icon(PlaceKind.fromWire(p.kind).icon),
              title: Text(p.label),
              subtitle: Text(
                '${p.radiusM.round()} m · '
                '${alerts.where((a) => a.placeId == p.id).length} alert'
                '${alerts.where((a) => a.placeId == p.id).length == 1 ? '' : 's'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.place(p.id)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
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
