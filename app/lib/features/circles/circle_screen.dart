import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/circles_repo.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/presence_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/relative_time.dart';
import '../../widgets/signed_in_scope.dart';
import '../friends/widgets/user_avatar.dart';
import 'checkin_sheet.dart';
import 'circle_invite_sheet.dart';

/// One circle: members with where they are, my hiding switch, invite, leave.
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
    final theme = Theme.of(context);
    final repo = ref.read(circlesRepoProvider);

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
            ? const Center(child: Text('This circle is not in your list.'))
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(circleMembersProvider(circleId));
                  await ref.read(myCirclesProvider.notifier).refresh();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                  children: [
                    SwitchListTile(
                      key: const Key('circle-hiding'),
                      secondary: Icon(
                        circle.myHiding
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      title: const Text('Hide from this circle'),
                      subtitle: const Text(
                        'Everyone in this circle can see that you are hiding.',
                      ),
                      value: circle.myHiding,
                      onChanged: (v) => repo.setHiding(circle.id, v),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: FilledButton.tonalIcon(
                        onPressed: () => showCheckinSheet(context),
                        icon: const Icon(Icons.home_outlined),
                        label: const Text('I got home'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text(
                        'Members',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    if (members.isLoading && (members.value?.isEmpty ?? true))
                      const LinearProgressIndicator(minHeight: 2),
                    for (final m in members.value ?? const <CircleMember>[])
                      _MemberTile(
                        member: m,
                        presence: byUser[m.userId],
                        isMe: m.userId == me,
                        now: now,
                      ),
                    if (members.hasError)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not load members: ${members.error}',
                          style: theme.textTheme.bodySmall,
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

class _MemberTile extends StatelessWidget {
  const _MemberTile({
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
    final theme = Theme.of(context);
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
      where = 'Parked · ${relativeTime(p.updatedAt, now)}';
    }
    return ListTile(
      leading: UserAvatar(
        name: member.name,
        avatarPath: member.avatarPath,
        highlighted: driving,
      ),
      title: Text(isMe ? '${member.name} (you)' : member.name),
      subtitle: Text('@${member.handle} · $where'),
      trailing: member.hiding
          ? Chip(
              label: const Text('hiding'),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            )
          : null,
      onTap: () => context.push(Routes.userProfile(member.userId)),
    );
  }
}
