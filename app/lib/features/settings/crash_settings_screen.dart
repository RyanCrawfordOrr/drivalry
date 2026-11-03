import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/crash/crash_monitor.dart';
import '../../data/db/database.dart';
import 'widgets/settings_rows.dart';

/// Settings › Crash detection (docs/01 §4.5, docs/06 M3.4): the switch, two
/// sentences on what happens, the contacts and test rows, and the history as
/// two stat tiles.
class CrashSettingsScreen extends ConsumerWidget {
  const CrashSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(crashMonitorProvider);
    final monitor = ref.read(crashMonitorProvider.notifier);
    final falsePositives = ref.watch(crashFalsePositivesProvider).value ?? 0;
    final lastAt = ref.watch(_lastCandidateProvider).value;
    final contacts = ref.watch(_contactCountProvider).value ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Crash detection')),
      body: ListView(
        padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
        children: [
          Padding(
            padding: Space.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroup(
                  children: [
                    SettingsSwitchRow(
                      key: const Key('crash-enabled'),
                      icon: Icons.car_crash_outlined,
                      title: 'Detect crashes',
                      caption:
                          'A hard hit and a dead stop start a 30-second '
                          'check.',
                      value: state.enabled,
                      onChanged: (v) {
                        Haptics.select();
                        monitor.setEnabled(v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: Space.md),
                Tile(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Tap I'm OK and nothing happens. Say nothing and "
                        'your friends get a push and your contacts a text '
                        'with your location.',
                        style: context.body,
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        'Drivalry never places a call. Low-speed bumps and '
                        'dropped phones are ignored.',
                        style: context.caption,
                      ),
                    ],
                  ),
                ),
                if (state.unresolved != null) ...[
                  const SizedBox(height: Space.md),
                  Tile(
                    tone: TileTone.danger,
                    onTap: () => context.push(Routes.crash),
                    child: Row(
                      children: [
                        Icon(
                          Icons.emergency_share,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: Space.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Help was requested',
                                style: context.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tap to confirm you are OK.',
                                style: context.caption,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.section),
          EditorialSection(
            kicker: 'If nobody answers',
            child: SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.contact_phone_outlined,
                  title: 'Emergency contacts',
                  caption: contacts == 0
                      ? 'None yet. Add at least one so the text has somewhere '
                            'to go.'
                      : '$contacts ${contacts == 1 ? 'contact' : 'contacts'}',
                  onTap: () => context.push(Routes.emergencyContacts),
                ),
                SettingsRow(
                  icon: Icons.play_circle_outline,
                  title: 'Test the countdown',
                  caption: 'The full-screen check with sound. Nothing is sent.',
                  onTap: () {
                    monitor.startTest();
                    context.push(Routes.crash);
                  },
                ),
              ],
            ),
          ),
          EditorialSection(
            kicker: 'So far',
            gap: 0,
            child: StatGrid(
              columns: 2,
              children: [
                StatTile(
                  value: '$falsePositives',
                  label: falsePositives == 1 ? 'False alarm' : 'False alarms',
                ),
                StatTile(
                  value: lastAt == null
                      ? 'Never'
                      : DateFormat.MMMd().format(
                          DateTime.fromMillisecondsSinceEpoch(lastAt),
                        ),
                  label: 'Last check',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _lastCandidateProvider = StreamProvider<int?>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(CrashKeys.lastCandidateAt)
      .map((v) => int.tryParse(v ?? '')),
);

final _contactCountProvider = StreamProvider<int>(
  (ref) => ref
      .watch(databaseProvider)
      .watchEmergencyContacts()
      .map((rows) => rows.length),
);
