import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/deep_links.dart';
import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/convoy/eta.dart';
import '../../data/repos/convoy_repo.dart';
import '../../data/repos/convoy_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/relative_time.dart';
import '../../widgets/signed_in_scope.dart';
import 'live/convoy_live.dart';
import 'widgets/convoy_invite_sheet.dart';
import 'widgets/convoy_ui.dart';
import 'widgets/member_avatar.dart';
import 'widgets/talk_button.dart';

/// The Convoy tab (docs/12 §7): the convoy I am in as a hero, Talk as the
/// one in-car action, five doors, the rest under More; past trips open
/// their recap.
class ConvoyScreen extends ConsumerWidget {
  const ConvoyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(convoySyncProvider);
    ref.watch(deepLinksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convoy'),
        actions: [
          IconButton(
            tooltip: 'Join with a code',
            onPressed: () => showJoinCodeSheet(context),
            icon: const Icon(Icons.key_outlined),
          ),
          IconButton(
            key: const Key('new-convoy'),
            tooltip: 'Start a convoy',
            onPressed: () => context.push(Routes.createConvoy),
            icon: const Icon(Icons.add_road_outlined),
          ),
        ],
      ),
      body: const SignedInScope(
        message: 'Sign in to drive with friends in a convoy.',
        icon: Icons.route_outlined,
        child: ConvoyHubBody(),
      ),
    );
  }
}

/// The hub without the sign-in gate, so it can be tested with overrides.
class ConvoyHubBody extends ConsumerWidget {
  const ConvoyHubBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convoys = ref.watch(myConvoysProvider);
    final list = convoys.value ?? const <Convoy>[];
    final hero = ref.watch(activeConvoyProvider);
    final others = [
      for (final c in list)
        if (c.status != ConvoyStatus.ended && c.id != hero?.id) c,
    ];
    final past = [
      for (final c in list)
        if (c.status == ConvoyStatus.ended) c,
    ];
    final now = DateTime.now().toUtc();

    return RefreshIndicator(
      onRefresh: () => ref.read(myConvoysProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.only(top: Space.sm, bottom: Space.xxxl),
        children: [
          if (convoys.isLoading && list.isEmpty)
            const Padding(
              padding: Space.screen,
              child: Column(
                children: [
                  SkeletonTile(height: 160),
                  SizedBox(height: Space.md),
                  SkeletonTile(height: Sizes.drivingTouch),
                ],
              ),
            ),
          if (!convoys.isLoading && hero == null)
            EmptyState(
              kicker: 'Convoy',
              headline: 'Road trips, together.',
              body: 'One map, a vote on stops and a radio between the cars.',
              actionLabel: 'Start a convoy',
              onAction: () => context.push(Routes.createConvoy),
              secondaryLabel: 'Join with a code',
              onSecondary: () => showJoinCodeSheet(context),
            ),
          if (hero != null) _ActiveHub(convoy: hero),
          if (others.isNotEmpty)
            EditorialSection(
              kicker: 'Other convoys',
              child: Column(
                children: [
                  for (final c in others) _ConvoyRow(convoy: c, now: now),
                ],
              ),
            ),
          if (past.isNotEmpty)
            EditorialSection(
              kicker: 'Past trips',
              child: Column(
                children: [
                  for (final c in past) _ConvoyRow(convoy: c, now: now),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Asks for an invite code in a sheet and opens the join screen.
Future<void> showJoinCodeSheet(BuildContext context) async {
  final code = await showDrivalrySheet<String>(
    context,
    title: 'Join a convoy',
    builder: (_) => TextControllers(
      builder: (ctx, c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('join-code'),
              controller: c.first,
              autofocus: true,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Invite code'),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
            const SizedBox(height: Space.lg),
            PrimaryButton(
              label: 'Join',
              onPressed: () => Navigator.of(ctx).pop(c.first.text),
            ),
          ],
        ),
      ),
    ),
  );
  if (code == null || code.trim().isEmpty || !context.mounted) return;
  context.push(Routes.joinConvoy(code.trim().toLowerCase()));
}

class _ActiveHub extends ConsumerWidget {
  const _ActiveHub({required this.convoy});
  final Convoy convoy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = convoy.id;
    final amLeader = ref.watch(amConvoyLeaderProvider(id));
    final members = ref.watch(convoyMembersProvider(id)).value ?? const [];
    final stops = ref.watch(convoyStopsProvider(id)).value ?? const [];
    final present = [
      for (final m in members)
        if (m.isPresent) m,
    ];
    final accepted = stops.where((s) => s.status == StopStatus.accepted);
    final proposed = stops.where((s) => s.status == StopStatus.proposed);
    final stopsCaption = accepted.isNotEmpty
        ? 'Next: ${accepted.first.name}'
        : proposed.isEmpty
        ? 'Nothing proposed yet'
        : '${proposed.length} ${proposed.length == 1 ? 'stop' : 'stops'} '
              'proposed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: Space.screen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Reveal(
                child: _HeroTile(convoy: convoy, members: present),
              ),
              const SizedBox(height: Space.lg),
              if (convoy.isActive) TalkButton(convoyId: id),
              if (convoy.status == ConvoyStatus.planning) ...[
                if (amLeader)
                  PrimaryButton(
                    key: const Key('start-convoy'),
                    label: 'Start trip',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => ref
                        .read(convoyRepoProvider)
                        .setStatus(id, ConvoyStatus.active),
                  )
                else
                  PrimaryButton(
                    label: 'Invite cars',
                    icon: Icons.person_add_alt_1_outlined,
                    onPressed: () => showConvoyInviteSheet(context, convoy),
                  ),
                if (amLeader) ...[
                  const SizedBox(height: Space.sm),
                  SecondaryButton(
                    label: 'Invite cars',
                    icon: Icons.person_add_alt_1_outlined,
                    onPressed: () => showConvoyInviteSheet(context, convoy),
                  ),
                ],
              ],
              const SizedBox(height: Space.xl),
              _FeatureGrid(
                tiles: [
                  _Feature(
                    Icons.map_outlined,
                    'Map',
                    '${present.length} of ${convoy.maxCars} cars',
                    Routes.convoyDetail(id),
                  ),
                  _Feature(
                    Icons.local_gas_station_outlined,
                    'Stops',
                    stopsCaption,
                    Routes.convoyStops(id),
                  ),
                  _Feature(
                    Icons.chat_bubble_outline,
                    'Chat',
                    'Voice notes and text',
                    Routes.convoyChat(id),
                  ),
                  _Feature(
                    Icons.music_note_outlined,
                    'Music',
                    'Same song in every car',
                    Routes.convoyMusic(id),
                  ),
                  _Feature(
                    Icons.sports_esports_outlined,
                    'Games',
                    'Passenger games',
                    Routes.convoyGames(id),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.section),
        EditorialSection(
          kicker: 'More',
          child: Column(
            children: [
              ConvoyRow(
                leading: const Icon(Icons.photo_library_outlined),
                title: 'Album',
                caption: 'Photos for the recap',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.convoyAlbum(id)),
              ),
              ConvoyRow(
                leading: const Icon(Icons.receipt_long_outlined),
                title: 'Expenses',
                caption: 'Gas, tolls and food, split',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.convoyExpenses(id)),
              ),
              ConvoyRow(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: 'Recap',
                caption: 'The trip so far',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.convoyRecap(id)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroTile extends ConsumerWidget {
  const _HeroTile({required this.convoy, required this.members});
  final Convoy convoy;
  final List<ConvoyMember> members;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final me = ref.watch(currentUserIdProvider);
    final etas =
        ref.watch(convoyEtasProvider(convoy.id)).value ??
        const <String, EtaInfo>{};
    final eta = me == null ? null : etas[me] ?? etas[convoy.createdBy];
    final dest = convoy.destination;
    final live = convoy.isActive;
    final fg = live ? scheme.onPrimaryContainer : null;
    final caption = [
      if (dest == null) 'No destination yet' else 'to ${dest.name}',
      if (eta != null) 'ETA ${eta.estimated ? '~' : ''}${eta.label}',
    ].join(' · ');
    final cars = '${members.length} ${members.length == 1 ? 'car' : 'cars'}';

    return Tile(
      tone: live ? TileTone.primary : TileTone.raised,
      onTap: () => context.push(Routes.convoyDetail(convoy.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  convoy.name,
                  style: context.headline.copyWith(color: fg),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.md),
              ConvoyStatusBadge(status: convoy.status, compact: true),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            caption,
            style: context.caption.copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              StackedAvatars(members: members, me: me),
              const SizedBox(width: Space.md),
              Text(cars, style: context.label.copyWith(color: fg)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Feature {
  const _Feature(this.icon, this.title, this.caption, this.route);
  final IconData icon;
  final String title;
  final String caption;
  final String route;
}

/// Large square tiles in two columns; an odd last tile keeps its size.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({required this.tiles});
  final List<_Feature> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(
              child: Reveal(
                delay: Reveal.stagger(i),
                child: _FeatureTile(tiles[i]),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : Reveal(
                      delay: Reveal.stagger(i + 1),
                      child: _FeatureTile(right),
                    ),
            ),
          ],
        ),
      );
      if (i + 2 < tiles.length) rows.add(const SizedBox(height: Space.md));
    }
    return Column(children: rows);
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile(this.feature);
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: Tile(
        key: Key('hub-${feature.title.toLowerCase()}'),
        padding: const EdgeInsets.all(Space.lg),
        onTap: () => context.push(feature.route),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(feature.icon, size: 28, color: scheme.primary),
            const Spacer(),
            Text(feature.title, style: context.title),
            const SizedBox(height: Space.xs),
            Text(
              feature.caption,
              style: context.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConvoyRow extends StatelessWidget {
  const _ConvoyRow({required this.convoy, required this.now});
  final Convoy convoy;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = convoy;
    final cars = '${c.memberCount} ${c.memberCount == 1 ? 'car' : 'cars'}';
    final when = c.isEnded
        ? 'Ended ${relativeTime(c.endedAt ?? c.createdAt, now)}'
        : 'Planning';
    final dest = c.destination?.name;
    return ConvoyRow(
      leading: Icon(
        c.isEnded ? Icons.flag_outlined : Icons.edit_road_outlined,
        size: 28,
      ),
      title: c.name,
      caption: dest == null ? '$when · $cars' : '$when · $cars · to $dest',
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        c.isEnded ? Routes.convoyRecap(c.id) : Routes.convoyDetail(c.id),
      ),
    );
  }
}
