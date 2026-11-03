import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/routes.dart';
import '../../data/badges/badges_providers.dart';
import '../../data/badges/streaks.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';
import '../stats/profile_stats_card.dart';
import 'profile_model.dart';
import 'profile_repo.dart';

/// Your profile, or another driver's when [userId] is given (docs/01 §4.9).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.userId});

  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final id = userId ?? me;
    final own = userId == null || userId == me;
    return Scaffold(
      appBar: AppBar(
        title: Text(own ? 'Profile' : 'Driver'),
        actions: [
          if (own)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push(Routes.settings),
            ),
        ],
      ),
      body: SignedInScope(
        message: 'Sign in to have a profile your friends can see.',
        icon: Icons.person_outline,
        child: id == null
            ? const SizedBox.shrink()
            : _ProfileBody(userId: id, own: own),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.userId, required this.own});

  final String userId;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(userId));
    return profile.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load profile: $e')),
      data: (p) {
        if (p == null) {
          return const Center(child: Text('No profile yet. Pull to refresh.'));
        }
        return RefreshIndicator(
          onRefresh: () => ref.read(profileRepoProvider).refresh(userId),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: _Avatar(profile: p, own: own),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  p.displayName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Center(
                child: Text(
                  '@${p.handle}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Driver Rating',
                      value: p.driverRating == null
                          ? '–'
                          : p.driverRating!.toStringAsFixed(0),
                      hint: p.driverRating == null
                          ? 'Needs 5 scored trips'
                          : '30-day average',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Stat(
                      label: 'Passenger trips',
                      value: '${p.passengerMarkedCount}',
                      hint: 'Marked by them, honour system',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (own) ...[
                ListTile(
                  leading: const Icon(Icons.alternate_email),
                  title: const Text('Handle'),
                  subtitle: Text('@${p.handle}'),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editHandle(context, ref, p),
                ),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('Display name'),
                  subtitle: Text(p.displayName),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editDisplayName(context, ref, p),
                ),
                ListTile(
                  leading: Icon(
                    p.locationHidden
                        ? Icons.location_off_outlined
                        : Icons.location_on_outlined,
                  ),
                  title: Text(
                    p.locationHidden
                        ? 'Hidden from everyone'
                        : 'Visible to friends and circles',
                  ),
                  subtitle: const Text('Change in Settings › Location'),
                  onTap: () => context.push(Routes.settings),
                ),
              ] else
                ListTile(
                  leading: Icon(
                    p.locationHidden
                        ? Icons.location_off_outlined
                        : Icons.location_on_outlined,
                  ),
                  title: Text(
                    p.locationHidden
                        ? 'Hiding their location'
                        : 'Shares location with friends',
                  ),
                ),
              if (own) ...[
                const SizedBox(height: 8),
                const _StreaksRow(),
                const ProfileStatsCard(),
                const _BadgesRow(),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _editHandle(
    BuildContext context,
    WidgetRef ref,
    Profile p,
  ) async {
    final value = await _prompt(
      context,
      title: 'Handle',
      initial: p.handle,
      hint: 'lowercase, digits, underscore (3–20)',
      validator: Profile.validateHandle,
    );
    if (value == null || !context.mounted) return;
    try {
      await ref.read(profileRepoProvider).updateHandle(p.id, value);
    } on ProfileError catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not change handle: $e');
    }
  }

  Future<void> _editDisplayName(
    BuildContext context,
    WidgetRef ref,
    Profile p,
  ) async {
    final value = await _prompt(
      context,
      title: 'Display name',
      initial: p.displayName,
      hint: 'What friends see',
      validator: Profile.validateDisplayName,
    );
    if (value == null || !context.mounted) return;
    try {
      await ref.read(profileRepoProvider).updateDisplayName(p.id, value);
    } on ProfileError catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }
}

Future<String?> _prompt(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
  required String? Function(String) validator,
}) {
  final controller = TextEditingController(text: initial);
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          validator: (v) => validator(v ?? ''),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(controller.text.trim());
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

class _Avatar extends ConsumerWidget {
  const _Avatar({required this.profile, required this.own});

  final Profile profile;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(profileRepoProvider);
    final url = repo.avatarUrl(profile.avatarPath);
    final initials = profile.displayName.isEmpty
        ? '?'
        : profile.displayName.trim()[0].toUpperCase();
    final avatar = CircleAvatar(
      radius: 48,
      backgroundImage: url == null ? null : CachedNetworkImageProvider(url),
      child: url == null
          ? Text(initials, style: const TextStyle(fontSize: 32))
          : null,
    );
    if (!own) return avatar;
    return Stack(
      children: [
        avatar,
        Positioned(
          right: 0,
          bottom: 0,
          child: Material(
            color: Theme.of(context).colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _pick(context, ref),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.photo_camera, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await ref.read(profileRepoProvider).uploadAvatar(profile.id, bytes);
      if (context.mounted) _toast(context, 'Avatar updated.');
    } on ProfileError catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) _toast(context, 'Could not upload: $e');
    }
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelMedium),
            Text(value, style: theme.textTheme.headlineMedium),
            Text(hint, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Clean-trip and phone-free streaks, computed on this phone.
class _StreaksRow extends ConsumerWidget {
  const _StreaksRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streaks = ref.watch(streaksProvider).value;
    if (streaks == null) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: _Stat(
            label: 'Clean streak',
            value: '${streaks.clean}',
            hint: 'Trips at 80+, none reckless',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Stat(
            label: 'Phone-free streak',
            value: '${streaks.phoneFree}',
            hint: 'Trips without touching it',
          ),
        ),
      ],
    );
  }
}

/// Earned badges, newest first.
class _BadgesRow extends ConsumerWidget {
  const _BadgesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(myBadgesProvider).value;
    if (badges == null) return const SizedBox.shrink();
    final earned = badges.where((b) => b.earned).toList()
      ..sort((a, b) => b.awardedAt!.compareTo(a.awardedAt!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Badges (${earned.length}/${badges.length})',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (earned.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('None yet. Drive well.'),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in earned)
                Tooltip(
                  message: b.def.description,
                  child: Chip(
                    avatar: const Icon(Icons.military_tech, size: 18),
                    label: Text(b.def.name),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
