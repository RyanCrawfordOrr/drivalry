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
import '../widgets/swipe_to_delete.dart';
import '../widgets/unit_stat.dart';

/// What the fill-up sheet hands back when saved.
typedef _FillUp = ({String volume, String odo, String cost, bool full});

/// Fill-ups and the economy they prove. Empty: one headline and one button;
/// populated: a two-by-two stat grid, the log as tiles you can swipe away
/// (with Undo), and a FAB the list clears. The two states cross-fade
/// (docs/12 §5b).
class FuelTab extends ConsumerStatefulWidget {
  const FuelTab({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  ConsumerState<FuelTab> createState() => _FuelTabState();
}

class _FuelTabState extends ConsumerState<FuelTab> {
  /// Rows swiped away but not yet gone from the stream, so a dismissed
  /// `Dismissible` never lingers in the tree.
  final Set<String> _removing = {};

  Vehicle get vehicle => widget.vehicle;

  @override
  Widget build(BuildContext context) {
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final imperial = unitLabel(units) == 'mph';
    final all = ref.watch(fuelEntriesProvider(vehicle.id)).value ?? const [];
    _removing.removeWhere((id) => !all.any((e) => e.id == id));
    final entries = all.where((e) => !_removing.contains(e.id)).toList();
    final stats = ref.watch(fuelStatsProvider(vehicle.id));
    final date = DateFormat.yMMMd();
    final economy = stats.hasEconomy
        ? (imperial ? 235.214583 / stats.lPer100km : stats.lPer100km)
        : null;

    return Scaffold(
      floatingActionButton: entries.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fuel-fab',
              onPressed: () => _addFillUp(imperial),
              icon: const Icon(Icons.local_gas_station),
              label: const Text('Fill-up'),
            ),
      body: StateSwitcher(
        child: entries.isEmpty
            ? ListView(
                key: const ValueKey('empty'),
                children: [
                  EmptyState(
                    kicker: 'Fuel',
                    headline: 'Log your first fill-up.',
                    body:
                        'Two full tanks with the odometer and you get real '
                        'economy.',
                    actionLabel: 'Add fill-up',
                    onAction: () => _addFillUp(imperial),
                  ),
                ],
              )
            : ListView(
                key: const ValueKey('list'),
                // The last row clears the FAB (56 + 16 margin) and the nav
                // bar with 24 to spare.
                padding: EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.lg,
                  Space.gutter,
                  Space.xxxl +
                      Space.xxxl +
                      MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Reveal(
                    child: StatGrid(
                      columns: 2,
                      children: [
                        UnitStat(
                          value: economy,
                          decimals: 1,
                          unit: imperial ? 'mpg' : 'L/100 km',
                          label: 'Economy',
                        ),
                        UnitStat(
                          value: imperial
                              ? litresToUsGallons(stats.totalLitres)
                              : stats.totalLitres,
                          decimals: 1,
                          unit: imperial ? 'gal' : 'L',
                          label: 'Fuel logged',
                        ),
                        UnitStat(
                          value: stats.totalCostCents == 0
                              ? null
                              : stats.totalCostCents / 100,
                          decimals: 2,
                          unit: entries.last.currency,
                          label: 'Spent',
                        ),
                        UnitStat(value: entries.length, label: 'Fill-ups'),
                      ],
                    ),
                  ),
                  if (!stats.hasEconomy) ...[
                    const SizedBox(height: Space.md),
                    Text(
                      'Economy appears after two full tanks with odometer '
                      'readings. Partial fill-ups count toward the next full '
                      'one.',
                      style: context.caption,
                    ),
                  ],
                  const SizedBox(height: Space.xl),
                  for (var i = 0; i < entries.length; i++) ...[
                    Reveal(
                      key: ValueKey(entries.reversed.elementAt(i).id),
                      delay: Reveal.stagger(i + 1),
                      child: _row(
                        entries.reversed.elementAt(i),
                        imperial,
                        date,
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _row(FuelEntry e, bool imperial, DateFormat date) {
    return Dismissible(
      key: ValueKey('fuel-${e.id}'),
      direction: DismissDirection.endToStart,
      background: const SwipeToDeleteBackground(),
      onDismissed: (_) => _remove(e),
      child: SettingsGroup(
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
          ),
        ],
      ),
    );
  }

  Future<void> _remove(FuelEntry e) async {
    Haptics.select();
    setState(() => _removing.add(e.id));
    final db = ref.read(databaseProvider);
    await ref.read(garageRepoProvider).deleteFuelEntry(e.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Fill-up removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await db.upsertFuelEntry(e.toCompanion(true));
            if (mounted) setState(() => _removing.remove(e.id));
          },
        ),
      ),
    );
  }

  /// The fields live inside [TextControllers], which outlives the sheet's
  /// exit animation; the typed text comes back through the pop value.
  Future<void> _addFillUp(bool imperial) async {
    var full = true;
    final result = await showDrivalrySheet<_FillUp>(
      context,
      title: 'Fill-up',
      builder: (_) => TextControllers(
        initial: const ['', '', ''],
        builder: (ctx, c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: StatefulBuilder(
            builder: (ctx, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: c[0],
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
                  controller: c[1],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: imperial ? 'Odometer (mi)' : 'Odometer (km)',
                  ),
                ),
                const SizedBox(height: Space.md),
                TextField(
                  controller: c[2],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cost (optional)',
                  ),
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
                  onPressed: () => Navigator.of(ctx).pop((
                    volume: c[0].text,
                    odo: c[1].text,
                    cost: c[2].text,
                    full: full,
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return;
    final v = double.tryParse(result.volume.replaceAll(',', '.'));
    if (v == null || v <= 0) return;
    final o = double.tryParse(result.odo.replaceAll(',', '.'));
    final c = double.tryParse(result.cost.replaceAll(',', '.'));
    await ref
        .read(garageRepoProvider)
        .addFuelEntry(
          vehicleId: vehicle.id,
          litres: imperial ? usGallonsToLitres(v) : v,
          odometerKm: o == null ? null : (imperial ? milesToKm(o) : o),
          costCents: c == null ? null : (c * 100).round(),
          fullTank: result.full,
        );
    Haptics.success();
  }
}
