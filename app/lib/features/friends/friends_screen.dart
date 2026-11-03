import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/ui/ui.dart';
import '../../app/deep_links.dart';
import '../../app/routes.dart';
import '../../data/alerts/auto_checkin.dart';
import '../../data/alerts/place_alerts.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/friends_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';
import '../circles/circles_view.dart';
import 'feed_controller.dart';
import 'feed_view.dart';
import 'friends_list_view.dart';

/// Friends tab: the feed, the friends list and circles (docs/01 §4.5, §4.9;
/// docs/12 §7). A large title that collapses as the list scrolls, with the
/// three tabs pinned under it. One FAB for the whole tab, hoisted here so no
/// segment nests a Scaffold: Add friend on Feed and Friends, New circle on
/// Circles. It hides while the segment's empty state carries the same
/// button, so each screen state has one primary action.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refreshCurrent() => switch (_tabs.index) {
    0 => ref.read(feedControllerProvider.notifier).refresh(),
    1 => ref.read(friendsSnapshotProvider.notifier).refresh(),
    _ => ref.read(myCirclesProvider.notifier).refresh(),
  };

  @override
  Widget build(BuildContext context) {
    ref.watch(friendsSyncProvider);
    ref.watch(circlesSyncProvider);
    ref.watch(placeAlertsProvider);
    ref.watch(autoCheckinProvider);
    ref.watch(deepLinksProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final pending = ref.watch(pendingRequestCountProvider);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshCurrent,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: LargeTitleBar(
                title: 'Friends',
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
                    ? TabBar(
                        controller: _tabs,
                        tabs: const [
                          Tab(text: 'Feed'),
                          Tab(text: 'Friends'),
                          Tab(text: 'Circles'),
                        ],
                      )
                    : null,
              ),
            ),
          ],
          body: SignedInScope(
            message:
                'Sign in to see friends, their drives and the roasts they '
                'earned.',
            child: TabBarView(
              controller: _tabs,
              children: const [FeedView(), FriendsListView(), CirclesView()],
            ),
          ),
        ),
      ),
      floatingActionButton: signedIn ? _fab(context) : null,
    );
  }

  Widget? _fab(BuildContext context) {
    switch (_tabs.index) {
      case 0:
        if (ref.watch(feedControllerProvider).posts.isEmpty) return null;
        return _addFriend(context);
      case 1:
        final friends =
            ref.watch(friendsSnapshotProvider).value?.friends ?? const [];
        if (friends.isEmpty) return null;
        return _addFriend(context);
      default:
        final circles = ref.watch(myCirclesProvider).value ?? const [];
        if (circles.isEmpty) return null;
        return FloatingActionButton.extended(
          onPressed: () => context.push(Routes.createCircle),
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('New circle'),
        );
    }
  }

  Widget _addFriend(BuildContext context) => FloatingActionButton.extended(
    onPressed: () => context.push(Routes.addFriend),
    icon: const Icon(Icons.person_add_alt_1_outlined),
    label: const Text('Add friend'),
  );
}
