import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// One row in an action sheet opened by a long-press or a status capsule:
/// icon, label, 56 tall. Pops the sheet before running [onTap].
class SheetAction extends StatelessWidget {
  const SheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: Sizes.button,
      leading: Icon(icon, color: color ?? scheme.onSurfaceVariant),
      title: Text(label, style: context.body.copyWith(color: color)),
      onTap: () {
        Haptics.tap();
        Navigator.of(context).pop();
        onTap();
      },
    );
  }
}

/// Destructive confirmations stay dialogs (docs/12 §4).
Future<bool> confirmDeleteTrip(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this trip?'),
      content: const Text(
        'It disappears from your history. Nothing was uploaded.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok == true;
}
