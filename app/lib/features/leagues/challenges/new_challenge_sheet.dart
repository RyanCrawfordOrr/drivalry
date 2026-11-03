import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repos/challenges_repo.dart';

/// Goal, target and length for a new group challenge. Resolves with the
/// challenge, or null when dismissed.
Future<GroupChallenge?> showNewChallengeSheet(
  BuildContext context,
  String leagueId,
) => showModalBottomSheet<GroupChallenge>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => NewChallengeSheet(leagueId: leagueId),
);

class NewChallengeSheet extends ConsumerStatefulWidget {
  const NewChallengeSheet({super.key, required this.leagueId});
  final String leagueId;

  @override
  ConsumerState<NewChallengeSheet> createState() => _NewChallengeSheetState();
}

class _NewChallengeSheetState extends ConsumerState<NewChallengeSheet> {
  ChallengeGoal _goal = ChallengeGoal.cleanTrips;
  int _days = 7;
  bool _busy = false;
  late final TextEditingController _target = TextEditingController(
    text: '${_goal.defaultTarget}',
  );

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Group challenge', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'One goal for the whole league. Everyone who is a member when '
                'it ends earns the badge if the league makes it.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              RadioGroup<ChallengeGoal>(
                groupValue: _goal,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _goal = v;
                    _target.text = '${v.defaultTarget}';
                  });
                },
                child: Column(
                  children: [
                    for (final g in ChallengeGoal.values)
                      RadioListTile<ChallengeGoal>(
                        dense: true,
                        value: g,
                        title: Text(g.label),
                        subtitle: Text(g.description),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Target',
                  suffixText: _goal.unit,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('One week')),
                  ButtonSegment(value: 14, label: Text('Two weeks')),
                ],
                selected: {_days},
                onSelectionChanged: (s) => setState(() => _days = s.first),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag),
                label: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    final target = int.tryParse(_target.text.trim());
    if (target == null || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a whole-number target above zero.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final c = await ref
          .read(challengesRepoProvider)
          .create(
            leagueId: widget.leagueId,
            goal: _goal,
            target: target,
            days: _days,
          );
      if (mounted) Navigator.pop(context, c);
    } on ChallengeException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}
