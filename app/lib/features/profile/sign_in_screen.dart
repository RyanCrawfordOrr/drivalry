import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../config/env.dart';
import '../../data/supabase/auth_service.dart';
import '../../data/supabase/supabase_providers.dart';

/// Continue with Apple (iOS) or Google (both). No passwords, no email
/// (docs/09-auth-setup.md).
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.cloudConfigured});

  /// Whether a Supabase project is configured; null means `Env.hasSupabase`.
  /// Tests pass a value.
  final bool? cloudConfigured;

  /// The one line every tester should read before adding friends (ADR-018).
  static const String privacyNote =
      'Adding a friend shares your live location with them. '
      'You can hide it any time in Settings.';

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/drive');
      }
    } on SignInFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.cancelled ? null : e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = ref.watch(authServiceProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final showApple = AuthService.appleAvailable;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.directions_car,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Drivalry',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Sign in to join leagues, see friends and get roasted in public.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            if (!(widget.cloudConfigured ?? Env.hasSupabase))
              const _Notice(
                'This build has no Drivalry cloud project configured, so '
                'sign-in is unavailable.',
              )
            else if (signedIn)
              const _Notice('You are signed in.')
            else ...[
              if (showApple) ...[
                FilledButton.icon(
                  key: const Key('sign-in-apple'),
                  onPressed: _busy ? null : () => _run(auth.signInWithApple),
                  icon: const Icon(Icons.apple),
                  label: const Text('Continue with Apple'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                key: const Key('sign-in-google'),
                onPressed: _busy ? null : () => _run(auth.signInWithGoogle),
                icon: const Text(
                  'G',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                label: const Text('Continue with Google'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              if (!AuthService.googleAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Google sign-in is not configured for this build.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  key: const Key('sign-in-error'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const Spacer(),
            Text(
              SignInScreen.privacyNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
