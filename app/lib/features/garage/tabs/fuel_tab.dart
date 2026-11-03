import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/db/database.dart';
import '../../../data/garage/fuel_math.dart';
import '../../../data/repos/garage_repo.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/units.dart';

/// Fill-ups and the economy they prove.
class FuelTab extends ConsumerWidget {
  const FuelTab({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final imperial = unitLabel(units) == 'mph';
    final entries =
        ref.watch(fuelEntriesProvider(vehicle.id)).value ?? const [];
    final stats = ref.watch(fuelStatsProvider(vehicle.id));
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fuel-fab',
        onPressed: () => _addFillUp(context, ref, imperial),
        icon: const Icon(Icons.local_gas_station),
        label: const Text('Fill-up'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: _Stat(
                      'Economy',
                      formatEconomy(stats.lPer100km, useMpg: imperial),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      'Fuel logged',
                      formatVolume(stats.totalLitres, useGallons: imperial),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      'Spent',
                      stats.totalCostCents == 0
                          ? '–'
                          : formatCents(stats.totalCostCents),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!stats.hasEconomy)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Economy appears after two full tanks with odometer readings. '
                'Partial fill-ups count toward the next full one.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (final e in entries.reversed)
            ListTile(
              leading: Icon(
                e.fullTank
                    ? Icons.local_gas_station
                    : Icons.local_gas_station_outlined,
              ),
              title: Text(
                '${formatVolume(e.litres, useGallons: imperial)}'
                '${e.costCents == null ? '' : ' · ${formatCents(e.costCents!)} ${e.currency}'}',
              ),
              subtitle: Text(
                [
                  date.format(DateTime.fromMillisecondsSinceEpoch(e.at)),
                  if (e.odometerKm != null)
                    imperial
                        ? '${kmToMiles(e.odometerKm!).round()} mi'
                        : '${e.odometerKm!.round()} km',
                  if (!e.fullTank) 'partial',
                ].join(' · '),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    ref.read(garageRepoProvider).deleteFuelEntry(e.id),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addFillUp(
    BuildContext context,
    WidgetRef ref,
    bool imperial,
  ) async {
    final volume = TextEditingController();
    final odo = TextEditingController();
    final cost = TextEditingController();
    var full = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Fill-up'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: volume,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: imperial ? 'Gallons' : 'Litres',
                ),
              ),
              TextField(
                controller: odo,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: imperial ? 'Odometer (mi)' : 'Odometer (km)',
                ),
              ),
              TextField(
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Cost (optional)'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Full tank'),
                value: full,
                onChanged: (v) => setState(() => full = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(volume.text.replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    final o = double.tryParse(odo.text.replaceAll(',', '.'));
    final c = double.tryParse(cost.text.replaceAll(',', '.'));
    await ref
        .read(garageRepoProvider)
        .addFuelEntry(
          vehicleId: vehicle.id,
          litres: imperial ? usGallonsToLitres(v) : v,
          odometerKm: o == null ? null : (imperial ? milesToKm(o) : o),
          costCents: c == null ? null : (c * 100).round(),
          fullTank: full,
        );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}
