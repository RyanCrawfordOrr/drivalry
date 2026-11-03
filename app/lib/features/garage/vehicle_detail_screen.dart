import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/garage_repo.dart';
import 'tabs/documents_tab.dart';
import 'tabs/fuel_tab.dart';
import 'tabs/maintenance_tab.dart';
import 'tabs/stats_tab.dart';

/// One vehicle: Stats, Fuel, Maintenance, Documents.
class VehicleDetailScreen extends ConsumerWidget {
  const VehicleDetailScreen({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleProvider(vehicleId)).value;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(vehicle?.name ?? 'Vehicle'),
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
              Tab(text: 'Maintenance'),
              Tab(text: 'Documents'),
            ],
          ),
        ),
        body: vehicle == null
            ? const Center(child: Text('This vehicle is gone.'))
            : TabBarView(
                children: [
                  StatsTab(vehicle: vehicle),
                  FuelTab(vehicle: vehicle),
                  MaintenanceTab(vehicle: vehicle),
                  DocumentsTab(vehicle: vehicle),
                ],
              ),
      ),
    );
  }
}
