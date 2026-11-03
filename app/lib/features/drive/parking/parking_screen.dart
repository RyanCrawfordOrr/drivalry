import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../app/bootstrap.dart';
import '../../../app/ui/ui.dart';
import '../../../tracking/providers.dart';
import '../../../widgets/relative_time.dart';
import '../../../widgets/units.dart';
import 'parking_card.dart';
import 'parking_memory.dart';

/// Full-screen parking memory: a small map when the Maps key is ready, the
/// photo, the note and the same actions as the tile.
class ParkingScreen extends ConsumerWidget {
  const ParkingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spot = ref.watch(latestParkingSpotProvider).value;
    final mapsReady = ref.watch(mapsReadyProvider).value ?? false;
    final units = resolveUnits(
      ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto,
    );
    final scheme = Theme.of(context).colorScheme;
    if (spot == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Where I parked')),
        body: const EmptyState(
          kicker: 'Parking',
          headline: 'No spot remembered yet.',
          body: 'Where you park next shows up here.',
        ),
      );
    }
    final road = ref.watch(parkingRoadNameProvider(spot.tripId)).value;
    final ago = relativeTime(
      DateTime.fromMillisecondsSinceEpoch(spot.parkedAt),
      DateTime.now(),
    );
    final sections = <Widget>[
      ClipRRect(
        borderRadius: Radii.cardRadius,
        child: SizedBox(
          height: 220,
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
              : Container(
                  color: scheme.surfaceContainerLow,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text(
                    'Map not available in this version.',
                    textAlign: TextAlign.center,
                    style: context.bodyMuted,
                  ),
                ),
        ),
      ),
      const SizedBox(height: Space.xl),
      Text('Parked $ago', style: context.headline),
      if (road != null && road.isNotEmpty) ...[
        const SizedBox(height: Space.xs),
        Text('near $road', style: context.title),
      ],
      const SizedBox(height: Space.xs),
      Text(
        'Within about ${formatShortDistance(spot.accuracy, units)}',
        style: context.caption,
      ),
      if (spot.note != null && spot.note!.isNotEmpty) ...[
        const SizedBox(height: Space.lg),
        Text(spot.note!, style: context.body),
      ],
      if (spot.photoPath != null) ...[
        const SizedBox(height: Space.lg),
        ClipRRect(
          borderRadius: Radii.cardRadius,
          child: Image.file(
            File(spot.photoPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ],
      const SizedBox(height: Space.lg),
      ParkingActions(spot: spot),
      const SizedBox(height: Space.xl),
      Text(
        'Parking spots stay on this phone. Nobody else sees them.',
        style: context.caption,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Where I parked')),
      body: ListView(
        padding: Space.screenWithBottom,
        children: [
          for (final (i, s) in sections.indexed)
            Reveal(delay: Reveal.stagger(i), child: s),
        ],
      ),
    );
  }
}
