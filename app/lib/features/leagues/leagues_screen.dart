import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/badges/badges_providers.dart';
import '../../data/repos/duels_repo.dart';
import '../../data/repos/leagues_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';
import '../badges/badge_moments.dart';
import '../seasons/season_card.dart';
import 'duels/duel_moments.dart';
import 'global_league_card.dart';
import 'leagues_routes.dart';
import 'promotion_moments.dart';
import 'widgets/tier_pill.dart';

/// Weekly leagues with friends. Score and consistency climb the table; speed
/// never does. A large title that collapses, Duels and Badges as two tiles,
/// the season as the hero, the global league one tile, friend leagues under
/// a kicker. Everything arrives staggered (docs/12 §5b). Create or join
/// lives in the app bar, so nothing floats over the list; the empty state
/// repeats it as its one button.
class LeaguesScreen extends ConsumerWidget {
  const LeaguesScreen({super.key});

  static const _signInMessage =
      'Sign in to race your friends on how well you drive.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready =
        ref.watch(cloudConfiguredProvider) && ref.watch(isSignedInProvider);
    return Scaffold(
      body: BadgeMoments(
        child: ready
            ? const DuelMoments(child: PromotionMoments(child: _LeaguesBody()))
            : CustomScrollView(
                slivers: [
                  const _LargeTitle(),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: SignedInScope(
                      message: _signInMessage,
                      icon: Icons.emoji_events_outlined,
                      child: const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Leagues" as a large app bar title that collapses on scroll.
class _LargeTitle extends StatelessWidget {
  const _LargeTitle({this.actions});

  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) =>
      LargeTitleBar(title: 'Leagues', actions: actions);
}

class _LeaguesBody extends ConsumerWidget {
  const _LeaguesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final refresh = ref.watch(refreshMyLeaguesProvider);
    final leagues = ref.watch(myLeaguesProvider).value ?? const <League>[];
    // The global league has its own tile; these are the friend leagues.
    final friendLeagues = [
      for (final l in leagues)
        if (!l.isGlobal) l,
    ];
    // Opening the tab runs the week-badge pass and pulls the duel list once;
    // the tiles below follow the caches.
    ref.watch(leagueWeekBadgesProvider);
    ref.watch(refreshMyDuelsProvider);

    return RefreshIndicator(
      edgeOffset: 120,
      onRefresh: () => ref.refresh(refreshMyLeaguesProvider.future),
      child: CustomScrollView(
        slivers: [
          _LargeTitle(
            actions: [
              IconButton(
                tooltip: 'New league',
                icon: const Icon(Icons.add),
                onPressed: () => showAddLeagueSheet(context, ref),
              ),
            ],
          ),
          SliverPadding(
            // The last tile clears the navigation bar or home indicator.
            padding: EdgeInsets.only(
              top: Space.lg,
              bottom: Space.xl + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.list(
              children: [
                if (refresh.hasError)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      0,
                      Space.gutter,
                      Space.md,
                    ),
                    child: Text(
                      'Showing the last tables we saw. Pull to retry.',
                      style: context.caption.copyWith(color: scheme.error),
                    ),
                  ),
                const Reveal(
                  child: Padding(padding: Space.screen, child: _HubTiles()),
                ),
                const SizedBox(height: Space.xl),
                Reveal(
                  delay: Reveal.stagger(1),
                  child: const Padding(
                    padding: Space.screen,
                    child: SeasonCard(),
                  ),
                ),
                const SizedBox(height: Space.md),
                Reveal(
                  delay: Reveal.stagger(2),
                  child: const Padding(
                    padding: Space.screen,
                    child: GlobalLeagueCard(),
                  ),
                ),
                const SizedBox(height: Space.section),
                if (friendLeagues.isEmpty && !refresh.isLoading)
                  Reveal(
                    delay: Reveal.stagger(3),
                    child: EmptyState(
                      kicker: 'Friend leagues',
                      headline: 'No friend leagues yet.',
                      body: 'Race your friends on how well you drive.',
                      actionLabel: 'Create or join',
                      onAction: () => showAddLeagueSheet(context, ref),
                    ),
                  )
                else
                  EditorialSection(
                    kicker: 'Friend leagues',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: friendLeagues.isEmpty
                          ? const [
                              SkeletonTile(height: 84),
                              SizedBox(height: Space.md),
                              SkeletonTile(height: 84),
                            ]
                          : [
                              for (
                                var i = 0;
                                i < friendLeagues.length;
                                i++
                              ) ...[
                                if (i > 0) const SizedBox(height: Space.md),
                                Reveal(
                                  delay: Reveal.stagger(3 + i),
                                  child: _LeagueTile(league: friendLeagues[i]),
                                ),
                              ],
                            ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Create a league or join one with a code.
Future<void> showAddLeagueSheet(BuildContext context, WidgetRef ref) {
  return showDrivalrySheet<void>(
    context,
    title: 'New league',
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetRow(
          icon: Icons.add_circle_outline,
          title: 'Create a league',
          line: 'Up to 30 friends, Monday to Sunday',
          onTap: () {
            Navigator.pop(ctx);
            context.push(Routes.createLeague);
          },
        ),
        const SizedBox(height: Space.md),
        _SheetRow(
          icon: Icons.key_outlined,
          title: 'Join with a code',
          line: 'Paste the code a friend sent you',
          onTap: () {
            Navigator.pop(ctx);
            joinLeagueByCode(context, ref);
          },
        ),
      ],
    ),
  );
}

/// Asks for an invite code in a sheet, joins, and opens the league.
///
/// The field's controller lives inside [TextControllers], so it is still
/// there while the sheet animates out after the pop.
Future<void> joinLeagueByCode(BuildContext context, WidgetRef ref) async {
  final code = await showDrivalrySheet<String>(
    context,
    title: 'Join a league',
    builder: (_) => TextControllers(
      builder: (ctx, c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
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
  try {
    final id = await ref.read(leaguesRepoProvider).joinByCode(code);
    if (context.mounted) context.push(Routes.league(id));
  } on LeagueJoinException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.title,
    required this.line,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tile(
    onTap: onTap,
    padding: const EdgeInsets.all(Space.lg),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: Space.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.title),
              Text(line, style: context.caption),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Duels and Badges as two tiles: icon, title, one-line status, a count.
class _HubTiles extends ConsumerWidget {
  const _HubTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final duels = ref.watch(myDuelsProvider).value ?? const <Duel>[];
    final pending = ref.watch(pendingDuelCountProvider);
    final running = duels.where((d) => d.isActive).length;
    final badges = ref.watch(myBadgesProvider).value;
    final regular = badges?.where((b) => !b.def.isShame).toList();
    final earned = regular?.where((b) => b.earned).length ?? 0;
    final duelLine = pending > 0
        ? (pending == 1
              ? 'One challenge to answer'
              : '$pending challenges to answer')
        : running > 0
        ? (running == 1 ? 'One duel running' : '$running duels running')
        : 'Challenge a friend';
    final badgeLine = regular == null
        ? 'Streaks, not speed'
        : '$earned of ${regular.length} badges earned';
    // The status line may take two lines at 360 px; both tiles stay the
    // same height.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _HubTile(
              icon: Icons.bolt_outlined,
              title: 'Duels',
              line: duelLine,
              count: pending,
              live: running > 0,
              onTap: () => context.push(duelsPath),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: _HubTile(
              icon: Icons.military_tech_outlined,
              title: 'Badges',
              line: badgeLine,
              onTap: () => context.push(badgesPath),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.line,
    required this.onTap,
    this.count = 0,
    this.live = false,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onTap;
  final int count;

  /// Something is running right now: the tile breathes.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tile(
      onTap: onTap,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: scheme.primary),
              const Spacer(),
              if (count > 0)
                Pill('$count', tone: PillTone.primary, compact: true)
              else if (live)
                PulsingDot(color: scheme.primary, size: 8),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(title, style: context.title),
          const SizedBox(height: 2),
          Text(
            line,
            style: context.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _LeagueTile extends ConsumerWidget {
  const _LeagueTile({required this.league});
  final League league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(leagueCurrentWeekProvider(league.id)).value;
    final me = ref.watch(currentUserIdProvider);
    final mine = me == null ? null : week?.rowFor(me);
    final faces = [
      for (final r in (week?.rows ?? const <Standing>[]).take(3))
        r.displayName.isNotEmpty ? r.displayName : r.handle,
    ];
    final line = [
      '${league.memberCount} member${league.memberCount == 1 ? '' : 's'}',
      league.myTier.label,
      if (league.myHiding) 'hiding',
    ].join(' · ');
    return Tile(
      onTap: () => context.push(Routes.league(league.id)),
      child: Row(
        children: [
          _StackedAvatars(
            names: faces.isEmpty ? [league.name] : faces,
            color: tierColor(league.myTier, Theme.of(context).colorScheme),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  league.name,
                  style: context.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  style: context.caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (mine != null) ...[
            const SizedBox(width: Space.sm),
            Pill('#${mine.rank}', tone: PillTone.primary, compact: true),
          ],
        ],
      ),
    );
  }
}

/// Up to three member avatars, overlapping, on the tile's own colour.
class _StackedAvatars extends StatelessWidget {
  const _StackedAvatars({required this.names, required this.color});
  final List<String> names;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const step = 24.0;
    final bg = Theme.of(context).colorScheme.surfaceContainerLow;
    return SizedBox(
      width: 44 + step * (names.length - 1),
      height: 44,
      child: Stack(
        children: [
          for (var i = 0; i < names.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                child: Avatar(name: names[i], color: i == 0 ? color : null),
              ),
            ),
        ],
      ),
    );
  }
}
