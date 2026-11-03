import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/routes.dart';
import '../data/supabase/supabase_providers.dart';

/// Wraps a social screen. Shows [child] when signed in; otherwise a short
/// explanation and a sign-in button. A build without a Supabase project
/// explains that too, so every tab renders something honest offline.
class SignedInScope extends ConsumerWidget {
  const SignedInScope({
    super.key,
    required this.child,
    this.message = 'Sign in to use this with friends.',
    this.icon = Icons.people_outline,
  });

  final Widget child;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(cloudConfiguredProvider)) {
      return _Notice(
        icon: Icons.cloud_off_outlined,
        title: 'Offline build',
        body:
            'This build has no Drivalry cloud project configured, so friends, '
            'leagues and the feed are unavailable. Tracking and scoring still '
            'work.',
      );
    }
    if (ref.watch(isSignedInProvider)) return child;
    return _Notice(
      icon: icon,
      title: 'Not signed in',
      body: message,
      action: FilledButton.icon(
        onPressed: () => context.push(Routes.signIn),
        icon: const Icon(Icons.login),
        label: const Text('Sign in'),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
