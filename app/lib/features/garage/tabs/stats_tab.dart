import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/garage/fuel_math.dart';
import '../../../data/repos/garage_repo.dart';
import '../../../widgets/relative_time.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/units.dart';

/// Trips, distance, average score, fuel economy and odometer for one vehicle.
class StatsTab extends ConsumerWidget {
  const StatsTab({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final imperial = unitLabel(units) == 'mph';
    final stats = ref.watch(vehicleStatsProvider(vehicle.id)).value;
    final fuel = ref.watch(fuelStatsProvider(vehicle.id));
    final odo = ref.watch(odometerEstimateProvider(vehicle.id)).value;
    final theme = Theme.of(context);

    String score(double? v) => v == null ? '–' : v.round().toString();

    final tiles = <(String, String, String?)>[
      ('Trips', '${stats?.trips ?? 0}', null),
      (
        'Distance',
        formatDistance(stats?.distanceM ?? 0, units),
        'scored and unscored',
      ),
      ('Average score', score(stats?.averageScore), 'scored driver trips'),
      ('Last 30 days', score(stats?.averageScore30d), null),
      (
        'Fuel economy',
        formatEconomy(fuel.lPer100km, useMpg: imperial),
        fuel.segments.isEmpty ? 'needs two full tanks with odometer' : null,
      ),
      (
        'Odometer',
        odo == null
            ? '–'
            : imperial
            ? '${kmToMiles(odo).round()} mi'
            : '${odo.round()} km',
        odo == null ? 'add a fill-up with the odometer' : 'estimated',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (vehicle.neverTrack)
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const ListTile(
              leading: Icon(Icons.no_crash_outlined),
              title: Text('Never tracked'),
              subtitle: Text(
                'Drives in this vehicle are ended and deleted as soon as the '
                'phone connects to it.',
              ),
            ),
          ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.6,
          children: [
            for (final (label, value, hint) in tiles)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label, style: theme.textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Text(value, style: theme.textTheme.headlineSmall),
                      if (hint != null)
                        Text(
                          hint,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (stats?.lastTripAt != null)
          Text(
            'Last trip ${relativeTime(DateTime.fromMillisecondsSinceEpoch(stats!.lastTripAt!), DateTime.now())}',
            style: theme.textTheme.bodyMedium,
          ),
        const SizedBox(height: 8),
        if (vehicle.bluetoothNameList.isNotEmpty)
          Text(
            'Car audio: ${vehicle.bluetoothNameList.join(', ')}',
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}
