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
      Haptics.success();
      context.go(Routes.convoyDetail(id));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, doing: 'create the convoy'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dest = _destination;
    return Scaffold(
      appBar: AppBar(title: const Text('New convoy')),
      body: SignedInScope(
        message: 'Sign in to start a convoy.',
        icon: Icons.route_outlined,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Space.gutter,
            Space.lg,
            Space.gutter,
            pageBottomInset(context),
          ),
          children: [
            Reveal(
              child: TextField(
                key: const Key('convoy-name'),
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Name your trip',
                  hintText: 'Coast run, Thanksgiving drive…',
                ),
                onSubmitted: (_) => _create(),
              ),
            ),
            const SizedBox(height: Space.sm),
            Reveal(
              delay: Reveal.stagger(1),
              child: Tile(
                onTap: () async {
                  final picked = await showDestinationPicker(context);
                  if (picked != null && mounted) {
                    setState(() => _destination = picked);
                  }
                },
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.gutter,
                  vertical: Space.md,
                ),
                child: ConvoyRow(
                  padding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.flag_outlined,
                    size: 28,
                    color: scheme.primary,
                  ),
                  title: dest?.name ?? 'Destination',
                  caption: dest == null
                      ? 'Optional. Powers ETAs and stop ideas.'
                      : 'Tap to pick a different place.',
                  trailing: dest == null
                      ? const Icon(Icons.chevron_right)
                      : IconButton(
                          tooltip: 'Clear',
                          onPressed: () => setState(() => _destination = null),
                          icon: const Icon(Icons.close),
                        ),
                ),
              ),
            ),
            const SizedBox(height: Space.lg),
            Text(
              'Up to six cars. You lead: start and end the trip, accept stops, '
              'drop a regroup pin.',
              style: context.caption,
            ),
            const SizedBox(height: Space.xl),
            PrimaryButton(
              key: const Key('create-convoy'),
              label: 'Create convoy',
              icon: Icons.add_road_outlined,
              busy: _busy,
              onPressed: _create,
            ),
          ],
        ),
      ),
    );
  }
}
