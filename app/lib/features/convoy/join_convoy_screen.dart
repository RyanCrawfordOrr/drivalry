import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/convoy_repo.dart';
import '../../data/repos/convoy_sync.dart';
import '../../widgets/signed_in_scope.dart';

/// Lands `drivalry://join/convoy/<code>` links and the "Join with code"
/// dialog: one tap joins through the `join_convoy` RPC.
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
          _error = 'Could not join: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Convoy invite')),
      body: SignedInScope(
        message: 'Sign in to join the convoy.',
        icon: Icons.route_outlined,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.route_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text('Join this convoy?', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Code ${widget.code.toUpperCase()}. Everyone in the convoy '
                  'sees your car on the shared map and hears you on the radio '
                  'while the trip is on. Positions stay between the cars.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _join,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.directions_car_outlined),
                  label: const Text('Join convoy'),
                ),
                TextButton(
                  onPressed: () => context.go(Routes.convoy),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
