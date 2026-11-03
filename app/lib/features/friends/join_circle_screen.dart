import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';

/// Lands `drivalry://join/circle/<code>` links until circles ship (Stage 3),
/// so a tapped invite never shows the router's error page.
class JoinCircleScreen extends StatelessWidget {
  const JoinCircleScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Circle invite')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.groups_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Circles arrive in the next update.',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Ask your friend to add you directly for now. '
                'Invite code: $code',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.go(Routes.friends),
                icon: const Icon(Icons.people_outline),
                label: const Text('Go to Friends'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
