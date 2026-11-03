import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/crash/crash_monitor.dart';
import '../../data/db/database.dart';
import '../../data/push/quiet_hours.dart';
import '../../data/supabase/auth_service.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../tracking/providers.dart';
import '../../tracking/tracking_controller.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/units.dart';
import '../cues/cue_settings.dart';
import '../profile/profile_repo.dart';
import 'emergency_contacts_screen.dart';
import 'notifications_settings_screen.dart';
import 'widgets/settings_rows.dart';

/// Settings as an editorial list (docs/12 §7): Drives, Friends, Safety,
/// Account and About, each a kicker over one tonal group of rows with a
/// one-line caption. Packs and Diagnostics are pushed so the back stack
/// survives (docs/12-ux-audit.md §1).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const String repoUrl = 'https://github.com/RyanCrawfordOrr/drivalry';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloud = ref.watch(cloudConfiguredProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final units = ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto;
    final profile = ref.watch(myProfileProvider).value;
    final tracking = ref.watch(trackingControllerProvider);
    final cues = ref.watch(cueSettingsProvider).value ?? const CueSettings();
    final quiet = ref.watch(quietHoursProvider);
    final crashOn = ref.watch(_crashEnabledProvider).value ?? true;
    final contacts = ref.watch(emergencyContactsProvider).value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
        children: [
          EditorialSection(
            kicker: 'Drives',
            child: SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.speed_outlined,
                  title: 'Units',
                  caption: 'Auto follows the roads you drive on.',
                  below: SegmentedButton<UnitsSetting>(
                    key: const Key('units-segments'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: UnitsSetting.auto,
                        label: Text('Auto'),
                      ),
                      ButtonSegment(
                        value: UnitsSetting.mph,
                        label: Text('mph'),
                      ),
                      ButtonSegment(
                        value: UnitsSetting.kmh,
                        label: Text('km/h'),
                      ),
                    ],
                    selected: {units},
                    onSelectionChanged: (s) {
                      Haptics.select();
                      ref
                          .read(databaseProvider)
                          .setSetting('units', s.first.name);
                    },
                  ),
                ),
                SettingsSwitchRow(
                  key: const Key('auto-detect'),
                  icon: Icons.directions_car_outlined,
                  title: 'Start drives on their own',
                  caption: tracking.plugin.enabled
                      ? 'The app notices when you set off and scores when '
                            'you park.'
                      : 'Off. Nothing is recorded until you turn this on.',
                  value: tracking.plugin.enabled,
                  onChanged: (v) => _setAutoDetect(context, ref, v),
                ),
                SettingsRow(
                  icon: Icons.record_voice_over_outlined,
                  title: 'Spoken cues',
                  caption: cues.enabled
                      ? 'On. Short words through the car speakers.'
                      : 'Off. Short words through the car speakers.',
                  onTap: () => context.push(Routes.cuesSettings),
                ),
                SettingsRow(
                  icon: Icons.map_outlined,
                  title: 'Speed-limit packs',
                  caption: 'Roads and limits kept on this phone.',
                  onTap: () => context.push(Routes.packs),
                ),
              ],
            ),
          ),
          EditorialSection(
            kicker: 'Friends',
            child: SettingsGroup(
              children: [
                SettingsSwitchRow(
                  key: const Key('hide-location'),
                  icon: Icons.location_off_outlined,
                  title: 'Hide my location',
                  caption: signedIn
                      ? 'Friends see that you are hiding, not where you are.'
                      : 'Sign in to share or hide your location.',
                  value: profile?.locationHidden ?? false,
                  onChanged: signedIn && profile != null
                      ? (v) {
                          Haptics.select();
                          ref
                              .read(profileRepoProvider)
                              .setLocationHidden(profile.id, v);
                        }
                      : null,
                ),
                SettingsRow(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  caption: 'What you hear about.',
                  onTap: () => context.push(Routes.notificationsSettings),
                ),
                SettingsRow(
                  icon: Icons.bedtime_outlined,
                  title: 'Quiet hours',
                  caption: quiet.enabled
                      ? '${QuietHours.formatMinutes(quiet.startMinutes)} to '
                            '${QuietHours.formatMinutes(quiet.endMinutes)}. '
                            'Crash alerts still come through.'
                      : 'Off. Set a window when nothing buzzes.',
                  onTap: () => context.push(Routes.notificationsSettings),
                ),
              ],
            ),
          ),
          EditorialSection(
            kicker: 'Safety',
            child: SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.car_crash_outlined,
                  title: 'Crash detection',
                  caption: crashOn
                      ? 'On. A 30-second check after a hard stop.'
                      : 'Off. Turn it on for a 30-second check after a hard '
                            'stop.',
                  onTap: () => context.push(Routes.crashSettings),
                ),
                SettingsRow(
                  icon: Icons.contact_phone_outlined,
                  title: 'Emergency contacts',
                  caption: contacts == 0
                      ? 'Who gets a text if you do not answer.'
                      : '$contacts ${contacts == 1 ? 'person gets' : 'people get'} '
                            'a text if you do not answer.',
                  onTap: () => context.push(Routes.emergencyContacts),
                ),
                SettingsRow(
                  key: const Key('auto-reply'),
                  icon: Icons.sms_outlined,
                  title: 'Auto-reply to texts',
                  caption: 'Your phone can answer texts while you drive.',
                  onTap: () => context.push(Routes.autoReplySettings),
                ),
              ],
            ),
          ),
          EditorialSection(
            kicker: 'Account',
            child: SettingsGroup(
              children: [
                if (!cloud)
                  const SettingsRow(
                    icon: Icons.cloud_off_outlined,
                    title: 'Not available in this version yet.',
                    caption:
                        'Friends and leagues are coming. Drives still score '
                        'on this phone.',
                  )
                else if (!signedIn)
                  SettingsRow(
                    icon: Icons.login,
                    title: 'Sign in',
                    caption: 'Apple or Google. No passwords.',
                    onTap: () => context.push(Routes.signIn),
                  )
                else ...[
                  SettingsRow(
                    leading: Avatar(
                      name: profile?.displayName ?? '?',
                      size: AvatarSize.sm,
                      isMe: true,
                    ),
                    title: profile == null
                        ? 'Your profile'
                        : '@${profile.handle}',
                    caption: profile?.displayName ?? 'Handle, name, photo.',
                    onTap: () => context.push(Routes.profile),
                  ),
                  SettingsRow(
                    icon: Icons.ios_share,
                    title: 'Export my data',
                    caption: 'Every trip on this phone, in a file you keep.',
                    onTap: () => _export(context, ref),
                  ),
                  SettingsRow(
                    icon: Icons.logout,
                    title: 'Sign out',
                    caption: 'Trips stay on this phone.',
                    onTap: () => _signOut(context, ref),
                  ),
                  SettingsRow(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete account',
                    caption:
                        'Leaves every league, circle and feed for good. '
                        'Trips on this phone stay.',
                    danger: true,
                    onTap: () => _deleteAccount(context, ref),
                  ),
                ],
              ],
            ),
          ),
          EditorialSection(
            kicker: 'About',
            gap: 0,
            child: SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.info_outline,
                  title: 'About Drivalry',
                  caption: 'Where the roads, maps and weather come from.',
                  onTap: () => context.push(Routes.attribution),
                ),
                SettingsRow(
                  icon: Icons.code,
                  title: 'Open source',
                  caption: 'Read the code, report a bug, build your own.',
                  trailing: const Pill('MIT', compact: true),
                  onTap: () => launchUrl(
                    Uri.parse(repoUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                SettingsRow(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Diagnostics',
                  caption: 'Numbers for bug reports.',
                  onTap: () => context.push(Routes.diagnostics),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setAutoDetect(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    Haptics.select();
    final controller = ref.read(trackingControllerProvider.notifier);
    await controller.setEnabled(enabled);
    if (!context.mounted || enabled) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Drives are no longer recorded.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.setEnabled(true),
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final profile = ref.read(myProfileProvider).value;
      await ref
          .read(authServiceProvider)
          .exportMyData(
            ref.read(databaseProvider),
            profileJson: profile == null ? null : jsonEncode(profile.toJson()),
          );
    } catch (e) {
      if (context.mounted) {
        _toast(context, friendlyError(e, doing: 'export your data'));
      }
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) _toast(context, 'Signed out.');
    } catch (e) {
      if (context.mounted) _toast(context, friendlyError(e, doing: 'sign out'));
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your profile, friendships, leagues, shared trips and posts are '
          'deleted for good. Trips on this phone are kept. This cannot be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(authServiceProvider)
          .deleteAccount(ref.read(databaseProvider));
      if (context.mounted) _toast(context, 'Account deleted.');
    } catch (e) {
      if (context.mounted) {
        _toast(context, friendlyError(e, doing: 'delete your account'));
      }
    }
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Crash detection on/off, read straight from the setting so Settings never
/// has to wake the crash monitor (default on, docs/01 §4.5).
final _crashEnabledProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(CrashKeys.enabled)
      .map((v) => v != 'false'),
);
