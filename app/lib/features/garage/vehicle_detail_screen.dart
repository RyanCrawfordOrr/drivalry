import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/garage_repo.dart';
import 'tabs/documents_tab.dart';
import 'tabs/fuel_tab.dart';
import 'tabs/maintenance_tab.dart';
import 'tabs/stats_tab.dart';

/// One vehicle: Stats, Fuel, Upkeep (maintenance reminders), Papers
/// (documents). Four fixed tabs share 360 px, so each label must fit in
/// 58 px: that is why the last two are the short words.
class VehicleDetailScreen extends ConsumerWidget {
  const VehicleDetailScreen({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleProvider(vehicleId));
    final v = vehicle.value;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(v?.name ?? 'Vehicle'),
          actions: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push(Routes.editVehicle(vehicleId)),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Stats'),
              Tab(text: 'Fuel'),
              Tab(text: 'Upkeep'),
              Tab(text: 'Papers'),
            ],
          ),
        ),
        body: v == null
            ? (vehicle.isLoading
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.lg,
                        Space.gutter,
                        0,
                      ),
                      child: SkeletonTile(height: 120),
                    )
                  : EmptyState(
                      kicker: 'Garage',
                      headline: 'This car is no longer in your garage.',
                      body:
                          'Its trips, fuel log and documents stay on the '
                          'phone.',
                      actionLabel: 'Back to the garage',
                      onAction: () => context.go(Routes.garage),
                    ))
            : TabBarView(
                children: [
                  StatsTab(vehicle: v),
                  FuelTab(vehicle: v),
                  MaintenanceTab(vehicle: v),
                  DocumentsTab(vehicle: v),
                ],
              ),
      ),
    );
  }
}
