import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../widgets/friendly_error.dart';
import '../widgets/convoy_ui.dart';

/// The shared photo roll: small JPEGs (≤ 200 KB, ≤ 50 per convoy) in the
/// private `convoy-photos` bucket, read through hour-long signed URLs.
class ConvoyAlbumScreen extends ConsumerWidget {
  const ConvoyAlbumScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final photos = ref.watch(convoyPhotosProvider(convoyId));
    final list = photos.value ?? const <ConvoyPhoto>[];
    final members =
        ref.watch(convoyMembersProvider(convoyId)).value ?? const [];
    final nameOf = {for (final m in members) m.userId: m.name};
    final full = list.length >= ConvoyRepo.maxPhotos;
    final loading = photos.isLoading && list.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Album'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.gutter),
            child: Center(
              child: Text(
                '${list.length} of ${ConvoyRepo.maxPhotos}',
                style: context.caption,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xxxl),
        children: [
          Padding(
            padding: Space.screen,
            child: PrimaryButton(
              key: const Key('add-photo'),
              label: full ? 'Album full' : 'Add photo',
              icon: Icons.add_a_photo_outlined,
              onPressed: me == null || full ? null : () => _add(context, ref),
            ),
          ),
          const SizedBox(height: Space.xl),
          if (loading)
            const Padding(
              padding: Space.screen,
              child: Row(
                children: [
                  Expanded(child: SkeletonTile(height: 110)),
                  SizedBox(width: Space.xs),
                  Expanded(child: SkeletonTile(height: 110)),
                  SizedBox(width: Space.xs),
                  Expanded(child: SkeletonTile(height: 110)),
                ],
              ),
            ),
          if (!loading && list.isEmpty)
            const EmptyState(
              kicker: 'Album',
              headline: 'No photos yet.',
              body: 'Small ones, for the recap. Passengers, this is your job.',
            ),
          if (list.isNotEmpty)
            Padding(
              padding: Space.screen,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: Space.xs,
                  mainAxisSpacing: Space.xs,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => Reveal(
                  delay: Reveal.stagger(i),
                  child: _PhotoTile(
                    convoyId: convoyId,
                    photo: list[i],
                    by: nameOf[list[i].userId] ?? 'Someone',
                    mine: list[i].userId == me,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final source = await showDrivalrySheet<ImageSource>(
      context,
      title: 'Add a photo',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConvoyRow(
            leading: const Icon(Icons.photo_camera_outlined, size: 28),
            title: 'Take a photo',
            onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
          ),
          ConvoyRow(
            leading: const Icon(Icons.photo_library_outlined, size: 28),
            title: 'Choose from the library',
            onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
          ),
        ],
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
        Haptics.success();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, doing: 'add that photo'))),
        );
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
    final scheme = Theme.of(context).colorScheme;
    final repo = ref.watch(convoyRepoProvider);
    return FutureBuilder<String?>(
      future: repo.photoUrl(convoyId, photo.storagePath),
      builder: (context, snap) {
        final url = snap.data;
        final loading = snap.connectionState != ConnectionState.done;
        return PressScale(
          onTap: url == null ? null : () => _open(context, ref, url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Space.md),
            child: Container(
              color: scheme.surfaceContainerHigh,
              child: url == null
                  ? Shimmer(
                      enabled: loading,
                      child: Center(
                        child: Icon(
                          loading
                              ? Icons.image_outlined
                              : Icons.broken_image_outlined,
                          color: scheme.outline,
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      fadeInDuration: Motion.reveal,
                      errorWidget: (_, _, _) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: scheme.outline,
                        ),
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
        insetPadding: const EdgeInsets.all(Space.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(Radii.sheet),
              ),
              child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.sm,
                Space.sm,
              ),
              child: Row(
                children: [
                  Expanded(child: Text('By $by', style: ctx.body)),
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
