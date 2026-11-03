import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../cues/cue_settings.dart';
import '../cues/cue_speaker.dart';
import 'widgets/settings_rows.dart';

/// Spoken cues during a drive (docs/01 §4.2). Off by default.
class CuesSettingsScreen extends ConsumerWidget {
  const CuesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(cueSettingsProvider).value ?? const CueSettings();
    final db = ref.read(databaseProvider);
    Future<void> set(String key, bool v) =>
        setCueSetting(db, key, v ? 'true' : 'false');

    final blocks = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.section,
        ),
        child: SettingsGroup(
          children: [
            SettingsSwitchRow(
              key: const Key('cues-enabled'),
              icon: Icons.record_voice_over_outlined,
              title: 'Spoken cues',
              caption: 'Short words through the car speakers.',
              value: cfg.enabled,
              onChanged: (v) => set(CueKeys.enabled, v),
            ),
          ],
        ),
      ),
      EditorialSection(
        kicker: 'Cues',
        child: SettingsGroup(
          children: [
            SettingsSwitchRow(
              key: const Key('cues-limit'),
              title: 'New speed limit',
              caption: '"Limit\'s 35" when the posted limit changes.',
              value: cfg.limit,
              onChanged: cfg.enabled ? (v) => set(CueKeys.limit, v) : null,
            ),
            SettingsSwitchRow(
              key: const Key('cues-over'),
              title: 'Over the limit',
              caption:
                  '"Over by 8" after eight seconds over, at most once a '
                  'minute.',
              value: cfg.over,
              onChanged: cfg.enabled ? (v) => set(CueKeys.over, v) : null,
            ),
            SettingsSwitchRow(
              key: const Key('cues-smooth'),
              title: 'Smooth driving',
              caption: '"Smooth" after five clean minutes.',
              value: cfg.smooth,
              onChanged: cfg.enabled ? (v) => set(CueKeys.smooth, v) : null,
            ),
          ],
        ),
      ),
      EditorialSection(
        kicker: 'Voice',
        child: Tile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Kicker('Voice speed')),
                  Text('${cfg.rate.toStringAsFixed(1)}×', style: context.label),
                ],
              ),
              const SizedBox(height: Space.sm),
              Slider(
                key: const Key('cues-rate'),
                value: cfg.rate,
                min: CueSettings.minRate,
                max: CueSettings.maxRate,
                divisions: 6,
                label: '${cfg.rate.toStringAsFixed(1)}×',
                padding: EdgeInsets.zero,
                onChangeEnd: (_) => Haptics.select(),
                onChanged: (v) =>
                    setCueSetting(db, CueKeys.rate, v.toStringAsFixed(1)),
              ),
              const SizedBox(height: Space.lg),
              SecondaryButton(
                key: const Key('cues-sample'),
                label: 'Say a sample',
                icon: Icons.play_arrow,
                onPressed: () async {
                  Haptics.tap();
                  final speaker = ref.read(cueSpeakerProvider);
                  await speaker.setRate(cfg.rate);
                  await speaker.speak("Limit's 35. Smooth.");
                },
              ),
            ],
          ),
        ),
      ),
      Padding(
        padding: Space.screen,
        child: Text(
          'Cues come from the roads stored on this phone. Nothing is said '
          'where the limit is unknown. The roast waits until you park.',
          style: context.caption,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Spoken cues')),
      body: ListView(
        padding: EdgeInsets.only(
          top: Space.lg,
          bottom: Space.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (var i = 0; i < blocks.length; i++)
            Reveal(delay: Reveal.stagger(i), child: blocks[i]),
        ],
      ),
    );
  }
}
