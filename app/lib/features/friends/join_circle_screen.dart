import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/circles_repo.dart';
import '../../data/repos/circles_sync.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/signed_in_scope.dart';
import 'widgets/page_insets.dart';

/// Lands `drivalry://join/circle/<code>` links and the "Join with code"
/// sheet: one tap joins through the `join_circle` RPC.
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
      Haptics.success();
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
          _error = friendlyError(e, doing: 'join the circle');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SignedInScope(
        message: 'Sign in to join the circle.',
        icon: Icons.groups_outlined,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.gutter,
            Space.xl,
            Space.gutter,
            pageBottomInset(context),
          ),
          children: [
            const Kicker('Circle invite'),
            const SizedBox(height: Space.md),
            Text('Join this circle?', style: context.headline),
            const SizedBox(height: Space.md),
            Text(
              'Everyone in it sees your live location, and you theirs. '
              'Hide any time; they see that you did.',
              style: context.bodyMuted,
            ),
            const SizedBox(height: Space.lg),
            Pill('Code ${widget.code.toUpperCase()}', icon: Icons.key_outlined),
            if (_error != null) ...[
              const SizedBox(height: Space.lg),
              Text(_error!, style: context.body.copyWith(color: scheme.error)),
            ],
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Join circle',
              icon: Icons.group_add_outlined,
              busy: _busy,
              onPressed: _join,
            ),
            const SizedBox(height: Space.sm),
            TextButton(
              onPressed: () => context.go(Routes.friends),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
