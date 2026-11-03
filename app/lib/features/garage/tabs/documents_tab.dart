import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../data/repos/garage_repo.dart';
import '../../settings/widgets/settings_rows.dart';

/// Insurance card, registration: photos encrypted on this phone.
class DocumentsTab extends ConsumerWidget {
  const DocumentsTab({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider(vehicle.id)).value ?? const [];
    final date = DateFormat.yMMMd();

    if (docs.isEmpty) {
      return ListView(
        children: [
          EmptyState(
            kicker: 'Documents',
            headline: 'Keep your papers here.',
            body:
                'Insurance card, registration: photos stay encrypted on this '
                'phone.',
            actionLabel: 'Add document',
            onAction: () => _add(context, ref),
          ),
        ],
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'documents-fab',
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Document'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xxxl + Space.xxl,
        ),
        children: [
          Text(
            'Stored encrypted on this phone only. Never uploaded, never '
            'shared.',
            style: context.caption,
          ),
          const SizedBox(height: Space.lg),
          for (final d in docs) ...[
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.lock_outline,
                  title: d.title,
                  caption: date.format(
                    DateTime.fromMillisecondsSinceEpoch(d.createdAt),
                  ),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, ref, d),
                  ),
                  onTap: () => _view(context, ref, d),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
          ],
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final source = await showDrivalrySheet<ImageSource>(
      context,
      title: 'New document',
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Take a photo',
              icon: Icons.photo_camera_outlined,
              onPressed: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            const SizedBox(height: Space.sm),
            SecondaryButton(
              label: 'Choose from library',
              icon: Icons.photo_library_outlined,
              onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await ref
        .read(garageRepoProvider)
        .addDocument(
          vehicleId: vehicle.id,
          title: title.text.trim().isEmpty ? 'Document' : title.text,
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
