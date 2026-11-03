import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/leagues_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';
import 'leagues_routes.dart';
import 'widgets/tier_chip.dart';

/// Weekly leagues with friends. Score and consistency climb the table; speed
/// never does.
class LeaguesScreen extends StatelessWidget {
  const LeaguesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leagues'),
        actions: [
          IconButton(
            tooltip: 'Badges',
            icon: const Icon(Icons.military_tech_outlined),
            onPressed: () => context.push(badgesPath),
          ),
        ],
      ),
      body: const SignedInScope(
        message: 'Sign in to race your friends on how well you drive.',
        icon: Icons.emoji_events_outlined,
        child: _LeaguesBody(),
      ),
    );
  }
}

class _LeaguesBody extends ConsumerWidget {
  const _LeaguesBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refresh = ref.watch(refreshMyLeaguesProvider);
    final leagues = ref.watch(myLeaguesProvider).value ?? const <League>[];
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('League'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(refreshMyLeaguesProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (refresh.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Showing the last known tables. Pull to retry.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            if (leagues.isEmpty && !refresh.isLoading)
              const _EmptyLeagues()
            else if (leagues.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final l in leagues) _LeagueTile(league: l),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create a league'),
              subtitle: const Text('Up to 30 friends, Monday to Sunday'),
              onTap: () {
                Navigator.pop(ctx);
                context.push(Routes.createLeague);
              },
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Join with a code'),
              subtitle: const Text('Paste the 8-character invite code'),
              onTap: () {
                Navigator.pop(ctx);
                _joinByCode(context, ref);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _joinByCode(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a league'),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(labelText: 'Invite code'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    try {
      final id = await ref.read(leaguesRepoProvider).joinByCode(code);
      if (context.mounted) context.push(Routes.league(id));
    } on LeagueJoinException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

class _LeagueTile extends ConsumerWidget {
  const _LeagueTile({required this.league});
  final League league;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final week = ref.watch(leagueCurrentWeekProvider(league.id)).value;
    final me = ref.watch(currentUserIdProvider);
    final mine = me == null ? null : week?.rowFor(me);
    final rankText = mine == null
        ? null
        : '#${mine.rank} of ${week!.rows.length} this week · ${mine.xp} XP';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => context.push(Routes.league(league.id)),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            league.name.isEmpty ? '?' : league.name[0].toUpperCase(),
            style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        title: Text(league.name),
        subtitle: Text(
          [
            '${league.memberCount} member${league.memberCount == 1 ? '' : 's'}',
            ?rankText,
            if (league.myHiding) 'hiding',
          ].join(' · '),
        ),
        trailing: TierChip(tier: league.myTier, dense: true),
      ),
    );
  }
}

class _EmptyLeagues extends StatelessWidget {
  const _EmptyLeagues();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('No leagues yet', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Create one and send the invite link to your friends, or paste a '
            'code someone sent you. Weeks run Monday to Sunday. The top five '
            'move up a tier, the bottom five move down, and skipping a week '
            'moves you down too.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
