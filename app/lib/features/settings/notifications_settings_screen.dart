import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/push/local_notifications.dart';
import '../../data/push/push_service.dart';
import '../../data/push/quiet_hours.dart';
import '../../widgets/friendly_error.dart';
import 'widgets/settings_rows.dart';

/// Permission state as a pill with one action, quiet hours, then the
/// categories with friendly titles and one-line captions (docs/01 §4.10).
/// Crash alerts are always on.
class NotificationsSettingsScreen extends ConsumerWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushControllerProvider);
    final db = ref.watch(databaseProvider);
    final quiet = ref.watch(quietHoursProvider);
    final sections = <Widget>[
      EditorialSection(
        kicker: 'Permission',
        child: _PermissionTile(status: status),
      ),
      EditorialSection(
        kicker: 'Quiet hours',
        child: SettingsGroup(
          children: [
            SettingsSwitchRow(
              key: const Key('quiet-hours'),
              icon: Icons.bedtime_outlined,
              title: 'Quiet hours',
              caption: quiet.enabled
                  ? '${QuietHours.formatMinutes(quiet.startMinutes)} to '
                        '${QuietHours.formatMinutes(quiet.endMinutes)}. '
                        'Crash alerts still come through.'
                  : 'Nothing buzzes while you sleep.',
              value: quiet.enabled,
              onChanged: (v) => db.setSetting(
                QuietHours.settingsKey,
                quiet.copyWith(enabled: v).toJson(),
              ),
            ),
            if (quiet.enabled) ...[
              // Blank leading keeps the times in the text column above.
              SettingsRow(
                leading: const SizedBox(width: 24),
                title: 'Starts',
                trailing: Text(
                  QuietHours.formatMinutes(quiet.startMinutes),
                  style: context.label,
                ),
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
              SettingsRow(
                leading: const SizedBox(width: 24),
                title: 'Ends',
                trailing: Text(
                  QuietHours.formatMinutes(quiet.endMinutes),
                  style: context.label,
                ),
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
          ],
        ),
      ),
      EditorialSection(
        kicker: 'Alerts',
        gap: 0,
        child: SettingsGroup(
          children: [
            for (final c in const [
              NotificationCategory.tripScored,
              NotificationCategory.social,
              NotificationCategory.friends,
            ])
              _CategorySwitch(category: c),
            const SettingsSwitchRow(
              icon: Icons.car_crash_outlined,
              title: 'Crash alerts',
              caption: 'Always comes through, even in quiet hours.',
              value: true,
              onChanged: null,
            ),
          ],
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: EdgeInsets.only(
          top: Space.lg,
          bottom: Space.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (var i = 0; i < sections.length; i++)
            Reveal(delay: Reveal.stagger(i), child: sections[i]),
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

/// The quiet-hours setting, live. Settings shows it too.
final quietHoursProvider = Provider<QuietHours>(
  (ref) => QuietHours.fromJson(
    ref.watch(_settingProvider(QuietHours.settingsKey)).value,
  ),
);

final _settingProvider = StreamProvider.family<String?, String>(
  (ref, key) => ref.watch(databaseProvider).watchSetting(key),
);

class _PermissionTile extends ConsumerWidget {
  const _PermissionTile({required this.status});
  final PushStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (pill, caption) = switch (status) {
      PushRegistered() => (
        const Pill('On', tone: PillTone.positive, dot: true),
        'Alerts reach this phone.',
      ),
      PushPermissionDenied() => (
        const Pill('Blocked', tone: PillTone.danger),
        'Allow notifications for Drivalry in your phone settings.',
      ),
      PushPending() => (
        const Pill('Off'),
        'Turn them on to hear when a friend reacts or a trip scores.',
      ),
      PushUnavailable(reason: final r) => (
        const Pill('Unavailable'),
        friendlyError(Exception(r), doing: 'turn on notifications'),
      ),
    };
    return Tile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Push from friends',
                  style: context.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              pill,
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(caption, style: context.caption),
          if (status is PushPending) ...[
            const SizedBox(height: Space.lg),
            PrimaryButton(
              key: const Key('push-enable'),
              label: 'Enable',
              onPressed: () =>
                  ref.read(pushControllerProvider.notifier).start(),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategorySwitch extends ConsumerWidget {
  const _CategorySwitch({required this.category});
  final NotificationCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(_settingProvider(category.settingsKey)).value;
    return SettingsSwitchRow(
      key: Key('notify-${category.channelId}'),
      icon: switch (category) {
        NotificationCategory.tripScored => Icons.speed,
        NotificationCategory.social => Icons.chat_bubble_outline,
        NotificationCategory.friends => Icons.person_add_alt_1_outlined,
        NotificationCategory.crash => Icons.car_crash_outlined,
        NotificationCategory.convoy => Icons.route_outlined,
      },
      title: category.channelName,
      caption: switch (category) {
        NotificationCategory.tripScored =>
          'Your score and roast when you park.',
        NotificationCategory.social =>
          'When a friend reacts to or comments on a drive.',
        NotificationCategory.friends => 'When someone wants to add you.',
        NotificationCategory.crash =>
          'Always comes through, even in quiet hours.',
        NotificationCategory.convoy => 'When your convoy stops or regroups.',
      },
      value: value != 'false',
      onChanged: (v) => ref
          .read(databaseProvider)
          .setSetting(category.settingsKey, v ? 'true' : 'false'),
    );
  }
}
