import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/brand/drivalry_mark.dart';
import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../config/env.dart';
import '../../data/supabase/auth_service.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/friendly_error.dart';

/// Continue with Apple (iOS) or Google (both). No passwords, no email
/// (docs/09-auth-setup.md). The mark, one line, two buttons, one privacy
/// sentence (docs/12 §7), starting right under the status bar rather than
/// floating mid-screen; Not now and the privacy line hold the bottom.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.cloudConfigured, this.googleConfigured});

  /// Whether a Supabase project is configured; null means `Env.hasSupabase`.
  /// Tests pass a value.
  final bool? cloudConfigured;

  /// Whether Google sign-in is configured; null means
  /// `AuthService.googleAvailable`. Tests pass a value.
  final bool? googleConfigured;

  /// The one line every tester should read before adding friends (ADR-018).
  static const String privacyNote =
      'Adding a friend shares your live location with them. '
      'You can hide it any time in Settings.';

  /// Shown instead of the buttons in a version without sign-in.
  static const String unavailableNote =
      'Sign-in isn\'t available in this version yet.';

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

/// One friendly sentence for a sign-in failure. Configuration problems are
/// never described as such.
String signInErrorText(Object e) {
  final raw = (e is SignInFailure ? e.message : e.toString()).toLowerCase();
  // Single words on purpose: the copy audit reads two-word literals as copy.
  if (raw.contains('configured') ||
      raw.contains('cloud') ||
      raw.contains('enabled')) {
    friendlyError(e, doing: 'sign in');
    return SignInScreen.unavailableNote;
  }
  if (e is SignInFailure) return e.message;
  return friendlyError(e, doing: 'sign in');
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  String? _busy;
  String? _error;

  Future<void> _run(String which, Future<void> Function() action) async {
    setState(() {
      _busy = which;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Haptics.success();
      _leave();
    } on SignInFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.cancelled ? null : signInErrorText(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = signInErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Back to wherever sign-in was opened from; home when it was the first
  /// screen.
  void _leave() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      if (router.canPop()) {
        router.pop();
      } else {
        router.go(Routes.drive);
      }
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authServiceProvider);
    final signedIn = ref.watch(isSignedInProvider);
    final showApple = AuthService.appleAvailable;
    final showGoogle = widget.googleConfigured ?? AuthService.googleAvailable;
    // No dead buttons: a version with neither provider says so instead.
    final cloud =
        (widget.cloudConfigured ?? Env.hasSupabase) &&
        (showApple || showGoogle);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xxl,
            Space.gutter,
            Space.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Reveal(
                        offset: Offset(0, 0.04),
                        duration: Motion.celebrate,
                        child: Center(child: DrivalryMark.tile(size: 96)),
                      ),
                      const SizedBox(height: Space.xl),
                      Reveal(
                        delay: Reveal.stagger(2),
                        child: Column(
                          children: [
                            Text(
                              'Drivalry',
                              textAlign: TextAlign.center,
                              style: context.headline,
                            ),
                            const SizedBox(height: Space.md),
                            Text(
                              'Score your drives. Beat your friends. '
                              'Get roasted.',
                              textAlign: TextAlign.center,
                              style: context.body,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Space.xxl),
                      Reveal(
                        delay: Reveal.stagger(4),
                        child: StateSwitcher(
                          child: !cloud
                              ? const _Note(
                                  key: ValueKey('offline'),
                                  SignInScreen.unavailableNote,
                                )
                              : signedIn
                              ? const _Note(
                                  key: ValueKey('in'),
                                  'You are signed in.',
                                )
                              : Column(
                                  key: const ValueKey('buttons'),
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showApple) ...[
                                      PressScale(
                                        child: PrimaryButton(
                                          key: const Key('sign-in-apple'),
                                          label: 'Continue with Apple',
                                          icon: Icons.apple,
                                          busy: _busy == 'apple',
                                          onPressed: _busy != null
                                              ? null
                                              : () => _run(
                                                  'apple',
                                                  auth.signInWithApple,
                                                ),
                                        ),
                                      ),
                                      if (showGoogle) ...[
                                        const SizedBox(height: Space.md),
                                        PressScale(
                                          child: SecondaryButton(
                                            key: const Key('sign-in-google'),
                                            label: 'Continue with Google',
                                            icon: Icons.account_circle_outlined,
                                            onPressed: _busy != null
                                                ? null
                                                : () => _run(
                                                    'google',
                                                    auth.signInWithGoogle,
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ] else
                                      PressScale(
                                        child: PrimaryButton(
                                          key: const Key('sign-in-google'),
                                          label: 'Continue with Google',
                                          icon: Icons.account_circle_outlined,
                                          busy: _busy == 'google',
                                          onPressed: _busy != null
                                              ? null
                                              : () => _run(
                                                  'google',
                                                  auth.signInWithGoogle,
                                                ),
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: Space.lg),
                        Text(
                          _error!,
                          key: const Key('sign-in-error'),
                          textAlign: TextAlign.center,
                          style: context.body.copyWith(color: scheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              TextButton(
                key: const Key('sign-in-not-now'),
                onPressed: _leave,
                child: const Text('Not now'),
              ),
              const SizedBox(height: Space.sm),
              Text(
                SignInScreen.privacyNote,
                textAlign: TextAlign.center,
                style: context.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Tile(
    child: Text(text, textAlign: TextAlign.center, style: context.bodyMuted),
  );
}
