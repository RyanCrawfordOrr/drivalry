import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repos/duels_repo.dart';
import '../../../data/repos/friends_repo.dart';
import '../../../data/repos/friends_sync.dart';
import '../../friends/widgets/user_avatar.dart';

/// Pick a friend and a metric; the challenge goes out through the outbox.
/// Resolves with the new duel, or null when dismissed.
Future<Duel?> showNewDuelSheet(BuildContext context) =>
    showModalBottomSheet<Duel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const NewDuelSheet(),
    );

class NewDuelSheet extends ConsumerStatefulWidget {
  const NewDuelSheet({super.key});

  @override
  ConsumerState<NewDuelSheet> createState() => _NewDuelSheetState();
}

class _NewDuelSheetState extends ConsumerState<NewDuelSheet> {
  FriendProfile? _friend;
  DuelMetric _metric = DuelMetric.xp;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friends =
        ref.watch(friendsSnapshotProvider).value?.friends ??
        const <FriendProfile>[];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Duel a friend', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Seven days from the moment they accept. The loser wears a badge '
              'the winner picks for a week. Never about speed.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('Who', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            if (friends.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Add a friend first; duels are between friends.'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in friends)
                      ListTile(
                        dense: true,
                        leading: UserAvatar(
                          name: f.name,
                          avatarPath: f.avatarPath,
                          radius: 16,
                        ),
                        title: Text('@${f.handle}'),
                        subtitle: f.displayName.isEmpty
                            ? null
                            : Text(f.displayName),
                        trailing: _friend?.id == f.id
                            ? const Icon(Icons.check_circle)
                            : null,
                        selected: _friend?.id == f.id,
                        onTap: () => setState(() => _friend = f),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text('On', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            SegmentedButton<DuelMetric>(
              segments: [
                for (final m in DuelMetric.values)
                  ButtonSegment(value: m, label: Text(m.label)),
              ],
              selected: {_metric},
              onSelectionChanged: (s) => setState(() => _metric = s.first),
            ),
            const SizedBox(height: 4),
            Text(_metric.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _friend == null || _busy ? null : _send,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt),
              label: const Text('Send challenge'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final f = _friend;
    if (f == null) return;
    setState(() => _busy = true);
    try {
      final duel = await ref
          .read(duelsRepoProvider)
          .challenge(
            opponent: DuelParty(
              userId: f.id,
              handle: f.handle,
              displayName: f.displayName,
            ),
            metric: _metric,
          );
      if (mounted) Navigator.pop(context, duel);
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
