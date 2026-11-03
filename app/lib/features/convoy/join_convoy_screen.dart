import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/convoy_repo.dart';
import '../../data/repos/convoy_sync.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/signed_in_scope.dart';
import 'widgets/convoy_ui.dart';

/// Lands `drivalry://join/convoy/<code>` links and the "Join with a code"
/// sheet: one tap joins through the `join_convoy` RPC.
class JoinConvoyScreen extends ConsumerStatefulWidget {
  const JoinConvoyScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<JoinConvoyScreen> createState() => _JoinConvoyScreenState();
}

class _JoinConvoyScreenState extends ConsumerState<JoinConvoyScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(convoyRepoProvider).join(widget.code);
      if (!mounted) return;
      Haptics.success();
      context.go(Routes.convoyDetail(id));
    } on ConvoyJoinException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, doing: 'join the convoy');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Convoy invite')),
      body: SignedInScope(
        message: 'Sign in to join the convoy.',
        icon: Icons.route_outlined,
        child: ListView(
          children: [
            Reveal(
              child: ConvoyNotice(
                kicker: 'Code ${widget.code.toUpperCase()}',
                headline: 'Join this convoy?',
                body:
                    'Everyone sees your car on the map and hears you on the '
                    'radio while the trip is on.',
                action: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        key: const Key('join-error'),
                        style: context.body.copyWith(color: scheme.error),
                      ),
                      const SizedBox(height: Space.lg),
                    ],
                    PrimaryButton(
                      label: 'Join',
                      icon: Icons.directions_car_outlined,
                      busy: _busy,
                      onPressed: _join,
                    ),
                  ],
                ),
                secondary: TextButton(
                  onPressed: () => context.go(Routes.convoy),
                  child: const Text('Not now'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
