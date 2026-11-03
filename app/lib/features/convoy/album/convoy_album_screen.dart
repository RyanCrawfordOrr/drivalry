import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';

/// The shared photo roll: small JPEGs (≤ 200 KB, ≤ 50 per convoy) in the
/// private `convoy-photos` bucket, read through hour-long signed URLs.
class ConvoyAlbumScreen extends ConsumerWidget {
  const ConvoyAlbumScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final me = ref.watch(currentUserIdProvider);
    final photos = ref.watch(convoyPhotosProvider(convoyId));
    final list = photos.value ?? const <ConvoyPhoto>[];
    final members =
        ref.watch(convoyMembersProvider(convoyId)).value ?? const [];
    final nameOf = {for (final m in members) m.userId: m.name};
    final full = list.length >= ConvoyRepo.maxPhotos;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Album'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${list.length}/${ConvoyRepo.maxPhotos}',
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-photo'),
        onPressed: me == null || full ? null : () => _add(context, ref),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(full ? 'Album full' : 'Add photo'),
      ),
      body: photos.isLoading && list.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No photos yet. Small ones only: the album is for the '
                  'recap, not a backup. Passengers, this is your job.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: list.length,
              itemBuilder: (_, i) => _PhotoTile(
                convoyId: convoyId,
                photo: list[i],
                by: nameOf[list[i].userId] ?? 'Someone',
                mine: list[i].userId == me,
              ),
            ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from the library'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 60,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await ref.read(convoyRepoProvider).addPhoto(convoyId, bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Added to the album.')));
      }
    } on ConvoyError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not add: $e')));
      }
    }
  }
}

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({
    required this.convoyId,
    required this.photo,
    required this.by,
    required this.mine,
  });

  final String convoyId;
  final ConvoyPhoto photo;
  final String by;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(convoyRepoProvider);
    return FutureBuilder<String?>(
      future: repo.photoUrl(convoyId, photo.storagePath),
      builder: (context, snap) {
        final url = snap.data;
        return GestureDetector(
          onTap: url == null ? null : () => _open(context, ref, url),
          child: Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: url == null
                ? Center(
                    child: Icon(
                      snap.connectionState == ConnectionState.done
                          ? Icons.broken_image_outlined
                          : Icons.image_outlined,
                      color: theme.colorScheme.outline,
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, String url) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(child: Text('By $by')),
                  if (mine)
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await ref
                            .read(convoyRepoProvider)
                            .deletePhoto(convoyId, photo);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
