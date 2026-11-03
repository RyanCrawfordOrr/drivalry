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
import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../widgets/friendly_error.dart';
import '../../../widgets/relative_time.dart';
import '../widgets/sheet_action.dart';
import 'parking_links.dart';
import 'parking_memory.dart';

/// "Parked near Elm St · 12 min ago" as one tile in the Drive sheet while no
/// trip is recording. Tap opens the parking screen; the walk icon opens
/// directions straight away.
class ParkingCard extends ConsumerWidget {
  const ParkingCard({super.key, required this.spot, this.compact = true});

  final ParkingSpot spot;

  /// The Drive-sheet tile is compact; the full screen uses the same actions.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final road = ref.watch(parkingRoadNameProvider(spot.tripId)).value;
    final ago = relativeTime(
      DateTime.fromMillisecondsSinceEpoch(spot.parkedAt),
      DateTime.now(),
    );
    final title = road == null || road.isEmpty ? 'Parked' : 'Parked near $road';
    final note = spot.note;
    final caption = note == null || note.isEmpty ? ago : '$ago · $note';

    return Tile(
      key: const Key('parking-card'),
      onTap: compact ? () => context.push(Routes.parking) : null,
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.md,
        Space.lg,
      ),
      child: Row(
        children: [
          Icon(Icons.local_parking, color: scheme.primary),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  caption,
                  style: context.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (spot.photoPath != null && compact) ...[
            const SizedBox(width: Space.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(Space.sm),
              child: Image.file(
                File(spot.photoPath!),
                width: Sizes.touch,
                height: Sizes.touch,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(width: Space.sm),
          IconButton.filledTonal(
            tooltip: 'Walk to car',
            onPressed: () => openWalkBack(context, spot),
            icon: const Icon(Icons.directions_walk),
          ),
        ],
      ),
    );
  }
}

/// Walk to car · Photo · Note · Forget.
class ParkingActions extends ConsumerWidget {
  const ParkingActions({super.key, required this.spot});

  final ParkingSpot spot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        TextButton.icon(
          onPressed: () => openWalkBack(context, spot),
          icon: const Icon(Icons.directions_walk),
          label: const Text('Walk to car'),
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
    ImageSource? source;
    await showDrivalrySheet<void>(
      context,
      title: 'Add a photo',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetAction(
            icon: Icons.photo_camera,
            label: 'Take a photo',
            onTap: () => source = ImageSource.camera,
          ),
          SheetAction(
            icon: Icons.photo_library,
            label: 'Pick from photos',
            onTap: () => source = ImageSource.gallery,
          ),
        ],
      ),
    );
    if (source == null) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source!,
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, doing: 'save the photo'))),
        );
      }
    }
  }

  Future<void> _editNote(BuildContext context, WidgetRef ref) async {
    final value = await showDrivalrySheet<String>(
      context,
      title: 'Parking note',
      builder: (_) => TextControllers(
        initial: [spot.note ?? ''],
        builder: (ctx, c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: c.first,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(
                  hintText: 'Level 3, near the lift',
                ),
              ),
              const SizedBox(height: Space.lg),
              PrimaryButton(
                label: 'Save',
                onPressed: () => Navigator.of(ctx).pop(c.first.text),
              ),
            ],
          ),
        ),
      ),
    );
    if (value == null) return;
    await ref.read(parkingMemoryProvider).setNote(spot.tripId, value.trim());
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget this spot?'),
        content: const Text('The photo and note go with it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No maps app on this phone.')),
      );
    }
  }
}
