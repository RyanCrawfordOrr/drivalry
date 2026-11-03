import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../data/db/database.dart';
import '../../../data/repos/garage_repo.dart';

/// Insurance card, registration: photos encrypted on this phone.
class DocumentsTab extends ConsumerWidget {
  const DocumentsTab({super.key, required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider(vehicle.id)).value ?? const [];
    final theme = Theme.of(context);
    final date = DateFormat.yMMMd();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'documents-fab',
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Document'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Text(
            'Stored encrypted on this phone only. Never uploaded, never '
            'shared.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (docs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No documents yet. Add a photo of your insurance card or '
                'registration.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          for (final d in docs)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(d.title),
              subtitle: Text(
                date.format(DateTime.fromMillisecondsSinceEpoch(d.createdAt)),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(context, ref, d),
              ),
              onTap: () => _view(context, ref, d),
            ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add document'),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ImageSource.gallery),
            child: const Text('Library'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ImageSource.camera),
            child: const Text('Camera'),
          ),
        ],
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
      bytes = null;
    }
    if (!context.mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not decrypt this document.')),
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
              padding: const EdgeInsets.all(12),
              child: Text(d.title, style: Theme.of(ctx).textTheme.titleMedium),
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
        content: const Text('The encrypted file is wiped from this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(garageRepoProvider).deleteDocument(d.id);
  }
}
