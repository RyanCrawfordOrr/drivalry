import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/ui/ui.dart';
import '../../data/repos/leagues_repo.dart';

/// Invite code, QR and share button for a league.
Future<void> showInviteSheet(BuildContext context, League league) {
  return showDrivalrySheet<void>(
    context,
    title: 'Invite to ${league.name}',
    builder: (ctx) => _InviteSheet(league: league),
  );
}

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.league});
  final League league;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final link = league.inviteLink;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Tile(
            padding: const EdgeInsets.all(Space.md),
            child: QrImageView(
              data: link,
              size: 200,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: scheme.onSurface,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: scheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        SelectableText(
          league.inviteCode.toUpperCase(),
          textAlign: TextAlign.center,
          style: context.headline.copyWith(
            letterSpacing: 4,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: Space.xs),
        Text(
          'Friends enter this code in Leagues, or open the link.',
          style: context.caption,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.xl),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Copy link',
                icon: Icons.copy_outlined,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  Haptics.success();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: PrimaryButton(
                label: 'Share',
                icon: Icons.share_outlined,
                onPressed: () => SharePlus.instance.share(
                  ShareParams(
                    text:
                        'Join my Drivalry league "${league.name}": $link '
                        '(code ${league.inviteCode.toUpperCase()})',
                    subject: 'Drivalry league invite',
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
