import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../cues/cue_settings.dart';
import '../cues/cue_speaker.dart';

/// Spoken cues during a drive (docs/01 §4.2). Off by default.
class CuesSettingsScreen extends ConsumerWidget {
  const CuesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(cueSettingsProvider).value ?? const CueSettings();
    final db = ref.read(databaseProvider);
    Future<void> set(String key, bool v) =>
        setCueSetting(db, key, v ? 'true' : 'false');

    return Scaffold(
      appBar: AppBar(title: const Text('Spoken cues')),
      body: ListView(
        children: [
          SwitchListTile(
            key: const Key('cues-enabled'),
            secondary: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Spoken cues'),
            subtitle: const Text(
              'Short spoken cues through the car speakers during a drive. '
              'Off by default. The roast always waits until the trip ends.',
            ),
            value: cfg.enabled,
            onChanged: (v) => set(CueKeys.enabled, v),
          ),
          const Divider(),
          SwitchListTile(
            key: const Key('cues-limit'),
            title: const Text('Limit changes'),
            subtitle: const Text('"Limit\'s 35" when the posted limit changes'),
            value: cfg.limit,
            onChanged: cfg.enabled ? (v) => set(CueKeys.limit, v) : null,
          ),
          SwitchListTile(
            key: const Key('cues-over'),
            title: const Text('Over the limit'),
            subtitle: const Text(
              '"Over by 8" after eight seconds at least 5 mph over, at most '
              'once a minute',
            ),
            value: cfg.over,
            onChanged: cfg.enabled ? (v) => set(CueKeys.over, v) : null,
          ),
          SwitchListTile(
            key: const Key('cues-smooth'),
            title: const Text('Smooth driving'),
            subtitle: const Text('"Smooth" after five clean minutes'),
            value: cfg.smooth,
            onChanged: cfg.enabled ? (v) => set(CueKeys.smooth, v) : null,
          ),
          const Divider(),
          ListTile(
            title: const Text('Voice speed'),
            subtitle: Slider(
              key: const Key('cues-rate'),
              value: cfg.rate,
              min: CueSettings.minRate,
              max: CueSettings.maxRate,
              divisions: 6,
              label: '${cfg.rate.toStringAsFixed(1)}×',
              onChanged: (v) =>
                  setCueSetting(db, CueKeys.rate, v.toStringAsFixed(1)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton.icon(
              key: const Key('cues-sample'),
              onPressed: () async {
                final speaker = ref.read(cueSpeakerProvider);
                await speaker.setRate(cfg.rate);
                await speaker.speak("Limit's 35. Smooth.");
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Say a sample'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Cues use the speed-limit pack on this phone and never the '
              'network. Nothing is said on roads without a known limit, and '
              'phone handling is never a cue.',
            ),
          ),
        ],
      ),
    );
  }
}
