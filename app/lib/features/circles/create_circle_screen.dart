import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/repos/circles_sync.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/signed_in_scope.dart';

/// Name a circle; the invite code arrives from the server a moment later.
class CreateCircleScreen extends ConsumerStatefulWidget {
  const CreateCircleScreen({super.key});

  @override
  ConsumerState<CreateCircleScreen> createState() => _CreateCircleScreenState();
}

class _CreateCircleScreenState extends ConsumerState<CreateCircleScreen> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the circle a name.');
      return;
    }
    if (name.length > 40) {
      setState(() => _error = 'Keep it under 40 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(circlesRepoProvider).create(name);
      if (!mounted) return;
      Haptics.success();
      context.pushReplacement(Routes.circle(id));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e, doing: 'create the circle');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New circle')),
      body: SignedInScope(
        message: 'Sign in to create a circle.',
        icon: Icons.groups_outlined,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.lg,
            Space.gutter,
            Space.xxxl,
          ),
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'Family, Roommates, The Boys',
                errorText: _error,
              ),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: Space.md),
            Text(
              'Everyone in it sees each other\'s live location and roasts. '
              'Anyone can hide, and the circle sees that.',
              style: context.caption,
            ),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              label: 'Create circle',
              icon: Icons.group_add_outlined,
              busy: _busy,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}
