import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/repos/challenges_repo.dart';
import '../../../data/supabase/supabase_providers.dart';
import 'new_challenge_sheet.dart';

/// The league's group challenge: progress while it runs, the result after,
/// and a way to start one. Sits above the standings on the league screen.
class ChallengeCard extends ConsumerWidget {
  const ChallengeCard({super.key, required this.leagueId});
  final String leagueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserIdProvider);
    final list = ref.watch(leagueChallengesProvider(leagueId));
    final challenges = list.value ?? const <GroupChallenge>[];
    GroupChallenge? active;
    for (final c in challenges) {
      if (c.isActive) active = c;
    }
    if (active != null) {
      final progress = ref
          .watch(challengeProgressProvider((leagueId, active.id)))
          .value;
      final a = active;
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ChallengeProgressView(
            challenge: a,
            progress: progress,
            onCancel: me != null && me == a.createdBy
                ? () => _cancel(context, ref, a)
                : null,
          ),
        ),
      );
    }
    final latest = challenges.isEmpty ? null : challenges.first;
    final recent =
        latest != null &&
        latest.finalizedAt != null &&
        DateTime.now().difference(latest.finalizedAt!).inDays <= 14;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (recent) ...[
              Text(latest.title, style: Theme.of(context).textTheme.titleSmall),
              Text(
                challengeResultLine(latest),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else
              Text(
                'A group challenge gives the whole league one goal for a '
                'week or two: clean trips, phone-free trips, average score, '
                'or everyone showing up.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final created = await showNewChallengeSheet(
                    context,
                    leagueId,
                  );
                  if (created != null) {
                    ref.invalidate(leagueChallengesProvider(leagueId));
                  }
                },
                icon: const Icon(Icons.flag_outlined),
                label: Text(
                  recent
                      ? 'Start another challenge'
                      : 'Start a group challenge',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    GroupChallenge c,
  ) async {
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
    ref.invalidate(leagueChallengesProvider(leagueId));
  }
}

/// Title, bar, numbers and the end date. Pure, so it renders offline and in
/// tests; [progress] null shows an empty bar.
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
    final theme = Theme.of(context);
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
            Icon(Icons.flag_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(challenge.title, style: theme.textTheme.titleSmall),
            ),
            if (onCancel != null)
              IconButton(
                tooltip: 'Call off',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: onCancel,
              ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: p?.fraction ?? 0,
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 6),
        Text(
          p == null ? 'Counting…' : challengeProgressLine(challenge, p),
          style: theme.textTheme.bodyMedium,
        ),
        Text(ends, style: theme.textTheme.bodySmall),
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
    return 'Missed: $shown of $needed.';
  }
  return 'Running';
}
