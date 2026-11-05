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
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
