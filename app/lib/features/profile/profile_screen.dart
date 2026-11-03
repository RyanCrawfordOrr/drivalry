import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/badges/badges_providers.dart';
import '../../data/badges/streaks.dart';
import '../../data/stats/stats_engine.dart';
import '../../data/stats/stats_providers.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/signed_in_scope.dart';
import '../friends/widgets/user_avatar.dart';
import '../leagues/leagues_routes.dart' show badgesPath;
import 'profile_model.dart';
import 'profile_repo.dart';

/// Your profile, or another driver's when [userId] is given (docs/01 §4.9;
/// docs/12 §7). An editorial page under a large title that collapses: the
/// avatar hero, Driver rating and clean streak as hero numbers, badges as
/// pills, the doors to Stats and Wrapped, then the account tiles. Settings
/// lives in the app bar.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.userId});

  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final id = userId ?? me;
    final own = userId == null || userId == me;
    final cloud = ref.watch(cloudConfiguredProvider);
    final signedIn = ref.watch(isSignedInProvider);
    if (id == null || !cloud || !signedIn) {
      return Scaffold(
        appBar: AppBar(title: Text(own ? 'Profile' : 'Driver')),
        body: const SignedInScope(
          message: 'Sign in to get a profile.',
          icon: Icons.person_outline,
          child: SizedBox.shrink(),
        ),
      );
    }
    return _ProfileBody(userId: id, own: own);
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.userId, required this.own});

  final String userId;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(userId));
    final repo = ref.read(profileRepoProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => repo.refresh(userId),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            LargeTitleBar(
              title: own ? 'Profile' : 'Driver',
              actions: [
                if (own)
                  IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push(Routes.settings),
                  ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
              sliver: SliverToBoxAdapter(
                child: StateSwitcher(
                  child: profile.when(
                    loading: () => Column(
                      key: const ValueKey('loading'),
                      children: [
                        for (var i = 0; i < 3; i++)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(
                              Space.gutter,
                              0,
                              Space.gutter,
                              Space.md,
                            ),
                            child: SkeletonTile(height: 120),
                          ),
                      ],
                    ),
                    error: (e, _) => EmptyState(
                      key: const ValueKey('error'),
                      kicker: 'Profile',
                      headline: 'Could not load this profile.',
                      body: friendlyError(e, doing: 'load the profile'),
                      actionLabel: 'Try again',
                      onAction: () => repo.refresh(userId),
                    ),
                    data: (p) => p == null
                        ? const EmptyState(
                            key: ValueKey('none'),
                            kicker: 'Profile',
                            headline: 'No profile yet.',
                            body: 'Pull down to check again.',
                          )
                        : _ProfileContent(
                            key: const ValueKey('profile'),
                            profile: p,
                            own: own,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileContent extends ConsumerWidget {
  const _ProfileContent({super.key, required this.profile, required this.own});

  final Profile profile;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final scheme = Theme.of(context).colorScheme;
    final streaks = own
        ? (ref.watch(streaksProvider).value ?? Streaks.none)
        : null;
    final name = p.displayName.trim().isEmpty ? '@${p.handle}' : p.displayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          child: Column(
            children: [
              _AvatarHero(profile: p, own: own),
              const SizedBox(height: Space.lg),
              Padding(
                padding: Space.screen,
                child: Text(
                  name,
                  style: context.headline,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text('@${p.handle}', style: context.caption),
            ],
          ),
        ),
        const SizedBox(height: Space.section),
        Padding(
          padding: Space.screen,
          child: Reveal(
            delay: Reveal.stagger(1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _HeroStat(
                    kicker: 'Driver rating',
                    value: p.driverRating?.round(),
                    caption: p.driverRating == null
                        ? 'Needs 5 scored trips'
                        : 'Last 30 days',
                  ),
                ),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: own
                      ? _HeroStat(
                          kicker: 'Clean streak',
                          value: streaks!.clean,
                          unit: 'trips',
                          caption: 'Scored 80+ in a row',
                        )
                      : _HeroStat(
                          kicker: 'Passenger trips',
                          value: p.passengerMarkedCount,
                          caption: 'Rides as a passenger',
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.section),
        if (own) ...[
          Reveal(
            delay: Reveal.stagger(2),
            child: _AllTimeSection(
              streaks: streaks!,
              passengerTrips: p.passengerMarkedCount,
            ),
          ),
          Reveal(delay: Reveal.stagger(3), child: const _BadgesSection()),
          Reveal(
            delay: Reveal.stagger(4),
            child: EditorialSection(
              kicker: 'More',
              child: Column(
                children: [
                  _DoorTile(
                    icon: Icons.query_stats,
                    title: 'All stats',
                    caption: 'Totals, records and fun facts.',
                    onTap: () => context.push(Routes.stats),
                  ),
                  const SizedBox(height: Space.md),
                  _DoorTile(
                    icon: Icons.auto_awesome_outlined,
                    title: 'Season Wrapped',
                    caption: 'Your season in a few cards.',
                    onTap: () => context.push(Routes.wrapped),
                  ),
                ],
              ),
            ),
          ),
          Reveal(
            delay: Reveal.stagger(5),
            child: EditorialSection(
              kicker: 'Account',
              child: Column(
                children: [
                  _DoorTile(
                    icon: Icons.alternate_email,
                    title: 'Handle',
                    caption: '@${p.handle}',
                    trailing: Icons.edit_outlined,
                    onTap: () => _editHandle(context, ref, p),
                  ),
                  const SizedBox(height: Space.md),
                  _DoorTile(
                    icon: Icons.badge_outlined,
                    title: 'Name',
                    caption: p.displayName,
                    trailing: Icons.edit_outlined,
                    onTap: () => _editDisplayName(context, ref, p),
                  ),
                  const SizedBox(height: Space.md),
                  _DoorTile(
                    icon: p.locationHidden
                        ? Icons.location_off_outlined
                        : Icons.location_on_outlined,
                    title: p.locationHidden
                        ? 'Nobody can see your location'
                        : 'Friends and circles can see your location',
                    caption: 'Change it in Settings',
                    onTap: () => context.push(Routes.settings),
                  ),
                ],
              ),
            ),
          ),
        ] else
          Reveal(
            delay: Reveal.stagger(2),
            child: EditorialSection(
              kicker: 'Location',
              child: Tile(
                child: Row(
                  children: [
                    Icon(
                      p.locationHidden
                          ? Icons.location_off_outlined
                          : Icons.location_on_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Space.lg),
                    Expanded(
                      child: Text(
                        p.locationHidden
                            ? 'Hiding their location'
                            : 'Shares location with friends',
                        style: context.body,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editHandle(
    BuildContext context,
    WidgetRef ref,
    Profile p,
  ) async {
    final value = await _promptSheet(
      context,
      title: 'Handle',
      initial: p.handle,
      hint: 'Lowercase letters, digits, underscores',
      validator: Profile.validateHandle,
    );
    if (value == null || !context.mounted) return;
    try {
      await ref.read(profileRepoProvider).updateHandle(p.id, value);
      if (context.mounted) Haptics.success();
    } on ProfileError catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) {
        _toast(context, friendlyError(e, doing: 'change the handle'));
      }
    }
  }

  Future<void> _editDisplayName(
    BuildContext context,
    WidgetRef ref,
    Profile p,
  ) async {
    final value = await _promptSheet(
      context,
      title: 'Name',
      initial: p.displayName,
      hint: 'What friends see',
      validator: Profile.validateDisplayName,
    );
    if (value == null || !context.mounted) return;
    try {
      await ref.read(profileRepoProvider).updateDisplayName(p.id, value);
      if (context.mounted) Haptics.success();
    } on ProfileError catch (e) {
      if (context.mounted) _toast(context, e.message);
    }
  }
}

/// Kicker, a number that counts up, optional unit, caption: the profile's
/// two hero figures.
class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.kicker,
    required this.value,
    required this.caption,
    this.unit,
  });

  final String kicker;
  final int? value;
  final String caption;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kicker(kicker),
        const SizedBox(height: Space.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (value == null)
              Text('–', style: context.displaySmall)
            else
              AnimatedNumber(value: value!, style: context.displaySmall),
            if (unit != null && value != null) ...[
              const SizedBox(width: Space.sm),
              Text(unit!, style: context.label),
            ],
          ],
        ),
        const SizedBox(height: Space.xs),
        Text(caption, style: context.caption),
      ],
    );
  }
}

/// Trips, average score and the phone-free streak. Streaks come from
/// [streaksProvider] only, the one source of truth.
class _AllTimeSection extends ConsumerWidget {
  const _AllTimeSection({required this.streaks, required this.passengerTrips});
  final Streaks streaks;
  final int passengerTrips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(driverStatsProvider(StatsWindow.allTime)).value;
    final totals = stats?.totals ?? Totals.empty;
    final avg = totals.averageScore;
    return EditorialSection(
      kicker: 'All time',
      child: StatGrid(
        columns: 2,
        children: [
          StatTile(value: '${totals.trips}', label: 'Trips'),
          StatTile(
            value: avg == null ? '–' : '${avg.round()}',
            label: 'Average score',
          ),
          StatTile(value: '${streaks.phoneFree}', label: 'Phone-free streak'),
          StatTile(value: '$passengerTrips', label: 'Passenger trips'),
        ],
      ),
    );
  }
}

/// Earned badges as tappable pills, newest first; each opens the badges
/// screen.
class _BadgesSection extends ConsumerWidget {
  const _BadgesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(myBadgesProvider).value;
    if (badges == null) return const SizedBox.shrink();
    final earned = badges.where((b) => b.earned).toList()
      ..sort((a, b) => b.awardedAt!.compareTo(a.awardedAt!));
    return EditorialSection(
      kicker: 'Badges',
      actionLabel: 'All badges',
      onAction: () => context.push(badgesPath),
      child: earned.isEmpty
          ? Text('None yet. Drive well.', style: context.bodyMuted)
          : Wrap(
              spacing: Space.sm,
              children: [
                for (final b in earned)
                  Tooltip(
                    message: b.def.description,
                    child: PressScale(
                      onTap: () => context.push(badgesPath),
                      // Vertical padding lifts the pill to a 48 px target.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.sm),
                        child: Pill(
                          b.def.name,
                          icon: Icons.military_tech_outlined,
                          tone: b.def.isShame
                              ? PillTone.danger
                              : PillTone.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Icon, title, caption, chevron: a row tile that goes somewhere.
class _DoorTile extends StatelessWidget {
  const _DoorTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
    this.trailing = Icons.chevron_right,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tile(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.lg,
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: Space.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.body.copyWith(fontWeight: FontWeight.w600),
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Text(caption, style: context.caption),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Icon(trailing, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Edit one field in a sheet (docs/12 §4: dialogs only for destructive
/// confirmations).
Future<String?> _promptSheet(
  BuildContext context, {
  required String title,
  required String initial,
  required String hint,
  required String? Function(String) validator,
}) {
  return showDrivalrySheet<String>(
    context,
    title: title,
    builder: (ctx) =>
        _EditField(initial: initial, hint: hint, validator: validator),
  );
}

class _EditField extends StatefulWidget {
  const _EditField({
    required this.initial,
    required this.hint,
    required this.validator,
  });

  final String initial;
  final String hint;
  final String? Function(String) validator;

  @override
  State<_EditField> createState() => _EditFieldState();
}

class _EditFieldState extends State<_EditField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    final err = widget.validator(v);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Space.lg),
          PressScale(
            child: PrimaryButton(label: 'Save', onPressed: _submit),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// The large avatar with the `avatar-<userId>` hero tag; on your own profile
/// a tap (or the camera badge) picks a new photo.
class _AvatarHero extends ConsumerWidget {
  const _AvatarHero({required this.profile, required this.own});

  final Profile profile;
  final bool own;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final name = profile.displayName.trim().isEmpty
        ? '@${profile.handle}'
        : profile.displayName;
    final avatar = Hero(
      tag: 'avatar-${profile.id}',
      child: UserAvatar(
        name: name,
        avatarPath: profile.avatarPath,
        size: AvatarSize.lg,
        isMe: own,
      ),
    );
    if (!own) return avatar;
    return Tooltip(
      message: 'Change photo',
      child: PressScale(
        onTap: () => _pick(context, ref),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: -Space.xs,
              bottom: -Space.xs,
              child: Container(
                padding: const EdgeInsets.all(Space.xs),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.photo_camera_outlined,
                  size: 16,
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
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
      if (context.mounted) {
        Haptics.success();
        _toast(context, 'Photo updated.');
      }
    } on ProfileError catch (e) {
      if (context.mounted) _toast(context, e.message);
    } catch (e) {
      if (context.mounted) {
        _toast(context, friendlyError(e, doing: 'change the photo'));
      }
    }
  }
}
