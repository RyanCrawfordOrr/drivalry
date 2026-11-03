import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tracking/providers.dart';

/// Settings › During a drive › Auto-reply to texts (docs/01 §4.2). The OS
/// already does this well and privately; Drivalry only shows the way there.
/// Nothing here reads or sends a message.
class AutoReplySettingsScreen extends ConsumerWidget {
  const AutoReplySettingsScreen({super.key});

  static const iosSteps = [
    'Open Settings and tap Focus.',
    'Tap + and choose Driving.',
    'Turn on Auto-Reply and pick who gets it (Favourites or Recents).',
    'Set it to turn on automatically when driving or when connected to '
        'CarPlay or your car\'s Bluetooth.',
  ];

  static const androidSteps = [
    'Open Do Not Disturb settings (button below).',
    'Add or edit the Driving schedule (on Pixel: Settings › Connected '
        'devices › Connection preferences › Driving mode).',
    'Choose what gets through and whether to reply with a text.',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ios =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final steps = ios ? iosSteps : androidSteps;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Auto-reply to texts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Your phone can answer texts for you while you drive. That '
            'feature lives in the operating system, not in Drivalry: it is '
            'private, works in every messaging app, and does not need this '
            'app to read your messages. Drivalry never sends replies.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            ios ? 'Set up a Driving Focus' : 'Set up Android\'s driving mode',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 12, child: Text('${i + 1}')),
              title: Text(steps[i]),
            ),
          const SizedBox(height: 16),
          if (ios)
            OutlinedButton.icon(
              key: const Key('auto-reply-copy'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: [
                      for (var i = 0; i < steps.length; i++)
                        '${i + 1}. ${steps[i]}',
                    ].join('\n'),
                  ),
                );
                if (context.mounted) _toast(context, 'Steps copied');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy the steps'),
            )
          else
            FilledButton.icon(
              key: const Key('auto-reply-open'),
              onPressed: () async {
                final opened = await ref
                    .read(trackingPortProvider)
                    .openDrivingModeSettings();
                if (!context.mounted) return;
                if (!opened) {
                  _toast(
                    context,
                    'Could not open it here. Look under Settings › Sound › '
                    'Do Not Disturb.',
                  );
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Do Not Disturb settings'),
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
