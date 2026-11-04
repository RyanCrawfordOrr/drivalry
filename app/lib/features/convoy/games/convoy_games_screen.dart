import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../audio/convoy_audio_session.dart';
import '../widgets/convoy_ui.dart';
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
          // Top of the page, like every empty screen (docs/12 §2).
          ? const SingleChildScrollView(
              child: EmptyState(
                key: Key('driver-gate'),
                kicker: 'Games',
                headline: 'Passengers only.',
                body: 'Games are for passengers. Drivers hear the results.',
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
    final scheme = Theme.of(context).colorScheme;
    final s = ref.watch(gamesControllerProvider(convoyId));
    final c = ref.read(gamesControllerProvider(convoyId).notifier);
    final names =
        ref.watch(convoyMemberNamesProvider(convoyId)).value ?? const {};
    final selfId = ref.watch(currentUserIdProvider);
    String nameOf(String id) => memberLabel(names, id, selfId: selfId);
    return DefaultTabController(
      length: 4,
      child: Column(
        // Stretched, so the result tile spans gutter to gutter like every
        // other tile instead of floating centred.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: EdgeInsets.symmetric(horizontal: Space.xs),
            tabs: [
              Tab(text: 'Plates'),
              Tab(text: 'Trivia'),
              Tab(text: 'I spy'),
              Tab(text: 'Smoothest'),
            ],
          ),
          StateSwitcher(
            child: s.lastResult == null
                ? const SizedBox.shrink(key: ValueKey('no-result'))
                : Padding(
                    key: ValueKey(s.lastResult),
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.md,
                      Space.gutter,
                      0,
                    ),
                    child: Tile(
                      tone: TileTone.primary,
                      padding: const EdgeInsets.all(Space.lg),
                      child: Text(
                        s.lastResult!,
                        key: const Key('last-result'),
                        style: context.body.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PlatesTab(nameOf: nameOf, controller: c),
                _TriviaTab(nameOf: nameOf, controller: c, peers: s.peers),
                _SpyTab(nameOf: nameOf, controller: c),
                _SmoothestTab(nameOf: nameOf, controller: c),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Standings extends StatelessWidget {
  const _Standings({required this.rows});
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        0,
      ),
      child: Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final (i, (name, n)) in rows.indexed)
            Pill(
              '$name: $n',
              tone: i == 0 ? PillTone.primary : PillTone.neutral,
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
    final scheme = Theme.of(context).colorScheme;
    final mine = controller.plates.mine;
    final standings = controller.plates.standings();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Standings(rows: [for (final (id, n) in standings) (nameOf(id), n)]),
        Expanded(
          child: GridView.count(
            crossAxisCount: 6,
            mainAxisSpacing: Space.sm,
            crossAxisSpacing: Space.sm,
            padding: EdgeInsets.fromLTRB(
              Space.gutter,
              Space.md,
              Space.gutter,
              pageBottomInset(context),
            ),
            children: [
              for (final code in plateStates)
                Tile(
                  key: Key('plate-$code'),
                  tone: mine.contains(code)
                      ? TileTone.primary
                      : TileTone.resting,
                  radius: Radii.tileRadius,
                  padding: EdgeInsets.zero,
                  onTap: () {
                    Haptics.select();
                    controller.togglePlate(code);
                  },
                  child: Center(
                    child: Text(
                      code,
                      style: context.label.copyWith(
                        color: mine.contains(code)
                            ? scheme.onPrimaryContainer
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
    final scheme = Theme.of(context).colorScheme;
    final t = controller.trivia;
    final q = t.current;
    final answered = t.answers.containsKey(t.selfId);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        pageBottomInset(context),
      ),
      children: [
        Text(
          controller.amTriviaHost
              ? 'You are asking the questions.'
              : 'Host: ${nameOf(Trivia.hostOf(peers, t.selfId))}',
          style: context.caption,
        ),
        const SizedBox(height: Space.md),
        if (q == null)
          Text(
            peers.isEmpty
                ? 'Trivia needs another car on the radio.'
                : 'No question yet.',
            style: context.bodyMuted,
          )
        else ...[
          Text(q.prompt, style: context.title),
          const SizedBox(height: Space.md),
          for (var i = 0; i < q.choices.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.sm),
            Reveal(
              delay: Reveal.stagger(i),
              child: Tile(
                key: Key('choice-$i'),
                tone: t.answers[t.selfId] == i
                    ? TileTone.primary
                    : TileTone.resting,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.md,
                ),
                onTap: t.open && !answered
                    ? () {
                        Haptics.select();
                        controller.answerTrivia(i);
                      }
                    : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Space.xxl),
                  child: Row(
                    children: [
                      Icon(
                        t.answers[t.selfId] == i
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: t.answers[t.selfId] == i
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          q.choices[i],
                          style: context.body.copyWith(
                            color: t.answers[t.selfId] == i
                                ? scheme.onPrimaryContainer
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          Text(
            t.open ? '${t.answers.length} answered' : 'Closed',
            style: context.caption,
          ),
        ],
        const SizedBox(height: Space.lg),
        if (controller.amTriviaHost) ...[
          PrimaryButton(
            key: const Key('next-question'),
            label: 'Next question',
            onPressed: controller.askNextQuestion,
          ),
          if (q != null && t.open) ...[
            const SizedBox(height: Space.sm),
            SecondaryButton(
              label: 'Reveal now',
              onPressed: controller.revealTrivia,
            ),
          ],
        ],
        if (t.scores.isNotEmpty) ...[
          const SizedBox(height: Space.section),
          const Kicker('Scores'),
          const SizedBox(height: Space.sm),
          for (final e in t.scores.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Text('${nameOf(e.key)}: ${e.value}', style: context.body),
            ),
        ],
      ],
    );
  }
}

class _SpyTab extends StatelessWidget {
  const _SpyTab({required this.nameOf, required this.controller});
  final GamesController controller;
  final String Function(String) nameOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = controller.scavenger;
    final tally = s.tally();
    return ListView(
      padding: EdgeInsets.only(bottom: pageBottomInset(context)),
      children: [
        _Standings(
          rows: [for (final e in tally.entries) (nameOf(e.key), e.value)],
        ),
        const SizedBox(height: Space.sm),
        for (final item in s.items)
          Padding(
            padding: Space.screen,
            child: ConvoyRow(
              key: Key('spot-$item'),
              leading: Icon(
                s.claims.containsKey(item)
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: s.claims.containsKey(item)
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              title: item,
              titleStyle: context.body,
              caption: s.claims[item] == null
                  ? null
                  : _spottedBy(nameOf(s.claims[item]!.$1)),
              onTap: s.claims.containsKey(item)
                  ? null
                  : () {
                      Haptics.success();
                      controller.claimItem(item);
                    },
            ),
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
    final scheme = Theme.of(context).colorScheme;
    final rows = controller.smoothest.ranking();
    if (rows.isEmpty) {
      return const EmptyState(
        kicker: 'Smoothest',
        headline: 'Needs a few minutes of driving.',
        body: 'Ranks the steadiest car, not the fastest.',
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        pageBottomInset(context),
      ),
      children: [
        for (var i = 0; i < rows.length; i++)
          Reveal(
            delay: Reveal.stagger(i),
            child: ConvoyRow(
              leading: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == 0
                      ? scheme.primaryContainer
                      : scheme.surfaceContainerHighest,
                ),
                child: Text(
                  '${i + 1}',
                  style: context.label.copyWith(
                    color: i == 0 ? scheme.onPrimaryContainer : null,
                  ),
                ),
              ),
              title: nameOf(rows[i].$1),
              trailing: Pill(
                SmoothestLeg.label(rows[i].$2),
                tone: i == 0 ? PillTone.positive : PillTone.neutral,
              ),
            ),
          ),
      ],
    );
  }
}

String _spottedBy(String who) =>
    who == 'You' ? 'Spotted by you' : 'Spotted by $who';
