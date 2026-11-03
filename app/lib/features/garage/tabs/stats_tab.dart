import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../data/garage/fuel_math.dart';
import '../../../data/repos/garage_repo.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/relative_time.dart';
import '../../../widgets/units.dart';
import '../widgets/unit_stat.dart';

/// Trips, distance, average score, fuel economy and odometer for one vehicle
/// as a stat grid whose numbers count up (docs/12 §5b), with one caption per
/// figure that is still missing.
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

    final economy = fuel.lPer100km;
    final hasEconomy = !economy.isNaN && economy > 0;
    final (distance, distanceDecimals, distanceUnit) = _distanceParts(
      stats?.distanceM ?? 0,
      units,
    );

    final carAudio = vehicle.bluetoothNameList.join(', ');
    final notes = <String>[
      if (fuel.segments.isEmpty)
        'Log two full tanks with the odometer to see fuel economy.',
      if (odo == null)
        'Add a fill-up with the odometer to estimate mileage.'
      else
        'The odometer is estimated from your last fill-up and the trips '
            'since.',
    ];

    final tiles = <Widget>[
      UnitStat(value: stats?.trips ?? 0, label: 'Trips'),
      UnitStat(
        value: distance,
        decimals: distanceDecimals,
        unit: distanceUnit,
        label: 'Distance',
      ),
      UnitStat(value: stats?.averageScore?.round(), label: 'Average score'),
      UnitStat(value: stats?.averageScore30d?.round(), label: 'Last 30 days'),
      UnitStat(
        value: hasEconomy ? (imperial ? 235.214583 / economy : economy) : null,
        decimals: 1,
        unit: imperial ? 'mpg' : 'L/100 km',
        label: 'Fuel economy',
      ),
      UnitStat(
        value: odo == null ? null : (imperial ? kmToMiles(odo) : odo).round(),
        unit: imperial ? 'mi' : 'km',
        label: 'Odometer',
      ),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (vehicle.neverTrack) ...[
          Reveal(
            child: Tile(
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
                          'Drives in this car are deleted as soon as the '
                          'phone connects to it.',
                          style: context.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.md),
        ],
        StatGrid(
          columns: 2,
          children: [
            for (var i = 0; i < tiles.length; i++)
              Reveal(delay: Reveal.stagger(i), child: tiles[i]),
          ],
        ),
        const SizedBox(height: Space.lg),
        Reveal(
          delay: Reveal.stagger(tiles.length),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final n in notes) ...[
                Text(n, style: context.caption),
                const SizedBox(height: Space.xs),
              ],
              if (stats?.lastTripAt != null)
                Text(
                  'Last trip ${relativeTime(DateTime.fromMillisecondsSinceEpoch(stats!.lastTripAt!), DateTime.now())}',
                  style: context.caption,
                ),
              if (carAudio.isNotEmpty) ...[
                const SizedBox(height: Space.xs),
                Text('Recognised car audio: $carAudio', style: context.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Number, decimals and unit for a distance in the person's units, so the
  /// figure can count while the unit sits still.
  static (double, int, String) _distanceParts(double metres, SpeedUnits u) {
    if (u == SpeedUnits.mph) {
      final mi = metres / 1609.344;
      return (mi, mi < 10 ? 1 : 0, 'mi');
    }
    final km = metres / 1000;
    return (km, km < 10 ? 1 : 0, 'km');
  }
}
