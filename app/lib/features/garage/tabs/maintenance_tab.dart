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

    if (items.isEmpty) {
      return ListView(
        children: [
          EmptyState(
            kicker: 'Maintenance',
            headline: 'Set a reminder.',
            body: 'Oil, tyres, registration, inspection: by distance, time '
                'or both.',
            actionLabel: 'Add reminder',
            onAction: () => _addItem(context, ref, imperial, odo),
          ),
        ],
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'maintenance-fab',
        onPressed: () => _addItem(context, ref, imperial, odo),
        icon: const Icon(Icons.build_outlined),
        label: const Text('Reminder'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xxxl + Space.xxl,
        ),
        children: [
          for (final item in items) ...[
            _ItemTile(
              item: item,
              due: dueStatus(item, nowMs: now, odometerKm: odo),
              imperial: imperial,
              odometerKm: odo,
            ),
            const SizedBox(height: Space.sm),
          ],
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
    final scheme = Theme.of(context).colorScheme;
    final color = due.isDue
        ? scheme.error
        : due.isSoon
        ? scheme.tertiary
        : null;
    return SettingsGroup(
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
              final repo = ref.read(garageRepoProvider);
              if (v == 'done') {
                await repo.markMaintenanceDone(
                  item.id,
                  odometerKm: odometerKm,
                );
                Haptics.success();
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
      ],
    );
  }
}
