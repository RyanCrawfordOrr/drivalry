import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/deep_links.dart';
import '../../app/routes.dart';
import '../../data/alerts/auto_checkin.dart';
import '../../data/alerts/place_alerts.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';
import '../circles/circles_view.dart';
import 'feed_view.dart';
import 'friends_list_view.dart';

/// Friends tab: the public feed, the friends list and circles
/// (docs/01 §4.5, §4.9).
class FriendsScreen extends ConsumerWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(friendsSyncProvider);
    ref.watch(circlesSyncProvider);
    ref.watch(placeAlertsProvider);
    ref.watch(autoCheckinProvider);
    ref.watch(deepLinksProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final pending = ref.watch(pendingRequestCountProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Friends'),
          actions: [
            IconButton(
              tooltip: 'Friend requests',
              onPressed: () => context.push(Routes.friendRequests),
              icon: Badge.count(
                count: pending,
                isLabelVisible: pending > 0,
                child: const Icon(Icons.mark_email_unread_outlined),
              ),
            ),
          ],
          bottom: signedIn
              ? const TabBar(
                  tabs: [
                    Tab(text: 'Feed'),
                    Tab(text: 'Friends'),
                    Tab(text: 'Circles'),
                  ],
                )
              : null,
        ),
        body: const SignedInScope(
          message:
              'Sign in to see friends, their drives and the roasts they earned.',
          child: TabBarView(
            children: [FeedView(), FriendsListView(), CirclesView()],
          ),
        ),
        floatingActionButton: signedIn
            ? FloatingActionButton.extended(
                onPressed: () => context.push(Routes.addFriend),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Add friend'),
              )
            : null,
      ),
    );
  }
}
