import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repos/convoy_repo.dart';
import '../../data/repos/convoy_sync.dart';
import '../../widgets/signed_in_scope.dart';
import 'widgets/destination_picker.dart';

/// Name the convoy, optionally pick where it is going, create it. The invite
/// code arrives from the server a moment later.
class CreateConvoyScreen extends ConsumerStatefulWidget {
  const CreateConvoyScreen({super.key});

  @override
  ConsumerState<CreateConvoyScreen> createState() => _CreateConvoyScreenState();
}

class _CreateConvoyScreenState extends ConsumerState<CreateConvoyScreen> {
  final _name = TextEditingController();
  Destination? _destination;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(convoyRepoProvider)
          .create(name, destination: _destination);
      if (!mounted) return;
      context.go(Routes.convoyDetail(id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not create: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dest = _destination;
    return Scaffold(
      appBar: AppBar(title: const Text('New convoy')),
      body: SignedInScope(
        message: 'Sign in to start a convoy.',
        icon: Icons.route_outlined,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              key: const Key('convoy-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Trip name',
                hintText: 'Coast run, Thanksgiving drive…',
              ),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(dest?.name ?? 'Destination (optional)'),
                subtitle: Text(
                  dest == null
                      ? 'Where everyone is heading. Needed for ETAs and stop '
                            'suggestions; you can set it later.'
                      : 'Tap to change',
                ),
                trailing: dest == null
                    ? const Icon(Icons.chevron_right)
                    : IconButton(
                        tooltip: 'Clear',
                        onPressed: () => setState(() => _destination = null),
                        icon: const Icon(Icons.close),
                      ),
                onTap: () async {
                  final picked = await showDestinationPicker(context);
                  if (picked != null && mounted) {
                    setState(() => _destination = picked);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Up to six cars. You lead: you start and end the trip, accept '
              'stops and can drop a regroup pin. Anyone can propose stops, '
              'add expenses and photos.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('create-convoy'),
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add_road_outlined),
              label: const Text('Create convoy'),
            ),
          ],
        ),
      ),
    );
  }
}
