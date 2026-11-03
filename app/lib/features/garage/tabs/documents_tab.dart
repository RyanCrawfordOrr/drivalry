import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../data/repos/garage_repo.dart';
import '../../settings/widgets/settings_rows.dart';

/// What the new-document sheet hands back: where the photo comes from and
/// the title typed for it.
typedef _NewDocument = ({ImageSource source, String title});

/// Papers: insurance card, registration, as photos encrypted on this phone.
/// Empty and populated states cross-fade; rows arrive staggered (docs/12
/// §5b).
class DocumentsTab extends ConsumerWidget {
  const DocumentsTab({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider(vehicle.id)).value ?? const [];
    final date = DateFormat.yMMMd();

    return Scaffold(
      floatingActionButton: docs.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'documents-fab',
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Document'),
            ),
      body: StateSwitcher(
        child: docs.isEmpty
            ? ListView(
                key: const ValueKey('empty'),
                children: [
                  EmptyState(
                    kicker: 'Papers',
                    headline: "Your car's papers, in one place.",
                    body:
                        'Insurance card, registration: photos stay encrypted '
                        'on this phone.',
                    actionLabel: 'Add a photo',
                    onAction: () => _add(context, ref),
                  ),
                ],
              )
            : ListView(
                key: const ValueKey('list'),
                // The last row clears the FAB (56 + 16 margin) and the nav
                // bar with 24 to spare.
                padding: EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.lg,
                  Space.gutter,
                  Space.xxxl +
                      Space.xxxl +
                      MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Text(
                    'Stored encrypted on this phone only. Never uploaded, '
                    'never shared.',
                    style: context.caption,
                  ),
                  const SizedBox(height: Space.lg),
                  for (var i = 0; i < docs.length; i++) ...[
                    Reveal(
                      key: ValueKey(docs[i].id),
                      delay: Reveal.stagger(i),
                      child: SettingsGroup(
                        children: [
                          SettingsRow(
                            icon: Icons.lock_outline,
                            title: docs[i].title,
                            caption: date.format(
                              DateTime.fromMillisecondsSinceEpoch(
                                docs[i].createdAt,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(context, ref, docs[i]),
                            ),
                            onTap: () => _view(context, ref, docs[i]),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                ],
              ),
      ),
    );
  }

  /// The title field lives inside [TextControllers], which outlives the
  /// sheet's exit animation; the text comes back through the pop value.
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final result = await showDrivalrySheet<_NewDocument>(
      context,
      title: 'New document',
      builder: (_) => TextControllers(
        builder: (ctx, c) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: c.first,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: Space.xl),
              PrimaryButton(
                label: 'Take a photo',
                icon: Icons.photo_camera_outlined,
                onPressed: () => Navigator.of(
                  ctx,
                ).pop((source: ImageSource.camera, title: c.first.text)),
              ),
              const SizedBox(height: Space.sm),
              SecondaryButton(
                label: 'Choose from library',
                icon: Icons.photo_library_outlined,
                onPressed: () => Navigator.of(
                  ctx,
                ).pop((source: ImageSource.gallery, title: c.first.text)),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null) return;
    final picked = await ImagePicker().pickImage(
      source: result.source,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final title = result.title.trim();
    await ref
        .read(garageRepoProvider)
        .addDocument(
          vehicleId: vehicle.id,
          title: title.isEmpty ? 'Document' : title,
          bytes: bytes,
          mimeType: picked.mimeType ?? 'image/jpeg',
        );
    Haptics.success();
  }

  Future<void> _view(
    BuildContext context,
    WidgetRef ref,
    VehicleDocument d,
  ) async {
    Uint8List? bytes;
    try {
      bytes = await ref.read(garageRepoProvider).readDocument(d.id);
    } catch (e) {
      debugPrint('document ${d.id} unreadable: $e');
      bytes = null;
    }
    if (!context.mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This document can't be opened on this phone."),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text(d.title, style: ctx.title),
            ),
            Flexible(child: InteractiveViewer(child: Image.memory(bytes!))),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    VehicleDocument d,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${d.title}"?'),
        content: const Text('The photo is wiped from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(garageRepoProvider).deleteDocument(d.id);
  }
}
