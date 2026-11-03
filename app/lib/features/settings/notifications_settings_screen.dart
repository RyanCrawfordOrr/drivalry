import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database.dart';
import '../../data/push/local_notifications.dart';
import '../../data/push/push_service.dart';
import '../../data/push/quiet_hours.dart';

/// Registration status, quiet hours and the per-category switches
/// (docs/01 §4.10). Crash alerts are always on.
class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushControllerProvider);
    final db = ref.watch(databaseProvider);
    final quiet = QuietHours.fromJson(
      ref.watch(_settingProvider(QuietHours.settingsKey)).value,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(switch (status) {
              PushRegistered() => Icons.notifications_active_outlined,
              PushPermissionDenied() => Icons.notifications_off_outlined,
              PushPending() => Icons.notifications_none,
              PushUnavailable() => Icons.cloud_off_outlined,
            }),
            title: const Text('Push from friends'),
            subtitle: Text(switch (status) {
              PushRegistered() => 'Registered on this device.',
              PushPermissionDenied() =>
                'Permission denied. Allow notifications in the system '
                    'settings.',
              PushPending() => 'Not registered yet.',
              PushUnavailable(reason: final r) => r,
            }),
            trailing: status is PushPending
                ? TextButton(
                    onPressed: () =>
                        ref.read(pushControllerProvider.notifier).start(),
                    child: const Text('Enable'),
                  )
                : null,
          ),
          const Divider(),
          SwitchListTile(
            key: const Key('quiet-hours'),
            secondary: const Icon(Icons.bedtime_outlined),
            title: const Text('Quiet hours'),
            subtitle: Text(
              quiet.enabled
                  ? '${QuietHours.formatMinutes(quiet.startMinutes)} to '
                        '${QuietHours.formatMinutes(quiet.endMinutes)}. '
                        'Crash alerts still come through.'
                  : 'Off',
            ),
            value: quiet.enabled,
            onChanged: (v) => db.setSetting(
              QuietHours.settingsKey,
              quiet.copyWith(enabled: v).toJson(),
            ),
          ),
          if (quiet.enabled) ...[
            ListTile(
              title: const Text('Start'),
              trailing: Text(QuietHours.formatMinutes(quiet.startMinutes)),
              onTap: () async {
                final t = await _pickTime(context, quiet.startMinutes);
                if (t != null) {
                  await db.setSetting(
                    QuietHours.settingsKey,
                    quiet.copyWith(startMinutes: t).toJson(),
                  );
                }
              },
            ),
            ListTile(
              title: const Text('End'),
              trailing: Text(QuietHours.formatMinutes(quiet.endMinutes)),
              onTap: () async {
                final t = await _pickTime(context, quiet.endMinutes);
                if (t != null) {
                  await db.setSetting(
                    QuietHours.settingsKey,
                    quiet.copyWith(endMinutes: t).toJson(),
                  );
                }
              },
            ),
          ],
          const Divider(),
          for (final c in const [
            NotificationCategory.tripScored,
            NotificationCategory.social,
            NotificationCategory.friends,
          ])
            _CategorySwitch(category: c),
          const ListTile(
            leading: Icon(Icons.car_crash_outlined),
            title: Text('Crash alerts'),
            subtitle: Text('Always on. Ignores quiet hours.'),
            trailing: Switch(value: true, onChanged: null),
          ),
        ],
      ),
    );
  }

  Future<int?> _pickTime(BuildContext context, int minutes) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }
}

final _settingProvider = StreamProvider.family<String?, String>(
  (ref, key) => ref.watch(databaseProvider).watchSetting(key),
);

class _CategorySwitch extends ConsumerWidget {
  const _CategorySwitch({required this.category});
  final NotificationCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(_settingProvider(category.settingsKey)).value;
    return SwitchListTile(
      key: Key('notify-${category.channelId}'),
      secondary: Icon(switch (category) {
        NotificationCategory.tripScored => Icons.speed,
        NotificationCategory.social => Icons.chat_bubble_outline,
        NotificationCategory.friends => Icons.person_add_alt_1_outlined,
        NotificationCategory.crash => Icons.car_crash_outlined,
      }),
      title: Text(category.channelName),
      value: value != 'false',
      onChanged: (v) => ref
          .read(databaseProvider)
          .setSetting(category.settingsKey, v ? 'true' : 'false'),
    );
  }
}
