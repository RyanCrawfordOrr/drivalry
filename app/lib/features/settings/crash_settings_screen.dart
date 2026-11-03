import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/routes.dart';
import '../../data/crash/crash_monitor.dart';
import '../../data/db/database.dart';

/// Settings › Crash detection (docs/01 §4.5, docs/06 M3.4).
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
        children: [
          SwitchListTile(
            key: const Key('crash-enabled'),
            secondary: const Icon(Icons.car_crash_outlined),
            title: const Text('Detect crashes'),
            subtitle: const Text(
              'A hard impact followed by a dead stop starts a 30-second '
              'check on this phone.',
            ),
            value: state.enabled,
            onChanged: monitor.setEnabled,
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'If you tap "I\'m OK" nothing happens. If nobody answers, '
              'friends and circle members who use Drivalry get a push, and a '
              'text with your location is prepared for your emergency '
              'contacts. Drivalry never places a call. Low-speed bumps and a '
              'dropped phone are ignored: the car has to have been moving.',
            ),
          ),
          if (state.unresolved != null)
            Card(
              margin: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.emergency_share),
                title: const Text('Help was requested'),
                subtitle: const Text('Tap to confirm you are OK.'),
                onTap: () => context.push(Routes.crash),
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.contact_phone_outlined),
            title: const Text('Emergency contacts'),
            subtitle: Text(
              contacts == 0
                  ? 'None yet. Add at least one so the text has somewhere to go.'
                  : '$contacts ${contacts == 1 ? 'contact' : 'contacts'}',
            ),
            onTap: () => context.push(Routes.emergencyContacts),
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: const Text('Test the countdown'),
            subtitle: const Text(
              'Runs the full-screen check with sound. Nothing is sent.',
            ),
            onTap: () {
              monitor.startTest();
              context.push(Routes.crash);
            },
          ),
          const Divider(),
          ListTile(
            dense: true,
            title: const Text('False alarms you dismissed'),
            trailing: Text('$falsePositives'),
          ),
          ListTile(
            dense: true,
            title: const Text('Last detection'),
            trailing: Text(
              lastAt == null
                  ? 'never'
                  : DateFormat.yMd().add_jm().format(
                      DateTime.fromMillisecondsSinceEpoch(lastAt),
                    ),
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
