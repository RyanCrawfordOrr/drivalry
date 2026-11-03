import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';
import 'circles_view.dart';

/// Standalone route for the Circles segment (`/friends/circles`). New circle
/// is an app-bar action once there is at least one circle; before that the
/// empty state carries the button.
class CirclesListScreen extends ConsumerWidget {
  const CirclesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(circlesSyncProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final circles = ref.watch(myCirclesProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circles'),
        actions: [
          // In the bar, never floating over a tile.
          if (signedIn && circles.isNotEmpty)
            IconButton(
              tooltip: 'New circle',
              onPressed: () => context.push(Routes.createCircle),
              icon: const Icon(Icons.group_add_outlined),
            ),
        ],
      ),
      body: SignedInScope(
        message: 'Sign in to share your location with a circle.',
        icon: Icons.groups_outlined,
        child: RefreshIndicator(
          onRefresh: () => ref.read(myCirclesProvider.notifier).refresh(),
          child: const CirclesView(),
        ),
      ),
    );
  }
}
