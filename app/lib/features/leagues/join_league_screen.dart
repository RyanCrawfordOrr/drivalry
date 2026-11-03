import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/leagues_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/signed_in_scope.dart';

/// Landing screen for `drivalry://join/league/<code>`: joins and moves on.
class JoinLeagueScreen extends ConsumerStatefulWidget {
  const JoinLeagueScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<JoinLeagueScreen> createState() => _JoinLeagueScreenState();
}

class _JoinLeagueScreenState extends ConsumerState<JoinLeagueScreen> {
  String? _error;
  bool _started = false;

  Future<void> _join() async {
    if (_started) return;
    _started = true;
    try {
      final id = await ref.read(leaguesRepoProvider).joinByCode(widget.code);
      if (mounted) context.go(Routes.league(id));
    } on LeagueJoinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not join right now. Try again later.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only attempt once a user is signed in; SignedInScope handles the rest.
    if (ref.watch(isSignedInProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Join league')),
      body: SignedInScope(
        message: 'Sign in to accept this league invite.',
        icon: Icons.emoji_events_outlined,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: _error == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        'Joining with code ${widget.code}…',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => context.go(Routes.leagues),
                        child: const Text('Back to leagues'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
