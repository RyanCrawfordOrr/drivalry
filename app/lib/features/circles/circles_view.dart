import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../data/repos/circles_repo.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/repos/places_repo.dart';
import '../../data/repos/presence_repo.dart';
import '../friends/widgets/live_badge.dart';
import '../friends/widgets/page_insets.dart';
import '../friends/widgets/tab_scroll_view.dart';
import 'checkin_sheet.dart';
import 'widgets/stacked_avatars.dart';

/// The Circles segment of the Friends tab (docs/01 §4.5; docs/12 §7): an
/// "I got home" hero when it applies, circles as tiles with stacked avatars
/// and a breathing "driving now" badge, the door to Places, and Join with
/// code as a text action. Creating a circle is the empty state's one button,
/// or the root's app-bar action once there are some. The root wraps this in
/// pull to refresh.
class CirclesView extends ConsumerWidget {
  const CirclesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final circles = ref.watch(myCirclesProvider);
    final membership = ref.watch(circleMembershipProvider);
    final presence = ref.watch(visiblePresenceProvider).value ?? const [];
    final places = ref.watch(placesProvider).value ?? const <Place>[];
    final friends =
        ref.watch(friendsSnapshotProvider).value?.friends ?? const [];
    final now = DateTime.now().toUtc();
    final drivingNow = {
      for (final p in presence)
        if (p.driving &&
            now.difference(p.updatedAt) < const Duration(hours: 24))
          p.userId,
    };
    final list = circles.value ?? const <Circle>[];
    final skeletons = circles.isLoading && list.isEmpty;
    // Check-in needs a saved place and someone to tell.
    final showCheckin =
        places.isNotEmpty && (list.isNotEmpty || friends.isNotEmpty);
    final scheme = Theme.of(context).colorScheme;

    return TabScrollView(
      slivers: [
        SliverPadding(
          // The empty state brings its own 48 on top.
          padding: EdgeInsets.only(
            top: !showCheckin && !skeletons && list.isEmpty ? 0 : Space.lg,
            bottom: pageBottomInset(context),
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showCheckin) ...[
                  Padding(
                    padding: Space.screen,
                    child: Reveal(
                      child: Tile(
                        key: const Key('checkin-button'),
                        tone: TileTone.raised,
                        onTap: () => showCheckinSheet(context),
                        child: Row(
                          children: [
                            Icon(
                              Icons.home_outlined,
                              size: 28,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: Space.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('I got home', style: context.title),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    'Tell your circles and friends in one tap.',
                                    style: context.caption,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.section),
                ],
                StateSwitcher(
                  child: skeletons
                      ? Column(
                          key: const ValueKey('skeleton'),
                          children: [
                            for (var i = 0; i < 3; i++)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(
                                  Space.gutter,
                                  0,
                                  Space.gutter,
                                  Space.md,
                                ),
                                child: SkeletonTile(),
                              ),
                          ],
                        )
                      : list.isEmpty
                      ? EmptyState(
                          key: const ValueKey('empty'),
                          kicker: 'Circles',
                          headline: 'No circles yet.',
                          body:
                              'Family, roommates, the crew: always on each '
                              'other\'s map.',
                          actionLabel: 'New circle',
                          onAction: () => context.push(Routes.createCircle),
                          secondaryLabel: 'Join with code',
                          onSecondary: () => joinCircleByCode(context),
                        )
                      : EditorialSection(
                          key: const ValueKey('list'),
                          kicker: 'Circles',
                          actionLabel: 'Join with code',
                          onAction: () => joinCircleByCode(context),
                          child: Column(
                            children: [
                              for (var i = 0; i < list.length; i++) ...[
                                Reveal(
                                  delay: Reveal.stagger(i),
                                  child: _CircleTile(
                                    circle: list[i],
                                    memberIds: membership[list[i].id],
                                    drivingNow: drivingNow,
                                  ),
                                ),
                                if (i < list.length - 1)
                                  const SizedBox(height: Space.md),
                              ],
                            ],
                          ),
                        ),
                ),
                EditorialSection(
                  kicker: 'Places',
                  child: Tile(
                    onTap: () => context.push(Routes.places),
                    child: Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: Space.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Places', style: context.title),
                              const SizedBox(height: Space.xs),
                              Text(
                                places.isEmpty
                                    ? 'Save Home to unlock check-ins and '
                                          'alerts.'
                                    : '${places.length} saved · alerts when '
                                          'friends arrive or leave',
                                style: context.caption,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleTile extends ConsumerWidget {
  const _CircleTile({
    required this.circle,
    required this.memberIds,
    required this.drivingNow,
  });

  final Circle circle;
  final Set<String>? memberIds;
  final Set<String> drivingNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members =
        ref.watch(circleMembersProvider(circle.id)).value ??
        const <CircleMember>[];
    final count = circle.memberCount == 0
        ? (memberIds?.length ?? members.length)
        : circle.memberCount;
    final driving = memberIds == null
        ? 0
        : memberIds!.where(drivingNow.contains).length;
    final pills = <Widget>[
      if (driving > 0) LiveBadge('$driving driving now'),
      if (circle.myHiding)
        const Pill(
          'Hiding',
          icon: Icons.visibility_off_outlined,
          compact: true,
        ),
    ];
    return Tile(
      onTap: () => context.push(Routes.circle(circle.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StackedAvatars(
                people: [
                  for (final m in members)
                    (name: m.name, avatarPath: m.avatarPath),
                ],
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      circle.name,
                      style: context.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      '$count member${count == 1 ? '' : 's'}',
                      style: context.caption,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
          if (pills.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: pills),
          ],
        ],
      ),
    );
  }
}

/// Asks for an invite code in a sheet and opens the join screen with it.
Future<void> joinCircleByCode(BuildContext context) async {
  final code = await showDrivalrySheet<String>(
    context,
    title: 'Join a circle',
    builder: (ctx) => const _JoinCodeForm(),
  );
  if (code == null || code.trim().isEmpty || !context.mounted) return;
  context.push(Routes.joinCircle(code.trim().toLowerCase()));
}

class _JoinCodeForm extends StatefulWidget {
  const _JoinCodeForm();

  @override
  State<_JoinCodeForm> createState() => _JoinCodeFormState();
}

class _JoinCodeFormState extends State<_JoinCodeForm> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: sheetBottomInset(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The code is on the invite a member shared with you.',
            style: context.bodyMuted,
          ),
          const SizedBox(height: Space.lg),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Invite code'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          const SizedBox(height: Space.lg),
          PressScale(
            child: PrimaryButton(
              label: 'Join',
              onPressed: () => Navigator.of(context).pop(_code.text),
            ),
          ),
        ],
      ),
    );
  }
}
