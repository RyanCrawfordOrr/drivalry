import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';

/// A failure that does not block the screen: one friendly sentence in a
/// resting tile with a text button to try again. Replaces banners and raw
/// exception text (docs/12 §1.7, audit item 2).
class QuietErrorTile extends StatelessWidget {
  const QuietErrorTile({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Retry',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Tile(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.sm,
        Space.md,
      ),
      child: Row(
        children: [
          Expanded(child: Text(message, style: context.bodyMuted)),
          if (onRetry != null) ...[
            const SizedBox(width: Space.sm),
            TextButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ],
      ),
    );
  }
}
