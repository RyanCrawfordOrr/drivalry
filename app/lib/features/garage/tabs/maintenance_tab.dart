import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/garage/fuel_math.dart';
import '../../../data/garage/maintenance.dart';
import '../../../data/repos/garage_repo.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/units.dart';

/// Oil, tyres, registration, inspection: by distance and/or time.
class MaintenanceTab extends ConsumerWidget {
  const MaintenanceTab({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final imperial = unitLabel(units) == 'mph';
    final items =
        ref.watch(maintenanceItemsProvider(vehicle.id)).value ?? const [];
    final odo = ref.watch(odometerEstimateProvider(vehicle.id)).value;
    final now = DateTime.now().millisecondsSinceEpoch;
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'maintenance-fab',
        onPressed: () => _addItem(context, ref, imperial, odo),
        icon: const Icon(Icons.build_outlined),
        label: const Text('Reminder'),
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No reminders yet. Add oil changes, tyre rotations, '
                  'registration or inspection by distance, time or both.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                for (final item in items)
                  _ItemTile(
                    item: item,
                    due: dueStatus(item, nowMs: now, odometerKm: odo),
                    imperial: imperial,
                    odometerKm: odo,
                  ),
              ],
            ),
    );
  }

  Future<void> _addItem(
    BuildContext context,
    WidgetRef ref,
    bool imperial,
    double? odo,
  ) async {
    final title = TextEditingController();
    final km = TextEditingController();
    final days = TextEditingController();
    final lastKm = TextEditingController(
      text: odo == null
          ? ''
          : (imperial ? kmToMiles(odo) : odo).round().toString(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Maintenance reminder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'What'),
            ),
            TextField(
              controller: km,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Every (${imperial ? 'mi' : 'km'}, optional)',
              ),
            ),
            TextField(
              controller: days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Every (days, optional)',
              ),
            ),
            TextField(
              controller: lastKm,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Last done at (${imperial ? 'mi' : 'km'})',
              ),
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
  }
}

class _ItemTile extends ConsumerWidget {
  const _ItemTile({
    required this.item,
    required this.due,
    required this.imperial,
    required this.odometerKm,
  });

  final MaintenanceItem item;
  final MaintenanceDue due;
  final bool imperial;
  final double? odometerKm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = due.isDue
        ? theme.colorScheme.error
        : due.isSoon
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          due.isDue ? Icons.warning_amber_rounded : Icons.build_outlined,
          color: color,
        ),
        title: Text(item.title),
        subtitle: Text(
          due.describe(useMiles: imperial),
          style: TextStyle(color: color),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            final repo = ref.read(garageRepoProvider);
            if (v == 'done') {
              await repo.markMaintenanceDone(item.id, odometerKm: odometerKm);
            } else if (v == 'delete') {
              await repo.deleteMaintenance(item.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'done', child: Text('Mark done today')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
