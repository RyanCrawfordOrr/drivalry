import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../data/garage/fuel_math.dart';
import '../../../data/garage/maintenance.dart';
import '../../../data/repos/garage_repo.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/units.dart';
import '../../settings/widgets/settings_rows.dart';
import '../widgets/swipe_to_delete.dart';

/// What the reminder sheet hands back when saved.
typedef _Reminder = ({String title, String km, String days, String lastKm});

/// Upkeep: oil, tyres, registration, inspection, by distance and/or time.
/// Rows swipe away with Undo; empty and populated states cross-fade
/// (docs/12 §5b).
class MaintenanceTab extends ConsumerStatefulWidget {
  const MaintenanceTab({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  ConsumerState<MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends ConsumerState<MaintenanceTab> {
  final Set<String> _removing = {};

  Vehicle get vehicle => widget.vehicle;

  @override
  Widget build(BuildContext context) {
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final imperial = unitLabel(units) == 'mph';
    final all =
        ref.watch(maintenanceItemsProvider(vehicle.id)).value ?? const [];
    _removing.removeWhere((id) => !all.any((i) => i.id == id));
    final items = all.where((i) => !_removing.contains(i.id)).toList();
    final odo = ref.watch(odometerEstimateProvider(vehicle.id)).value;
    final now = DateTime.now().millisecondsSinceEpoch;

    return Scaffold(
      floatingActionButton: items.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'maintenance-fab',
              onPressed: () => _addItem(imperial, odo),
              icon: const Icon(Icons.build_outlined),
              label: const Text('Reminder'),
            ),
      body: StateSwitcher(
        child: items.isEmpty
            ? ListView(
                key: const ValueKey('empty'),
                children: [
                  EmptyState(
                    kicker: 'Upkeep',
                    headline: 'Set a reminder.',
                    body:
                        'Oil, tyres, registration, inspection: by distance, '
                        'time or both.',
                    actionLabel: 'Add reminder',
                    onAction: () => _addItem(imperial, odo),
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
                  for (var i = 0; i < items.length; i++) ...[
                    Reveal(
                      key: ValueKey(items[i].id),
                      delay: Reveal.stagger(i),
                      child: _row(
                        items[i],
                        dueStatus(items[i], nowMs: now, odometerKm: odo),
                        imperial,
                        odo,
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _row(
    MaintenanceItem item,
    MaintenanceDue due,
    bool imperial,
    double? odometerKm,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final color = due.isDue
        ? scheme.error
        : due.isSoon
        ? scheme.tertiary
        : null;
    return Dismissible(
      key: ValueKey('maintenance-${item.id}'),
      direction: DismissDirection.endToStart,
      background: const SwipeToDeleteBackground(),
      onDismissed: (_) => _remove(item),
      child: SettingsGroup(
        children: [
          SettingsRow(
            leading: Icon(
              due.isDue ? Icons.warning_amber_rounded : Icons.build_outlined,
              color: color ?? scheme.onSurfaceVariant,
            ),
            title: item.title,
            caption: due.describe(useMiles: imperial),
            captionColor: color,
            trailing: PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                if (v == 'done') {
                  await ref
                      .read(garageRepoProvider)
                      .markMaintenanceDone(item.id, odometerKm: odometerKm);
                  Haptics.success();
                } else if (v == 'delete') {
                  await _remove(item);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'done', child: Text('Mark done today')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(MaintenanceItem item) async {
    Haptics.select();
    setState(() => _removing.add(item.id));
    final db = ref.read(databaseProvider);
    await ref.read(garageRepoProvider).deleteMaintenance(item.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.title} removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await db.upsertMaintenance(item.toCompanion(true));
            if (mounted) setState(() => _removing.remove(item.id));
          },
        ),
      ),
    );
  }

  /// The fields live inside [TextControllers], which outlives the sheet's
  /// exit animation; the typed text comes back through the pop value.
  Future<void> _addItem(bool imperial, double? odo) async {
    final lastKnown = odo == null
        ? ''
        : (imperial ? kmToMiles(odo) : odo).round().toString();
    final unit = imperial ? 'mi' : 'km';
    final result = await showDrivalrySheet<_Reminder>(
      context,
      title: 'New reminder',
      builder: (_) => TextControllers(
        initial: ['', '', '', lastKnown],
        builder: (ctx, c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: c[0],
                autofocus: true,
                decoration: const InputDecoration(labelText: 'What'),
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: c[1],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Every ($unit, optional)',
                ),
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: c[2],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Every (days, optional)',
                ),
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: c[3],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'Last done at ($unit)'),
              ),
              const SizedBox(height: Space.xl),
              PrimaryButton(
                label: 'Save',
                onPressed: () => Navigator.of(ctx).pop((
                  title: c[0].text,
                  km: c[1].text,
                  days: c[2].text,
                  lastKm: c[3].text,
                )),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final everyKm = double.tryParse(result.km);
    final everyDays = int.tryParse(result.days);
    if (everyKm == null && everyDays == null) return;
    final last = double.tryParse(result.lastKm);
    await ref
        .read(garageRepoProvider)
        .addMaintenance(
          vehicleId: vehicle.id,
          title: result.title,
          intervalKm: everyKm == null
              ? null
              : (imperial ? milesToKm(everyKm) : everyKm),
          intervalDays: everyDays,
          lastDoneKm: last == null ? null : (imperial ? milesToKm(last) : last),
          lastDoneAt: DateTime.now().millisecondsSinceEpoch,
        );
    Haptics.success();
  }
}
