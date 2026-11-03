import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../config/env.dart';
import '../../data/db/database.dart';
import '../../data/supabase/auth_service.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../tracking/providers.dart';
import '../../widgets/units.dart';
import '../profile/profile_repo.dart';

/// Account, units, location visibility, notifications, diagnostics,
/// attribution (docs/06 M2.1, ADR-018).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const String repoUrl = 'https://github.com/RyanCrawfordOrr/drivalry';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final units = ref.watch(unitsSettingProvider).value ?? UnitsSetting.auto;
    final profile = ref.watch(myProfileProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _Header('Account'),
          if (!Env.hasSupabase)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline build'),
              subtitle: Text(
                'No Drivalry cloud project is configured. Tracking and '
                'scoring work; friends and leagues do not.',
              ),
            )
          else if (!signedIn)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Sign in'),
              subtitle: const Text('Apple or Google. No passwords.'),
              onTap: () => context.push(Routes.signIn),
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(
                profile == null ? 'Your profile' : '@${profile.handle}',
              ),
              subtitle: Text(profile?.displayName ?? 'Handle, name, avatar'),
              onTap: () => context.push(Routes.profile),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export my data'),
              subtitle: const Text('Every trip on this phone, as JSON'),
              onTap: () => _export(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => _signOut(context, ref),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete account',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              subtitle: const Text(
                'Removes you from every league, circle and feed. Trips on '
                'this phone stay.',
              ),
              onTap: () => _deleteAccount(context, ref),
            ),
          ],
          const Divider(),
          const _Header('Units'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<UnitsSetting>(
              key: const Key('units-segments'),
              segments: const [
                ButtonSegment(value: UnitsSetting.auto, label: Text('Auto')),
                ButtonSegment(value: UnitsSetting.mph, label: Text('mph')),
                ButtonSegment(value: UnitsSetting.kmh, label: Text('km/h')),
              ],
              selected: {units},
              onSelectionChanged: (s) =>
                  ref.read(databaseProvider).setSetting('units', s.first.name),
            ),
          ),
          const Divider(),
          const _Header('Location'),
          SwitchListTile(
            key: const Key('hide-location'),
            secondary: const Icon(Icons.location_off_outlined),
            title: const Text('Hide my location from everyone'),
            subtitle: Text(
              signedIn
                  ? 'Friends and circles stop seeing where you are. They can '
                        'see that you are hiding.'
                  : 'Sign in to share or hide your location.',
            ),
            value: profile?.locationHidden ?? false,
            onChanged: signedIn && profile != null
                ? (v) => ref
                      .read(profileRepoProvider)
                      .setLocationHidden(profile.id, v)
                : null,
          ),
          const Divider(),
          const _Header('App'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Quiet hours, what to be told about'),
            onTap: () => context.push(Routes.notificationsSettings),
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Speed-limit packs'),
            onTap: () => context.go(Routes.packs),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_heart_outlined),
            title: const Text('Diagnostics'),
            onTap: () => context.go(Routes.diagnostics),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Attribution'),
            subtitle: const Text(
              'OpenStreetMap, Google, Open-Meteo, Nominatim',
            ),
            onTap: () => context.push(Routes.attribution),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Open source'),
            subtitle: const Text('MIT licence, built in public'),
            onTap: () => launchUrl(
              Uri.parse(repoUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
          const SizedBox(height: 24),
        ],
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
      if (context.mounted) _toast(context, 'Export failed: $e');
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) _toast(context, 'Signed out.');
    } catch (e) {
      if (context.mounted) _toast(context, 'Sign-out failed: $e');
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'Your profile, friendships, league memberships, uploaded trip '
          'summaries and posts are deleted for good. The trips stored on this '
          'phone are kept. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
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
      if (context.mounted) _toast(context, 'Delete failed: $e');
    }
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
