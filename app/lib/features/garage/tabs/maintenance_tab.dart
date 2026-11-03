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

/// Oil, tyres, registration, inspection: by distance and/or time. Rows swipe
/// away with Undo; empty and populated states cross-fade (docs/12 §5b).
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
                    kicker: 'Maintenance',
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
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.lg,
                  Space.gutter,
                  Space.xxxl + Space.xxl,
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

  Future<void> _addItem(bool imperial, double? odo) async {
    final title = TextEditingController();
    final km = TextEditingController();
    final days = TextEditingController();
    final lastKm = TextEditingController(
      text: odo == null
          ? ''
          : (imperial ? kmToMiles(odo) : odo).round().toString(),
    );
    final ok = await showDrivalrySheet<bool>(
      context,
      title: 'New reminder',
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'What'),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: km,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Every (${imperial ? 'mi' : 'km'}, optional)',
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Every (days, optional)',
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: lastKm,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Last done at (${imperial ? 'mi' : 'km'})',
              ),
            ),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Save',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    final everyKm = double.tryParse(km.text);
    final everyDays = int.tryParse(days.text);
    if (everyKm == null && everyDays == null) return;
    final last = double.tryParse(lastKm.text);
    await ref
        .read(garageRepoProvider)
        .addMaintenance(
          vehicleId: vehicle.id,
          title: title.text,
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
