import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../data/garage/fuel_math.dart';
import '../../../data/repos/garage_repo.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/relative_time.dart';
import '../../../widgets/units.dart';

/// Trips, distance, average score, fuel economy and odometer for one vehicle
/// as a stat grid, with one caption per figure that is still missing.
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
    final scheme = Theme.of(context).colorScheme;

    String score(double? v) => v == null ? '–' : v.round().toString();

    final notes = <String>[
      if (fuel.segments.isEmpty)
        'Fuel economy appears after two full tanks with the odometer noted.',
      if (odo == null) 'Add a fill-up with the odometer to estimate mileage.',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        if (vehicle.neverTrack) ...[
          Tile(
            tone: TileTone.raised,
            child: Row(
              children: [
                Icon(Icons.no_crash_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Never tracked',
                        style: context.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Drives in this car are deleted as soon as the phone '
                        'connects to it.',
                        style: context.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
        ],
        StatGrid(
          columns: 2,
          children: [
            StatTile(value: '${stats?.trips ?? 0}', label: 'Trips'),
            StatTile(
              value: formatDistance(stats?.distanceM ?? 0, units),
              label: 'Distance',
            ),
            StatTile(
              value: score(stats?.averageScore),
              label: 'Average score',
            ),
            StatTile(
              value: score(stats?.averageScore30d),
              label: 'Last 30 days',
            ),
            StatTile(
              value: formatEconomy(fuel.lPer100km, useMpg: imperial),
              label: 'Fuel economy',
            ),
            StatTile(
              value: odo == null
                  ? '–'
                  : imperial
                  ? '${kmToMiles(odo).round()} mi'
                  : '${odo.round()} km',
              label: odo == null ? 'Odometer' : 'Odometer, estimated',
            ),
          ],
        ),
        const SizedBox(height: Space.lg),
        for (final n in notes) ...[
          Text(n, style: context.caption),
          const SizedBox(height: Space.xs),
        ],
        if (stats?.lastTripAt != null)
          Text(
            'Last trip ${relativeTime(DateTime.fromMillisecondsSinceEpoch(stats!.lastTripAt!), DateTime.now())}',
            style: context.caption,
          ),
        if (vehicle.bluetoothNameList.isNotEmpty) ...[
          const SizedBox(height: Space.xs),
          Text(
            'Recognised car audio: ${vehicle.bluetoothNameList.join(', ')}',
            style: context.caption,
          ),
        ],
      ],
    );
  }
}
