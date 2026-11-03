import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../tracking/providers.dart';

/// Settings › Safety › Auto-reply to texts (docs/01 §4.2). The phone already
/// does this well and privately; Drivalry only shows the way there. Nothing
/// here reads or sends a message.
class AutoReplySettingsScreen extends ConsumerWidget {
  const AutoReplySettingsScreen({super.key});

  static const iosSteps = [
    'Open Settings and tap Focus.',
    'Tap + and choose Driving.',
    'Turn on Auto-Reply and pick who gets it.',
    "Under Turn On Automatically, pick Automatically or your car's "
        'Bluetooth.',
  ];

  static const androidSteps = [
    'Tap Open phone settings below.',
    'Find Driving under Schedules. On a Pixel it is under Connected '
        'devices as Driving mode.',
    'Choose what gets through and whether to reply with a text.',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ios =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final steps = ios ? iosSteps : androidSteps;
    return Scaffold(
      appBar: AppBar(title: const Text('Auto-reply to texts')),
      body: ListView(
        padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
        children: [
          Padding(
            padding: Space.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your phone can answer texts for you while you drive. '
                  'Drivalry never sends replies.',
                  style: context.body,
                ),
                const SizedBox(height: Space.sm),
                Text(
                  'It is built into your phone, so no app reads your '
                  'messages.',
                  style: context.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.section),
          EditorialSection(
            kicker: ios ? 'Driving Focus' : 'Driving mode',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(height: Space.sm),
                  _Step(number: i + 1, text: steps[i]),
                ],
              ],
            ),
          ),
          Padding(
            padding: Space.screen,
            child: ios
                ? SecondaryButton(
                    key: const Key('auto-reply-copy'),
                    label: 'Copy the steps',
                    icon: Icons.copy,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: [
                            for (var i = 0; i < steps.length; i++)
                              '${i + 1}. ${steps[i]}',
                          ].join('\n'),
                        ),
                      );
                      if (context.mounted) _toast(context, 'Steps copied.');
                    },
                  )
                : PrimaryButton(
                    key: const Key('auto-reply-open'),
                    label: 'Open phone settings',
                    icon: Icons.open_in_new,
                    onPressed: () async {
                      final opened = await ref
                          .read(trackingPortProvider)
                          .openDrivingModeSettings();
                      if (!context.mounted) return;
                      if (!opened) {
                        _toast(
                          context,
                          'Could not open it here. Look for Do Not Disturb '
                          "in your phone's Sound settings.",
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static void _toast(BuildContext context, String message) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
}

/// One numbered step: a 32 px numeral in the display face beside the text.
class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tile(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: Space.xxl,
            child: Text(
              '$number',
              style: context.displaySmall.copyWith(
                fontSize: 32,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(width: Space.lg),
          Expanded(child: Text(text, style: context.body)),
        ],
      ),
    );
  }
}
