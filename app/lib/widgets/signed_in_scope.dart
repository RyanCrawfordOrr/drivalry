import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/routes.dart';
import '../app/ui/ui.dart';
import '../data/supabase/supabase_providers.dart';

/// Wraps a social screen. Shows [child] when signed in; otherwise one
/// `EmptyState` with a sign-in button. A version without the online service
/// says so in the same grammar, with no button, so every tab renders
/// something honest offline (docs/12 §7).
class SignedInScope extends ConsumerWidget {
  const SignedInScope({
    super.key,
    required this.child,
    this.message = 'See what your friends are up to.',
    this.icon = Icons.people_outline,
    this.kicker,
  });

  final Widget child;

  /// One line on what the screen does, shown under the headline.
  final String message;

  /// Kept for callers; names the area when [kicker] is not given.
  final IconData icon;

  /// The small label above the headline. Defaults from [icon].
  final String? kicker;

  String get _kicker =>
      kicker ??
      switch (icon) {
        Icons.route_outlined => 'Convoy',
        Icons.radio_outlined => 'Radio',
        Icons.groups_outlined => 'Circles',
        Icons.emoji_events_outlined => 'Leagues',
        Icons.bolt_outlined => 'Duels',
        Icons.person_outline => 'Profile',
        _ => 'Friends',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(cloudConfiguredProvider)) {
      return SingleChildScrollView(
        child: EmptyState(
          kicker: _kicker,
          headline: 'Not available in this version yet.',
          body:
              'Friends, leagues and convoys are coming. Drives still score on '
              'this phone.',
        ),
      );
    }
    if (ref.watch(isSignedInProvider)) return child;
    return SingleChildScrollView(
      child: EmptyState(
        kicker: _kicker,
        headline: 'Sign in to see this.',
        body: message,
        actionLabel: 'Sign in',
        onAction: () => context.push(Routes.signIn),
      ),
    );
  }
}
