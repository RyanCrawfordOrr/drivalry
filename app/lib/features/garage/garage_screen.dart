import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/db/database.dart';
import '../../data/garage/vehicle_matcher.dart';
import '../../data/repos/garage_repo.dart';
import '../../tracking/providers.dart';
import '../../widgets/units.dart';

/// Your cars: stats, fuel, maintenance, documents (docs/01 §4.7).
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Garage')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.newVehicle),
        icon: const Icon(Icons.add),
        label: const Text('Add vehicle'),
      ),
      body: vehicles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load vehicles: $e')),
        data: (list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.garage_outlined,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text('No vehicles yet', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Add your car so trips are credited to it, or wait for '
                      'the app to notice its Bluetooth and ask.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              )
            else
              for (final v in list) _VehicleTile(vehicle: v, units: units),
            if (ignored.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Ignored car audio', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Rides in these are treated as passenger trips.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final n in ignored)
                    InputChip(
                      label: Text(n),
                      onDeleted: () => _unignore(ref, ignored, n),
                    ),
                ],
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
    final stats = ref.watch(vehicleStatsProvider(vehicle.id)).value;
    final subtitle = <String>[
      if (vehicle.year != null || vehicle.make != null || vehicle.model != null)
        [
          vehicle.year?.toString(),
          vehicle.make,
          vehicle.model,
        ].whereType<String>().join(' '),
      if (stats != null)
        '${stats.trips} trips · ${formatDistance(stats.distanceM, units)}'
            '${stats.averageScore == null ? '' : ' · avg ${stats.averageScore!.round()}'}',
      if (vehicle.neverTrack) 'Never tracked',
    ].where((s) => s.isNotEmpty).join('\n');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          vehicle.neverTrack
              ? Icons.no_crash_outlined
              : Icons.directions_car_filled_outlined,
        ),
        title: Text(vehicle.name),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        isThreeLine: subtitle.contains('\n'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.vehicle(vehicle.id)),
      ),
    );
  }
}
