import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../../widgets/relative_time.dart';
import 'parking_card.dart';
import 'parking_memory.dart';

/// Full-screen parking memory: a small map when the Maps key is ready, the
/// photo, the note and the same actions as the card.
class ParkingScreen extends ConsumerWidget {
  const ParkingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spot = ref.watch(latestParkingSpotProvider).value;
    final mapsReady = ref.watch(mapsReadyProvider).value ?? false;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Where I parked')),
      body: spot == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No parking spot remembered. The end of your next drive '
                  'will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SizedBox(
                  height: 220,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: mapsReady
                        ? GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: LatLng(spot.lat, spot.lon),
                              zoom: 16,
                            ),
                            markers: {
                              Marker(
                                markerId: const MarkerId('car'),
                                position: LatLng(spot.lat, spot.lon),
                              ),
                            },
                            zoomControlsEnabled: false,
                            myLocationButtonEnabled: false,
                            liteModeEnabled: true,
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                '${spot.lat.toStringAsFixed(5)}, '
                                '${spot.lon.toStringAsFixed(5)}\n'
                                '(map needs a Google Maps key)',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Parked ${relativeTime(DateTime.fromMillisecondsSinceEpoch(spot.parkedAt), DateTime.now())}',
                  style: theme.textTheme.titleMedium,
                ),
                Builder(
                  builder: (_) {
                    final road = ref
                        .watch(parkingRoadNameProvider(spot.tripId))
                        .value;
                    return road == null
                        ? const SizedBox.shrink()
                        : Text('near $road', style: theme.textTheme.bodyLarge);
                  },
                ),
                Text(
                  'Accuracy about ${spot.accuracy.round()} m',
                  style: theme.textTheme.bodySmall,
                ),
                if (spot.note != null && spot.note!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(spot.note!, style: theme.textTheme.bodyLarge),
                ],
                if (spot.photoPath != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(spot.photoPath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ParkingActions(spot: spot),
                const SizedBox(height: 24),
                Text(
                  'Parking spots stay on this phone. Nobody else sees them.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
    );
  }
}
