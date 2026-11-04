import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/convoy_repo.dart';
import '../../../data/repos/convoy_sync.dart';
import 'convoy_ui.dart';

/// Invite code, QR and share button for a convoy.
Future<void> showConvoyInviteSheet(BuildContext context, Convoy convoy) {
  return showConvoySheet<void>(
    context,
    title: 'Invite to ${convoy.name}',
    builder: (_) => _InviteSheet(convoy: convoy),
  );
}

class _InviteSheet extends ConsumerWidget {
  const _InviteSheet({required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final live = ref.watch(convoyProvider(convoy.id)) ?? convoy;
    final code = live.inviteCode;
    if (code.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The invite code is on its way. Check again in a moment.',
            style: context.bodyMuted,
          ),
          const SizedBox(height: Space.lg),
          SecondaryButton(
            label: 'Check again',
            icon: Icons.refresh,
            onPressed: () => ref.read(myConvoysProvider.notifier).refresh(),
          ),
        ],
      );
    }
    final link = live.inviteLink;
    // A scanner wants dark modules on a light field. In dark mode the
    // scheme's text colour is the light one, so the pair swaps.
    final lightMode = scheme.brightness == Brightness.light;
    final field = lightMode ? scheme.surface : scheme.onSurface;
    final module = lightMode ? scheme.onSurface : scheme.surface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${live.memberCount} of ${live.maxCars} cars',
          style: context.caption,
        ),
        const SizedBox(height: Space.lg),
        Center(
          child: Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: field,
              borderRadius: Radii.tileRadius,
            ),
            child: QrImageView(
              data: link,
              size: 180,
              backgroundColor: field,
              eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: module),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: module,
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        Center(
          child: SelectableText(
            code.toUpperCase(),
            style: context.headline.copyWith(
              letterSpacing: 4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: Space.xl),
        PrimaryButton(
          label: 'Share invite',
          icon: Icons.ios_share,
          onPressed: () => SharePlus.instance.share(
            ShareParams(
              text:
                  'Join my convoy "${live.name}" on Drivalry: $link '
                  '(code ${code.toUpperCase()})',
              subject: 'Convoy invite',
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) {
              Haptics.success();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Code copied.')));
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy code'),
        ),
      ],
    );
  }
}
