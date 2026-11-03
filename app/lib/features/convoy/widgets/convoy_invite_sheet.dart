import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';

/// Invite code, QR and share button for a convoy.
Future<void> showConvoyInviteSheet(BuildContext context, Convoy convoy) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _InviteSheet(convoy: convoy),
  );
}

class _InviteSheet extends ConsumerWidget {
  const _InviteSheet({required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final live = ref.watch(convoyProvider(convoy.id)) ?? convoy;
    final code = live.inviteCode;
    if (code.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Invite to ${live.name}', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              const Text(
                'The invite code is on its way from the server. Pull to '
                'refresh the convoy list in a moment.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => ref.read(myConvoysProvider.notifier).refresh(),
                child: const Text('Check again'),
              ),
            ],
          ),
        ),
      );
    }
    final link = live.inviteLink;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Invite to ${live.name}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${live.memberCount} of ${live.maxCars} cars',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(data: link, size: 180),
            ),
            const SizedBox(height: 16),
            SelectableText(
              code.toUpperCase(),
              style: theme.textTheme.headlineSmall?.copyWith(
                letterSpacing: 4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copied.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy code'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => SharePlus.instance.share(
                    ShareParams(
                      text:
                          'Join my convoy "${live.name}" on Drivalry: $link '
                          '(code ${code.toUpperCase()})',
                      subject: 'Convoy invite',
                    ),
                  ),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Share'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
