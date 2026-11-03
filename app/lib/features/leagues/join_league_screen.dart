import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/leagues_repo.dart';
import '../../data/supabase/supabase_providers.dart';
import '../../widgets/friendly_error.dart';
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
      Haptics.success();
      if (mounted) context.go(Routes.league(id));
    } on LeagueJoinException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _error = friendlyError(e, doing: 'join the league'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only attempt once a user is signed in; SignedInScope handles the rest.
    if (ref.watch(isSignedInProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Join league')),
      body: SignedInScope(
        message: 'Sign in to accept this league invite.',
        icon: Icons.emoji_events_outlined,
        child: _error == null
            ? const Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.xxxl,
                  Space.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Kicker('League invite'),
                    SizedBox(height: Space.md),
                    SkeletonTile(height: 96),
                  ],
                ),
              )
            : EmptyState(
                kicker: 'League invite',
                headline: 'Could not join.',
                body: _error,
                actionLabel: 'Back to leagues',
                onAction: () => context.go(Routes.leagues),
              ),
      ),
    );
  }
}
