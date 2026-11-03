import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/duels_repo.dart';
import '../../../data/repos/friends_repo.dart';
import '../../../data/repos/friends_sync.dart';
import '../../friends/widgets/user_avatar.dart';

/// Pick a friend and a metric; the challenge goes out through the outbox.
/// Resolves with the new duel, or null when dismissed.
Future<Duel?> showNewDuelSheet(BuildContext context) => showDrivalrySheet<Duel>(
  context,
  title: 'Duel a friend',
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
    final friends =
        ref.watch(friendsSnapshotProvider).value?.friends ??
        const <FriendProfile>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Seven days from when they accept. The loser wears a badge the '
            'winner picks.',
            style: context.bodyMuted,
          ),
          const SizedBox(height: Space.lg),
          const Kicker('Who'),
          const SizedBox(height: Space.sm),
          if (friends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              child: Text(
                'Add a friend first. Duels are between friends.',
                style: context.bodyMuted,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in friends)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: UserAvatar(
                        name: f.name,
                        avatarPath: f.avatarPath,
                        radius: 20,
                      ),
                      title: Text('@${f.handle}', style: context.body),
                      subtitle: f.displayName.isEmpty
                          ? null
                          : Text(f.displayName, style: context.caption),
                      trailing: _friend?.id == f.id
                          ? const Icon(Icons.check_circle)
                          : null,
                      selected: _friend?.id == f.id,
                      onTap: () {
                        Haptics.select();
                        setState(() => _friend = f);
                      },
                    ),
                ],
              ),
            ),
          const SizedBox(height: Space.lg),
          const Kicker('On'),
          const SizedBox(height: Space.sm),
          // Chips wrap at 360 px where three segments would not fit.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final m in DuelMetric.values)
                ChoiceChip(
                  label: Text(m.label),
                  selected: _metric == m,
                  onSelected: (_) {
                    Haptics.select();
                    setState(() => _metric = m);
                  },
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(_metric.description, style: context.caption),
          const SizedBox(height: Space.xl),
          PrimaryButton(
            label: 'Send challenge',
            icon: Icons.bolt,
            busy: _busy,
            onPressed: _friend == null ? null : _send,
          ),
        ],
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
