import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/circles_repo.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/presence_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/relative_time.dart';
import '../../widgets/signed_in_scope.dart';
import '../friends/widgets/live_badge.dart';
import '../friends/widgets/page_insets.dart';
import '../friends/widgets/person_row.dart';
import '../friends/widgets/quiet_error_tile.dart';
import 'checkin_sheet.dart';
import 'circle_invite_sheet.dart';

/// One circle: the hide switch as a tile, check-in, then members as rows
/// with where they are. Invite in the app bar, leave in the overflow.
class CircleScreen extends ConsumerWidget {
  const CircleScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(circlesSyncProvider);
    final circle = ref.watch(circleProvider(circleId));
    final members = ref.watch(circleMembersProvider(circleId));
    final presence = ref.watch(visiblePresenceProvider).value ?? const [];
    final me = ref.watch(currentUserIdProvider);
    final byUser = {for (final p in presence) p.userId: p};
    final now = DateTime.now().toUtc();
    final repo = ref.read(circlesRepoProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(circle?.name ?? 'Circle'),
        actions: [
          if (circle != null)
            IconButton(
              tooltip: 'Invite',
              onPressed: () => showCircleInviteSheet(context, circle),
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
          if (circle != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                if (v == 'leave') await _leave(context, ref, circle);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'leave', child: Text('Leave circle')),
              ],
            ),
        ],
      ),
      body: SignedInScope(
        message: 'Sign in to see this circle.',
        icon: Icons.groups_outlined,
        child: circle == null
            ? const EmptyState(
                kicker: 'Circle',
                headline: 'Not in this circle.',
                body: 'A member can invite you back.',
              )
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(circleMembersProvider(circleId));
                  await ref.read(myCirclesProvider.notifier).refresh();
                },
                child: ListView(
                  padding: EdgeInsets.only(
                    top: Space.lg,
                    bottom: pageBottomInset(context),
                  ),
                  children: [
                    Padding(
                      padding: Space.screen,
                      child: Tile(
                        key: const Key('circle-hiding'),
                        child: Row(
                          children: [
                            Icon(
                              circle.myHiding
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: Space.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hide from this circle',
                                    style: context.body.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    'They can see that you are hiding.',
                                    style: context.caption,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            Switch(
                              value: circle.myHiding,
                              onChanged: (v) {
                                Haptics.select();
                                repo.setHiding(circle.id, v);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Padding(
                      padding: Space.screen,
                      child: Tile(
                        onTap: () => showCheckinSheet(context),
                        child: Row(
                          children: [
                            Icon(Icons.home_outlined, color: scheme.primary),
                            const SizedBox(width: Space.lg),
                            Expanded(
                              child: Text(
                                'I got home',
                                style: context.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.section),
                    EditorialSection(
                      kicker: 'Members',
                      child: Column(
                        children: [
                          if (members.isLoading &&
                              (members.value?.isEmpty ?? true))
                            for (var i = 0; i < 3; i++)
                              const Padding(
                                padding: EdgeInsets.only(bottom: Space.md),
                                child: SkeletonTile(height: 56),
                              ),
                          for (final (i, m)
                              in (members.value ?? const <CircleMember>[])
                                  .indexed)
                            Reveal(
                              delay: Reveal.stagger(i),
                              child: _MemberRow(
                                member: m,
                                presence: byUser[m.userId],
                                isMe: m.userId == me,
                                now: now,
                              ),
                            ),
                          if (members.hasError)
                            QuietErrorTile(
                              message: friendlyError(
                                members.error!,
                                doing: 'load the members',
                              ),
                              onRetry: () => ref.invalidate(
                                circleMembersProvider(circleId),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Circle c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Leave ${c.name}?'),
        content: const Text(
          'You stop seeing the circle and they stop seeing you. A member can '
          'invite you back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(circlesRepoProvider).leave(c.id);
    if (context.mounted) context.go(Routes.friends);
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.presence,
    required this.isMe,
    required this.now,
  });

  final CircleMember member;
  final PresenceRow? presence;
  final bool isMe;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = presence;
    final stale =
        p != null && now.difference(p.updatedAt) > const Duration(hours: 24);
    final driving = p != null && p.driving && !stale;
    final String where;
    if (member.hiding) {
      where = 'Hiding';
    } else if (p == null) {
      where = isMe ? 'You' : 'No location yet';
    } else if (driving) {
      where = 'Driving now';
    } else {
      where = 'Parked ${relativeTime(p.updatedAt, now)}';
    }
    final Widget? badge;
    if (member.hiding) {
      badge = const Pill(
        'Hiding',
        icon: Icons.visibility_off_outlined,
        compact: true,
      );
    } else if (driving) {
      badge = const LiveBadge('Driving');
    } else {
      badge = null;
    }
    return PersonRow(
      name: isMe ? '${member.name} (you)' : member.name,
      avatarName: member.name,
      avatarPath: member.avatarPath,
      caption: '@${member.handle} · $where',
      highlighted: driving,
      isMe: isMe,
      heroTag: 'avatar-${member.userId}',
      badge: badge,
      onTap: () => context.push(Routes.userProfile(member.userId)),
    );
  }
}
