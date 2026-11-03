import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/challenges_repo.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../badges/moment_ledger.dart';
import '../widgets/live_numbers.dart';
import 'new_challenge_sheet.dart';

/// The league's group challenge as one tile above the standings: progress
/// while it runs, the result after, and a way to start one. A met challenge
/// gets the celebration moment once (docs/12 §5).
class ChallengeCard extends ConsumerStatefulWidget {
  const ChallengeCard({super.key, required this.leagueId});
  final String leagueId;

  @override
  ConsumerState<ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends ConsumerState<ChallengeCard> {
  ProviderSubscription<AsyncValue<List<GroupChallenge>>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual(leagueChallengesProvider(widget.leagueId), (
      _,
      next,
    ) {
      final list = next.value;
      if (list != null) _celebrateMet(list);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  Future<void> _celebrateMet(List<GroupChallenge> list) async {
    final now = DateTime.now();
    for (final c in list) {
      if (!c.succeeded ||
          !recentlyAt(c.finalizedAt, now, challengeMomentWindow)) {
        continue;
      }
      if (!mounted) return;
      await ref
          .read(momentLedgerProvider)
          .celebrateOnce(
            context,
            id: 'challenge:${c.id}',
            title: 'Challenge met',
            verdict: c.title,
            badges: [c.goal.badgeName],
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserIdProvider);
    final list = ref.watch(leagueChallengesProvider(widget.leagueId));
    final challenges = list.value ?? const <GroupChallenge>[];
    GroupChallenge? active;
    for (final c in challenges) {
      if (c.isActive) active = c;
    }
    if (active != null) {
      final progress = ref
          .watch(challengeProgressProvider((widget.leagueId, active.id)))
          .value;
      final a = active;
      return Tile(
        child: ChallengeProgressView(
          challenge: a,
          progress: progress,
          onCancel: me != null && me == a.createdBy ? () => _cancel(a) : null,
        ),
      );
    }
    final latest = challenges.isEmpty ? null : challenges.first;
    final recent =
        latest != null &&
        latest.finalizedAt != null &&
        DateTime.now().difference(latest.finalizedAt!).inDays <= 14;
    return Tile(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.md,
        Space.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.flag_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: recent
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(latest.title, style: context.body),
                      Text(challengeResultLine(latest), style: context.caption),
                    ],
                  )
                : Text(
                    'Set one goal for the whole league.',
                    style: context.body,
                  ),
          ),
          const SizedBox(width: Space.sm),
          TextButton(
            onPressed: () async {
              final created = await showNewChallengeSheet(
                context,
                widget.leagueId,
              );
              if (created != null) {
                ref.invalidate(leagueChallengesProvider(widget.leagueId));
              }
            },
            child: Text(recent ? 'Another' : 'Start'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(GroupChallenge c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Call off this challenge?'),
        content: const Text(
          'Nobody gets the badge; the league can start another.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Call off'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(challengesRepoProvider).cancel(c);
    ref.invalidate(leagueChallengesProvider(widget.leagueId));
  }
}

/// How long after a challenge is met it still earns the moment.
const Duration challengeMomentWindow = Duration(days: 14);

/// Title, thin bar, count and the end date. Pure, so it renders offline and
/// in tests; [progress] null shows an empty bar.
class ChallengeProgressView extends StatelessWidget {
  const ChallengeProgressView({
    super.key,
    required this.challenge,
    required this.progress,
    this.now,
    this.onCancel,
  });

  final GroupChallenge challenge;
  final ChallengeProgress? progress;
  final DateTime? now;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = now ?? DateTime.now();
    final p = progress;
    final daysLeft = challenge.endsAt.difference(n).inDays;
    final ends = challenge.isActive
        ? 'Ends ${DateFormat.MMMEd().format(challenge.endsAt)}'
              '${daysLeft > 0 ? ' · $daysLeft day${daysLeft == 1 ? '' : 's'} left' : ''}'
        : challengeResultLine(challenge);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.flag_outlined, size: 20, color: scheme.primary),
            const SizedBox(width: Space.md),
            Expanded(child: Text(challenge.title, style: context.body)),
            if (onCancel != null)
              IconButton(
                tooltip: 'Call off',
                icon: const Icon(Icons.close),
                onPressed: onCancel,
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        GrowBar(fraction: p?.fraction ?? 0),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                p == null ? 'Counting…' : challengeProgressLine(challenge, p),
                style: context.caption,
              ),
            ),
            Text(ends, style: context.caption),
          ],
        ),
      ],
    );
  }
}

/// `17 of 25 trips`, `Averaging 86.2, target 85`, `4 of 6 members have 3 trips`.
String challengeProgressLine(GroupChallenge c, ChallengeProgress p) {
  switch (c.goal) {
    case ChallengeGoal.cleanTrips:
    case ChallengeGoal.phoneFree:
      return '${p.value.round()} of ${p.needed} ${c.goal.unit}';
    case ChallengeGoal.scoreAvg:
      return 'Averaging ${p.value.toStringAsFixed(1)}, target ${p.needed}';
    case ChallengeGoal.everyoneDrives:
      return '${p.value.round()} of ${p.needed} members have ${c.target} '
          'trip${c.target == 1 ? '' : 's'}';
  }
}

/// After the window closes: met or missed, with the badge.
String challengeResultLine(GroupChallenge c) {
  if (c.succeeded) return 'Met! Everyone earned ${c.goal.badgeName}.';
  if (c.failed) {
    final v = c.value ?? 0;
    final shown = c.goal == ChallengeGoal.scoreAvg
        ? v.toStringAsFixed(1)
        : v.round().toString();
    final needed = c.goal == ChallengeGoal.everyoneDrives
        ? '${c.perMember.length} members'
        : '${c.target} ${c.goal.unit}';
    return 'Not met. The league reached $shown of $needed.';
  }
  return 'Running';
}
