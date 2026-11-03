import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/garage/vehicle_matcher.dart';
import '../../data/repos/garage_repo.dart';
import '../../tracking/providers.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/units.dart';

/// Your cars: stats, fuel, maintenance, documents (docs/01 §4.7). Vehicles
/// are tiles with a 48 px icon disc, a name and one caption line; the empty
/// garage is one headline and one button.
class GarageScreen extends ConsumerWidget {
  const GarageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the matcher and the daily reminder check alive on this tab too.
    ref.watch(vehicleMatcherProvider);
    ref.watch(maintenanceRemindersProvider);

    final vehicles = ref.watch(vehiclesProvider);
    final ignored = ref.watch(ignoredBluetoothNamesProvider).value ?? const [];
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final hasVehicles = vehicles.value?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Garage')),
      floatingActionButton: hasVehicles
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.newVehicle),
              icon: const Icon(Icons.add),
              label: const Text('Add vehicle'),
            )
          : null,
      body: vehicles.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xxxl,
          ),
          children: const [
            SkeletonTile(),
            SizedBox(height: Space.md),
            SkeletonTile(),
          ],
        ),
        error: (e, _) => EmptyState(
          kicker: 'Garage',
          headline: 'Could not load your garage.',
          body: friendlyError(e, doing: 'load your garage'),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            Space.xxxl + Space.xxl,
          ),
          children: [
            if (list.isEmpty)
              EmptyState(
                kicker: 'Garage',
                headline: 'Add your car.',
                body:
                    'Trips get credited to it, and the app can spot its '
                    'Bluetooth.',
                actionLabel: 'Add vehicle',
                onAction: () => context.push(Routes.newVehicle),
              )
            else
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const SizedBox(height: Space.md),
                _VehicleTile(vehicle: list[i], units: units),
              ],
            if (ignored.isNotEmpty) ...[
              const SizedBox(height: Space.section),
              EditorialSection(
                kicker: 'Not my cars',
                padding: EdgeInsets.zero,
                gap: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rides in these count as passenger trips.',
                      style: context.caption,
                    ),
                    const SizedBox(height: Space.md),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        for (final n in ignored)
                          InputChip(
                            label: Text(n),
                            deleteButtonTooltipMessage: 'Forget',
                            onDeleted: () => _unignore(ref, ignored, n),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _unignore(WidgetRef ref, List<String> all, String name) => ref
      .read(databaseProvider)
      .setSetting(
        VehicleMatcher.ignoredNamesKey,
        VehicleMatcher.encodeNames(all.where((n) => n != name)),
      );
}

class _VehicleTile extends ConsumerWidget {
  const _VehicleTile({required this.vehicle, required this.units});

  final Vehicle vehicle;
  final SpeedUnits units;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(vehicleStatsProvider(vehicle.id)).value;
    final model = [
      vehicle.year?.toString(),
      vehicle.make,
      vehicle.model,
    ].whereType<String>().join(' ');
    final caption = <String>[
      if (model.isNotEmpty) model,
      if (stats != null)
        stats.trips == 0
            ? 'No trips yet'
            : '${stats.trips} ${stats.trips == 1 ? 'trip' : 'trips'}',
      if (stats != null && stats.trips > 0)
        formatDistance(stats.distanceM, units),
      if (stats?.averageScore != null) 'avg ${stats!.averageScore!.round()}',
    ].join(' · ');
    return Tile(
      onTap: () => context.push(Routes.vehicle(vehicle.id)),
      child: Row(
        children: [
          Container(
            width: Sizes.touch,
            height: Sizes.touch,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              vehicle.neverTrack
                  ? Icons.no_crash_outlined
                  : Icons.directions_car_filled_outlined,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        vehicle.name,
                        style: context.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (vehicle.neverTrack) ...[
                      const SizedBox(width: Space.sm),
                      const Pill('Never tracked', compact: true),
                    ],
                  ],
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    caption,
                    style: context.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
