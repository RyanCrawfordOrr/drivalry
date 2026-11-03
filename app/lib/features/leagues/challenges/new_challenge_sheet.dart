import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/repos/challenges_repo.dart';

/// Goal, target and length for a new group challenge. Resolves with the
/// challenge, or null when dismissed.
Future<GroupChallenge?> showNewChallengeSheet(
  BuildContext context,
  String leagueId,
) => showDrivalrySheet<GroupChallenge>(
  context,
  title: 'Group challenge',
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'One goal for the whole league. Make it and everyone earns '
              'the badge.',
              style: context.bodyMuted,
            ),
            const SizedBox(height: Space.sm),
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
                      contentPadding: EdgeInsets.zero,
                      value: g,
                      title: Text(g.label, style: context.body),
                      subtitle: Text(g.description, style: context.caption),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            TextField(
              controller: _target,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Target',
                suffixText: _goal.unit,
              ),
            ),
            const SizedBox(height: Space.md),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('One week')),
                ButtonSegment(value: 14, label: Text('Two weeks')),
              ],
              selected: {_days},
              onSelectionChanged: (s) => setState(() => _days = s.first),
            ),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Start',
              icon: Icons.flag,
              busy: _busy,
              onPressed: _start,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start() async {
    final target = int.tryParse(_target.text.trim());
    if (target == null || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a whole number above zero.')),
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
