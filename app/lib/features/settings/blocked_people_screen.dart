import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/ui/ui.dart';
import '../../data/repos/moderation_repo.dart';
import '../friends/moderation_actions.dart';
import '../friends/widgets/page_insets.dart';
import '../friends/widgets/person_row.dart';

/// Everyone the signed-in user blocked, with Unblock on each row
/// (docs/05 §1). Blocking happens from a profile, a post or a request.
class BlockedPeopleScreen extends ConsumerWidget {
  const BlockedPeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(moderationStateProvider).value ?? const ModerationState();
    final blocked = state.blocked;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const LargeTitleBar(title: 'Blocked people'),
          SliverPadding(
            padding: EdgeInsets.only(
              top: Space.sm,
              bottom: pageBottomInset(context),
            ),
            sliver: SliverToBoxAdapter(
              child: blocked.isEmpty
                  ? const EmptyState(
                      kicker: 'Blocked',
                      headline: 'Nobody is blocked.',
                      body:
                          'Block someone from their profile, a post or a '
                          'friend request and they show up here. Blocked '
                          'people cannot see your drives, posts or location.',
                    )
                  : Padding(
                      padding: Space.screen,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'They cannot see you or reach you. Unblock '
                            'restores nothing on its own; add them again '
                            'if you want to be friends.',
                            style: context.bodyMuted,
                          ),
                          const SizedBox(height: Space.lg),
                          for (var i = 0; i < blocked.length; i++)
                            Reveal(
                              delay: Reveal.stagger(i),
                              child: PersonRow(
                                name: blocked[i].name,
                                avatarPath: blocked[i].avatarPath,
                                caption: '@${blocked[i].handle}',
                                trailing: TextButton(
                                  onPressed: () =>
                                      unblockUserFlow(context, ref, blocked[i]),
                                  child: const Text('Unblock'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
