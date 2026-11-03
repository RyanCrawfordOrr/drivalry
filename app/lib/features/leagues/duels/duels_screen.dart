import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repos/duels_repo.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../widgets/signed_in_scope.dart';
import 'duel_card.dart';
import 'new_duel_sheet.dart';

/// Head-to-head duels with friends (docs/02 §7, §12.1).
class DuelsScreen extends StatelessWidget {
  const DuelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duels')),
      body: const SignedInScope(
        message: 'Sign in to duel your friends on how well you drive.',
        icon: Icons.bolt_outlined,
        child: _DuelsBody(),
      ),
    );
  }
}

class _DuelsBody extends ConsumerWidget {
  const _DuelsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final duel = await showNewDuelSheet(context);
          if (duel != null && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Challenge sent to @${duel.opponent.handle}.'),
              ),
            );
          }
        },
        icon: const Icon(Icons.bolt),
        label: const Text('Duel'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(refreshMyDuelsProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (refresh.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Showing the last known duels. Pull to retry.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (duels.isEmpty && !refresh.isLoading)
              const _EmptyDuels()
            else if (duels.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (incoming.isNotEmpty) ...[
              _Header('Waiting for you'),
              for (final d in incoming)
                DuelCard(
                  duel: d,
                  me: me,
                  footer: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _respond(context, ref, d, false),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _respond(context, ref, d, true),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ),
            ],
            if (running.isNotEmpty) ...[
              _Header('Running'),
              for (final d in running) _LiveDuel(duel: d, me: me),
            ],
            if (outgoing.isNotEmpty) ...[
              _Header('Sent'),
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
            if (done.isNotEmpty) ...[
              _Header('Finished'),
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
                      d.isFinished && d.winnerId == me && d.loserBadgeId == null
                      ? _BadgePicker(duel: d)
                      : null,
                ),
            ],
          ],
        ),
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
          const SnackBar(content: Text('Could not cancel. Try again online.')),
        );
      }
    }
  }
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'You won. Pick the badge @${widget.duel.other(widget.duel.winnerId!).handle} '
          'wears for a week:',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            for (final id in duelLoserBadges)
              ActionChip(
                label: Text(duelBadgeName(id)),
                avatar: const Icon(Icons.sentiment_dissatisfied_outlined),
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

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _EmptyDuels extends StatelessWidget {
  const _EmptyDuels();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        children: [
          Icon(Icons.bolt_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('No duels yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Challenge a friend to a week on XP, average Drive Score or '
            'phone-free trips. The loser wears Sunday Driver, Lead Foot or '
            'Butterfingers for seven days. The winner picks.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
