import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../data/db/database.dart';
import '../../../widgets/relative_time.dart';
import 'parking_links.dart';
import 'parking_memory.dart';

/// "Parked · 12 min ago · near Elm St" with walk-back, photo, note, forget.
/// Shown on the Drive tab while no trip is recording.
class ParkingCard extends ConsumerWidget {
  const ParkingCard({super.key, required this.spot, this.compact = true});

  final ParkingSpot spot;

  /// The Drive-tab card is compact; the full screen uses the same actions.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final road = ref.watch(parkingRoadNameProvider(spot.tripId)).value;
    final ago = relativeTime(
      DateTime.fromMillisecondsSinceEpoch(spot.parkedAt),
      DateTime.now(),
    );
    final title = [
      'Parked',
      ago,
      if (road != null && road.isNotEmpty) 'near $road',
    ].join(' · ');

    return Card(
      key: const Key('parking-card'),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: compact ? () => context.push(Routes.parking) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.local_parking, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                  if (spot.photoPath != null && compact)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(spot.photoPath!),
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
              if (spot.note != null && spot.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 34),
                  child: Text(spot.note!, style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: 6),
              ParkingActions(spot: spot),
            ],
          ),
        ),
      ),
    );
  }
}

/// Walk back · Photo · Note · Forget.
class ParkingActions extends ConsumerWidget {
  const ParkingActions({super.key, required this.spot});

  final ParkingSpot spot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: () => openWalkBack(context, spot),
          icon: const Icon(Icons.directions_walk),
          label: const Text('Walk back'),
        ),
        TextButton.icon(
          onPressed: () => _addPhoto(context, ref),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(spot.photoPath == null ? 'Add photo' : 'Photo'),
        ),
        TextButton.icon(
          onPressed: () => _editNote(context, ref),
          icon: const Icon(Icons.sticky_note_2_outlined),
          label: const Text('Note'),
        ),
        TextButton.icon(
          onPressed: () => _forget(context, ref),
          icon: const Icon(Icons.close),
          label: const Text('Forget'),
        ),
      ],
    );
  }

  Future<void> _addPhoto(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from library'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      final base = await getApplicationSupportDirectory();
      final dir = Directory(p.join(base.path, 'parking'));
      await dir.create(recursive: true);
      final dest = p.join(dir.path, '${spot.tripId}.jpg');
      await File(picked.path).copy(dest);
      await ref.read(parkingMemoryProvider).setPhoto(spot.tripId, dest);
    } catch (e) {
      debugPrint('parking photo failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save photo: $e')));
      }
    }
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: spot.note ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Parking note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(hintText: 'Level 3, near the lift'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value == null) return;
    await ref.read(parkingMemoryProvider).setNote(spot.tripId, value.trim());
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final photo = spot.photoPath;
    await ref.read(parkingMemoryProvider).forget(spot.tripId);
    if (photo != null) {
      try {
        await File(photo).delete();
      } catch (_) {}
    }
    if (context.mounted &&
        context.canPop() &&
        !ModalRoute.of(context)!.isFirst) {
      context.pop();
    }
  }
}

/// Opens walking directions in the platform maps app, falling back to the web.
Future<void> openWalkBack(BuildContext context, ParkingSpot spot) async {
  final primary = walkBackUri(
    lat: spot.lat,
    lon: spot.lon,
    platform: defaultTargetPlatform,
  );
  try {
    if (await launchUrl(primary, mode: LaunchMode.externalApplication)) return;
  } catch (_) {}
  final web = webWalkingUri(lat: spot.lat, lon: spot.lon);
  try {
    await launchUrl(web, mode: LaunchMode.externalApplication);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No maps app available.')));
    }
  }
}
