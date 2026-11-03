import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../data/garage/fuel_math.dart';
import '../../../data/repos/garage_repo.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/units.dart';
import '../../settings/widgets/settings_rows.dart';

/// Fill-ups and the economy they prove. Empty: one headline and one button;
/// populated: a stat grid, the log as tiles and a FAB.
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
    final date = DateFormat.yMMMd();

    if (entries.isEmpty) {
      return ListView(
        children: [
          EmptyState(
            kicker: 'Fuel',
            headline: 'Log your first fill-up.',
            body: 'Two full tanks with the odometer and you get real economy.',
            actionLabel: 'Add fill-up',
            onAction: () => _addFillUp(context, ref, imperial),
          ),
        ],
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fuel-fab',
        onPressed: () => _addFillUp(context, ref, imperial),
        icon: const Icon(Icons.local_gas_station),
        label: const Text('Fill-up'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xxxl + Space.xxl,
        ),
        children: [
          StatGrid(
            children: [
              StatTile(
                value: formatEconomy(stats.lPer100km, useMpg: imperial),
                label: 'Economy',
              ),
              StatTile(
                value: formatVolume(stats.totalLitres, useGallons: imperial),
                label: 'Fuel logged',
              ),
              StatTile(
                value: stats.totalCostCents == 0
                    ? '–'
                    : formatCents(stats.totalCostCents),
                label: 'Spent',
              ),
            ],
          ),
          if (!stats.hasEconomy) ...[
            const SizedBox(height: Space.md),
            Text(
              'Economy appears after two full tanks with odometer readings. '
              'Partial fill-ups count toward the next full one.',
              style: context.caption,
            ),
          ],
          const SizedBox(height: Space.xl),
          for (final e in entries.reversed) ...[
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: e.fullTank
                      ? Icons.local_gas_station
                      : Icons.local_gas_station_outlined,
                  title:
                      '${formatVolume(e.litres, useGallons: imperial)}'
                      '${e.costCents == null ? '' : ' · ${formatCents(e.costCents!)} ${e.currency}'}',
                  caption: [
                    date.format(DateTime.fromMillisecondsSinceEpoch(e.at)),
                    if (e.odometerKm != null)
                      imperial
                          ? '${kmToMiles(e.odometerKm!).round()} mi'
                          : '${e.odometerKm!.round()} km',
                    if (!e.fullTank) 'partial',
                  ].join(' · '),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _remove(context, ref, e),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
          ],
        ],
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, FuelEntry e) async {
    final repo = ref.read(garageRepoProvider);
    await repo.deleteFuelEntry(e.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Fill-up removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repo.addFuelEntry(
            vehicleId: e.vehicleId,
            litres: e.litres,
            odometerKm: e.odometerKm,
            costCents: e.costCents,
            fullTank: e.fullTank,
          ),
        ),
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
    final ok = await showDrivalrySheet<bool>(
      context,
      title: 'Fill-up',
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: Space.md),
              TextField(
                controller: odo,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: imperial ? 'Odometer (mi)' : 'Odometer (km)',
                ),
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: cost,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Cost (optional)'),
              ),
              const SizedBox(height: Space.sm),
              SettingsSwitchRow(
                title: 'Full tank',
                value: full,
                onChanged: (v) => setState(() => full = v),
              ),
              const SizedBox(height: Space.lg),
              PrimaryButton(
                label: 'Save',
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ),
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
    Haptics.success();
  }
}
