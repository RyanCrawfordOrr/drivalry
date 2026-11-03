import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/duels_repo.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../widgets/friendly_error.dart';
import '../../../widgets/signed_in_scope.dart';
import 'duel_card.dart';
import 'duel_moments.dart';
import 'new_duel_sheet.dart';

/// Head-to-head duels with friends (docs/02 §7, §12.1): four editorial
/// sections, one tile per duel, a won duel celebrated once.
class DuelsScreen extends ConsumerWidget {
  const DuelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready =
        ref.watch(cloudConfiguredProvider) && ref.watch(isSignedInProvider);
    final hasDuels =
        ready && (ref.watch(myDuelsProvider).value?.isNotEmpty ?? false);
    return Scaffold(
      appBar: AppBar(title: const Text('Duels')),
      // The empty state carries its own button; the FAB appears once there
      // is a list to float over.
      floatingActionButton: hasDuels
          ? FloatingActionButton.extended(
              onPressed: () => startDuel(context),
              icon: const Icon(Icons.bolt),
              label: const Text('Duel'),
            )
          : null,
      body: const SignedInScope(
        message: 'Sign in to duel your friends on how well you drive.',
        icon: Icons.bolt_outlined,
        child: DuelMoments(child: _DuelsBody()),
      ),
    );
  }
}

/// Opens the new-duel sheet and confirms the send.
Future<void> startDuel(BuildContext context) async {
  final duel = await showNewDuelSheet(context);
  if (duel != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Challenge sent to @${duel.opponent.handle}.')),
    );
  }
}

class _DuelsBody extends ConsumerWidget {
  const _DuelsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final refresh = ref.watch(refreshMyDuelsProvider);
    final duels = ref.watch(myDuelsProvider).value ?? const <Duel>[];
    final me = ref.watch(currentUserIdProvider);

    final incoming = duels
        .where((d) => d.isPending && d.opponent.userId == me)
        .toList();
    final outgoing = duels
        .where((d) => d.isPending && d.challenger.userId == me)
        .toList();
    final running = duels.where((d) => d.isActive).toList();
    final done = duels.where((d) => !d.isPending && !d.isActive).toList();

    return RefreshIndicator(
      onRefresh: () => ref.refresh(refreshMyDuelsProvider.future),
      child: ListView(
        padding: const EdgeInsets.only(top: Space.sm, bottom: 96),
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
                'Showing the last duels we saw. Pull to retry.',
                style: context.caption.copyWith(color: scheme.error),
              ),
            ),
          if (duels.isEmpty && !refresh.isLoading)
            EmptyState(
              kicker: 'Duels',
              headline: 'No duels yet.',
              body: 'Pick a friend and a week. The loser wears a badge.',
              actionLabel: 'Duel a friend',
              onAction: () => startDuel(context),
            )
          else if (duels.isEmpty)
            const Padding(
              padding: Space.screen,
              child: Column(
                children: [
                  SkeletonTile(height: 120),
                  SizedBox(height: Space.md),
                  SkeletonTile(height: 120),
                ],
              ),
            ),
          if (incoming.isNotEmpty)
            _Section(
              kicker: 'Challenges for you',
              children: [
                for (final d in incoming)
                  DuelCard(
                    duel: d,
                    me: me,
                    footer: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: Sizes.touch,
                            child: TextButton(
                              onPressed: () => _respond(context, ref, d, false),
                              child: const Text('Decline'),
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: SizedBox(
                            height: Sizes.touch,
                            child: FilledButton.tonal(
                              onPressed: () => _respond(context, ref, d, true),
                              child: const Text('Accept'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          if (running.isNotEmpty)
            _Section(
              kicker: 'Running',
              children: [for (final d in running) _LiveDuel(duel: d, me: me)],
            ),
          if (outgoing.isNotEmpty)
            _Section(
              kicker: 'Sent',
              children: [
                for (final d in outgoing)
                  DuelCard(
                    duel: d,
                    me: me,
                    footer: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _cancel(context, ref, d),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
              ],
            ),
          if (done.isNotEmpty)
            _Section(
              kicker: 'Finished',
              children: [
                for (final d in done)
                  DuelCard(
                    duel: d,
                    me: me,
                    board: d.isFinished
                        ? DuelScoreboard(
                            challenger: DuelValue(
                              value: d.challengerValue ?? 0,
                              trips: d.challengerTrips ?? 0,
                            ),
                            opponent: DuelValue(
                              value: d.opponentValue ?? 0,
                              trips: d.opponentTrips ?? 0,
                            ),
                          )
                        : null,
                    footer:
                        d.isFinished &&
                            d.winnerId == me &&
                            d.loserBadgeId == null
                        ? _BadgePicker(duel: d)
                        : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _respond(
    BuildContext context,
    WidgetRef ref,
    Duel duel,
    bool accept,
  ) async {
    try {
      await ref.read(duelsRepoProvider).respond(duel.id, accept: accept);
      ref.invalidate(refreshMyDuelsProvider);
    } on DuelException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, Duel duel) async {
    try {
      await ref.read(duelsRepoProvider).cancel(duel.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, doing: 'cancel the duel'))),
        );
      }
    }
  }
}

/// Kicker plus tiles twelve apart.
class _Section extends StatelessWidget {
  const _Section({required this.kicker, required this.children});
  final String kicker;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => EditorialSection(
    kicker: kicker,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.md),
          children[i],
        ],
      ],
    ),
  );
}

/// A running duel with its live scoreboard.
class _LiveDuel extends ConsumerWidget {
  const _LiveDuel({required this.duel, required this.me});
  final Duel duel;
  final String? me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(duelScoreboardProvider(duel.id)).value;
    return DuelCard(duel: duel, me: me, board: board);
  }
}

/// The winner's pick from the fixed list (docs/02 §7).
class _BadgePicker extends ConsumerStatefulWidget {
  const _BadgePicker({required this.duel});
  final Duel duel;

  @override
  ConsumerState<_BadgePicker> createState() => _BadgePickerState();
}

class _BadgePickerState extends ConsumerState<_BadgePicker> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final loser = widget.duel.other(widget.duel.winnerId!).handle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pick what @$loser wears for a week', style: context.caption),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final id in duelLoserBadges)
              ActionChip(
                label: Text(duelBadgeName(id)),
                onPressed: _busy ? null : () => _pick(id),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pick(String id) async {
    setState(() => _busy = true);
    try {
      await ref.read(duelsRepoProvider).pickBadge(widget.duel.id, id);
    } on DuelException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
