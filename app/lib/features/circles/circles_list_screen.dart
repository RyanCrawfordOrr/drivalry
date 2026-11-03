import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/circles_sync.dart';
import '../../widgets/signed_in_scope.dart';
import 'circles_view.dart';

/// Standalone route for the Circles segment (`/friends/circles`).
class CirclesListScreen extends ConsumerWidget {
  const CirclesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(circlesSyncProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Circles')),
      body: const SignedInScope(
        message: 'Sign in to share your location with a circle.',
        icon: Icons.groups_outlined,
        child: CirclesView(),
      ),
    );
  }
}
