import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/db/database.dart';
import '../../data/models/trip_score_view.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../widgets/units.dart';
import 'simulate_sheet.dart';
import 'widgets/passenger_card.dart';
import 'widgets/tracking_status_card.dart';
import 'widgets/trip_card.dart';

/// Home tab: tracking status, the passenger question, the last trip and the
/// recent list (docs/01 §4.1).
class DriveScreen extends ConsumerWidget {
  const DriveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = ref.watch(trackingControllerProvider);
    final controller = ref.read(trackingControllerProvider.notifier);
    final trips =
        ref.watch(recentTripsProvider).value ?? const <TripWithScore>[];
    final unanswered =
        ref.watch(unansweredTripsProvider).value ?? const <Trip>[];
    final unitsSetting =
        ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto;
    final latestRegion = trips.isEmpty ? null : trips.first.trip.packRegion;
    final units = resolveUnits(unitsSetting, packRegion: latestRegion);
    final theme = Theme.of(context);

    final last = trips.isEmpty ? null : trips.first;
    final rest = trips.length > 1 ? trips.sublist(1) : const <TripWithScore>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drive'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => _onMenu(context, ref, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'simulate', child: Text('Simulate a drive')),
              PopupMenuItem(value: 'packs', child: Text('Speed-limit packs')),
              PopupMenuItem(value: 'units', child: Text('Units')),
              PopupMenuItem(value: 'diagnostics', child: Text('Diagnostics')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          TrackingStatusCard(
            state: tracking,
            units: units,
            onRequestPermissions: controller.requestPermissions,
            onOpenSettings: controller.openSettings,
            onSetEnabled: controller.setEnabled,
            onPause: controller.pauseFor,
            onPauseUntilTomorrow: controller.pauseUntilTomorrow,
            onResume: controller.clearPause,
            onStartNow: controller.startNow,
            onEndNow: controller.endNow,
          ),
          for (final t in unanswered)
            PassengerCard(
              trip: t,
              units: resolveUnits(unitsSetting, packRegion: t.packRegion),
              onAnswer: (isPassenger) =>
                  controller.answerPassenger(t.id, isPassenger),
            ),
          const SizedBox(height: 8),
          if (last == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.directions_car_outlined,
                    size: 48,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text('No trips yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Your first drive will show up here, scored on this phone. '
                    'Or simulate one from the menu.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text('Last trip', style: theme.textTheme.titleSmall),
            ),
            TripCard(
              trip: last.trip,
              score: _view(last.score),
              units: resolveUnits(
                unitsSetting,
                packRegion: last.trip.packRegion,
              ),
              large: true,
              onTap: () => context.push(Routes.tripDetail(last.trip.id)),
            ),
            if (rest.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text('Recent', style: theme.textTheme.titleSmall),
              ),
            for (final t in rest)
              TripCard(
                trip: t.trip,
                score: _view(t.score),
                units: resolveUnits(
                  unitsSetting,
                  packRegion: t.trip.packRegion,
                ),
                onTap: () => context.push(Routes.tripDetail(t.trip.id)),
              ),
          ],
        ],
      ),
    );
  }

  static TripScoreView? _view(TripScoreRow? row) =>
      row == null ? null : TripScoreView.fromJsonString(row.scoreJson);

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    switch (value) {
      case 'simulate':
        await showSimulateSheet(context, ref);
      case 'packs':
        await context.push(Routes.packs);
      case 'diagnostics':
        await context.push(Routes.diagnostics);
      case 'units':
        await _pickUnits(context, ref);
    }
  }

  Future<void> _pickUnits(BuildContext context, WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final current = UnitsSetting.fromWire(await db.getSetting('units'));
    if (!context.mounted) return;
    final picked = await showDialog<UnitsSetting>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Units'),
        children: [
          RadioGroup<UnitsSetting>(
            groupValue: current,
            onChanged: (v) => Navigator.of(ctx).pop(v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (setting, label) in const [
                  (UnitsSetting.auto, 'Automatic (follow the pack / locale)'),
                  (UnitsSetting.mph, 'Miles per hour'),
                  (UnitsSetting.kmh, 'Kilometres per hour'),
                ])
                  RadioListTile<UnitsSetting>(
                    value: setting,
                    title: Text(label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await db.setSetting('units', picked.name);
  }
}
