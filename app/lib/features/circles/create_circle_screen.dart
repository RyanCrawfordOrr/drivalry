import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/circles_sync.dart';
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
      context.pushReplacement(Routes.circle(id));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not create the circle: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New circle')),
      body: SignedInScope(
        message: 'Sign in to create a circle.',
        icon: Icons.groups_outlined,
        child: ListView(
          padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 8),
            Text(
              'Everyone you invite sees everyone else\'s live location, '
              'precise, and the trips and roasts you all earn. Anyone can hide '
              'at any time; the circle can see that they are hiding.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.group_add_outlined),
              label: const Text('Create circle'),
            ),
          ],
        ),
      ),
    );
  }
}
