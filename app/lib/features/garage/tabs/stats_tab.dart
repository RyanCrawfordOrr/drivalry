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
      if (odo == null) 'Add a fill-up with the odometer to estimate mileage.',
    ];

    final tiles = <Widget>[
      _Stat(value: stats?.trips ?? 0, label: 'Trips'),
      _Stat(
        value: distance,
        decimals: distanceDecimals,
        suffix: distanceUnit,
        label: 'Distance',
      ),
      _Stat(value: stats?.averageScore?.round(), label: 'Average score'),
      _Stat(value: stats?.averageScore30d?.round(), label: 'Last 30 days'),
      _Stat(
        value: hasEconomy ? (imperial ? 235.214583 / economy : economy) : null,
        decimals: 1,
        suffix: imperial ? ' mpg' : ' L/100 km',
        label: 'Fuel economy',
      ),
      _Stat(
        value: odo == null ? null : (imperial ? kmToMiles(odo) : odo).round(),
        suffix: imperial ? ' mi' : ' km',
        label: odo == null ? 'Odometer' : 'Odometer, estimated',
      ),
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
      return (mi, mi < 10 ? 1 : 0, ' mi');
    }
    final km = metres / 1000;
    return (km, km < 10 ? 1 : 0, ' km');
  }
}

/// A [StatTile] whose number counts up; a null [value] shows a dash.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.value,
    required this.label,
    this.decimals = 0,
    this.suffix = '',
  });

  final num? value;
  final String label;
  final int decimals;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final style = context.title.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Tile(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.lg,
        Space.lg,
        Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (value == null)
            Text('–', style: style)
          else
            AnimatedNumber(
              value: value!,
              decimals: decimals,
              suffix: suffix,
              style: style,
            ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
