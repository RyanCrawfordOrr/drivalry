import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repos/friends_sync.dart';
import 'router.dart';

/// Bottom navigation around the five tab branches.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) {
          shell.goBranch(
            index,
            // Tapping the active tab pops that tab back to its root.
            initialLocation: index == shell.currentIndex,
          );
          // The branch keeps its state between visits, so the Friends screen
          // never rebuilds on its own: give it a fresh snapshot on the way in.
          if (AppTab.values[index] == AppTab.friends) {
            unawaited(
              ref.read(friendsSnapshotProvider.notifier).refreshIfStale(),
            );
          }
        },
        destinations: [
          for (final tab in AppTab.values)
            NavigationDestination(
              icon: _TabIcon(tab, selected: false),
              selectedIcon: _TabIcon(tab, selected: true),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}

/// A tab's icon. Friends carries a red dot while a friend request is waiting
/// for an answer, so the ask is visible from every tab; accepting or
/// declining the request clears it. A dot rather than a count: the number
/// is on the requests button once you are there.
class _TabIcon extends ConsumerWidget {
  const _TabIcon(this.tab, {required this.selected});

  final AppTab tab;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = Icon(selected ? tab.selectedIcon : tab.icon);
    if (tab != AppTab.friends) return icon;
    final pending = ref.watch(pendingRequestCountProvider);
    return Badge(
      isLabelVisible: pending > 0,
      backgroundColor: Theme.of(context).colorScheme.error,
      child: icon,
    );
  }
}
