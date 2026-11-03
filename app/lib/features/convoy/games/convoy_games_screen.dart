import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/supabase/supabase_providers.dart';
import '../audio/convoy_audio_session.dart';
import '../widgets/member_names.dart';
import 'games_controller.dart';
import 'games_core.dart';

/// Passenger games for one convoy. Hidden while this phone is driving; the
/// driver hears results through TTS instead (docs/01 §4.6).
class ConvoyGamesScreen extends ConsumerWidget {
  const ConvoyGamesScreen({super.key, required this.convoyId});

  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driving = ref.watch(isDrivingNowProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: driving
          ? const Center(
              key: Key('driver-gate'),
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Games are for passengers. Drivers hear the results.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _GamesBody(convoyId: convoyId),
    );
  }
}

class _GamesBody extends ConsumerWidget {
  const _GamesBody({required this.convoyId});
  final String convoyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(gamesControllerProvider(convoyId));
    final c = ref.read(gamesControllerProvider(convoyId).notifier);
    final names =
        ref.watch(convoyMemberNamesProvider(convoyId)).value ?? const {};
    final selfId = ref.watch(currentUserIdProvider);
    String nameOf(String id) => memberLabel(names, id, selfId: selfId);
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Plates'),
              Tab(text: 'Trivia'),
              Tab(text: 'Spot the…'),
              Tab(text: 'Smoothest'),
            ],
          ),
          if (s.lastResult != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(s.lastResult!, key: const Key('last-result')),
            ),
          Expanded(
            child: TabBarView(
              children: [
                _PlatesTab(nameOf: nameOf, controller: c),
                _TriviaTab(nameOf: nameOf, controller: c, peers: s.peers),
                _ScavengerTab(nameOf: nameOf, controller: c),
                _SmoothestTab(nameOf: nameOf, controller: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatesTab extends StatelessWidget {
  const _PlatesTab({required this.nameOf, required this.controller});
  final GamesController controller;
  final String Function(String) nameOf;

  @override
  Widget build(BuildContext context) {
    final mine = controller.plates.mine;
    final standings = controller.plates.standings();
    return Column(
      children: [
        if (standings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (id, n) in standings)
                  Chip(label: Text('${nameOf(id)}: $n')),
              ],
            ),
          ),
        Expanded(
          child: GridView.count(
            crossAxisCount: 6,
            padding: const EdgeInsets.all(8),
            children: [
              for (final code in plateStates)
                InkWell(
                  key: Key('plate-$code'),
                  onTap: () => controller.togglePlate(code),
                  child: Container(
                    margin: const EdgeInsets.all(3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: mine.contains(code)
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: mine.contains(code)
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TriviaTab extends StatelessWidget {
  const _TriviaTab({
    required this.nameOf,
    required this.controller,
    required this.peers,
  });
  final GamesController controller;
  final String Function(String) nameOf;
  final Set<String> peers;

  @override
  Widget build(BuildContext context) {
    final t = controller.trivia;
    final q = t.current;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          controller.amTriviaHost
              ? 'You are asking the questions.'
              : 'Host: ${nameOf(Trivia.hostOf(peers, t.selfId))}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (q == null)
          Text(
            peers.isEmpty
                ? 'Trivia needs at least one other car on the radio.'
                : 'No question yet.',
          )
        else ...[
          Text(q.prompt, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < q.choices.length; i++)
            ListTile(
              key: Key('choice-$i'),
              leading: Icon(
                t.answers[t.selfId] == i
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
              ),
              title: Text(q.choices[i]),
              enabled: t.open && !t.answers.containsKey(t.selfId),
              onTap: () => controller.answerTrivia(i),
            ),
          Text(
            t.open ? '${t.answers.length} answered' : 'Closed',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        if (controller.amTriviaHost)
          Row(
            children: [
              FilledButton(
                key: const Key('next-question'),
                onPressed: controller.askNextQuestion,
                child: const Text('Next question'),
              ),
              const SizedBox(width: 8),
              if (q != null && t.open)
                OutlinedButton(
                  onPressed: controller.revealTrivia,
                  child: const Text('Reveal now'),
                ),
            ],
          ),
        if (t.scores.isNotEmpty) ...[
          const Divider(),
          Text('Scores', style: theme.textTheme.labelLarge),
          for (final e in t.scores.entries)
            Text('${nameOf(e.key)}: ${e.value}'),
        ],
      ],
    );
  }
}

class _ScavengerTab extends StatelessWidget {
  const _ScavengerTab({required this.nameOf, required this.controller});
  final GamesController controller;
  final String Function(String) nameOf;

  @override
  Widget build(BuildContext context) {
    final s = controller.scavenger;
    final tally = s.tally();
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (tally.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              for (final e in tally.entries)
                Chip(label: Text('${nameOf(e.key)}: ${e.value}')),
            ],
          ),
        for (final item in s.items)
          ListTile(
            key: Key('spot-$item'),
            leading: Icon(
              s.claims.containsKey(item)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
            ),
            title: Text(item),
            subtitle: s.claims[item] == null
                ? null
                : Text(_spottedBy(nameOf(s.claims[item]!.$1))),
            onTap: s.claims.containsKey(item)
                ? null
                : () => controller.claimItem(item),
          ),
      ],
    );
  }
}

class _SmoothestTab extends StatelessWidget {
  const _SmoothestTab({required this.nameOf, required this.controller});
  final GamesController controller;
  final String Function(String) nameOf;

  @override
  Widget build(BuildContext context) {
    final rows = controller.smoothest.ranking();
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Needs a few minutes of positions from the other cars. This ranks '
            'steadiness, not speed.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (var i = 0; i < rows.length; i++)
          ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(nameOf(rows[i].$1)),
            trailing: Text(SmoothestLeg.label(rows[i].$2)),
          ),
      ],
    );
  }
}

String _spottedBy(String who) =>
    who == 'You' ? 'Spotted by you' : 'Spotted by $who';
