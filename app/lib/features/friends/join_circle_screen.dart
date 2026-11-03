import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/circles_repo.dart';
import '../../data/repos/circles_sync.dart';
import '../../widgets/signed_in_scope.dart';

/// Lands `drivalry://join/circle/<code>` links and the "Join with code"
/// dialog: one tap joins through the `join_circle` RPC.
class JoinCircleScreen extends ConsumerStatefulWidget {
  const JoinCircleScreen({super.key, required this.code});

  final String code;

  @override
  ConsumerState<JoinCircleScreen> createState() => _JoinCircleScreenState();
}

class _JoinCircleScreenState extends ConsumerState<JoinCircleScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(circlesRepoProvider).join(widget.code);
      if (!mounted) return;
      context.go(Routes.circle(id));
    } on CircleJoinException catch (e) {
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
      appBar: AppBar(title: const Text('Circle invite')),
      body: SignedInScope(
        message: 'Sign in to join the circle.',
        icon: Icons.groups_outlined,
        child: Center(
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
                Text('Join this circle?', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Code ${widget.code.toUpperCase()}. Everyone in the circle '
                  'will see your live location, and you theirs. You can hide '
                  'at any time; they can see that you are hiding.',
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
                      : const Icon(Icons.group_add_outlined),
                  label: const Text('Join circle'),
                ),
                TextButton(
                  onPressed: () => context.go(Routes.friends),
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
