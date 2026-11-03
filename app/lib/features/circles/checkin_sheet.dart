import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/alerts/auto_checkin.dart';
import '../../data/db/database.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/places_repo.dart';

/// "I got home": pick a saved place (or type one) and post a check-in that
/// carries only the label. Also hosts the auto check-in switch.
Future<void> showCheckinSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => const _CheckinSheet(),
  );
}

class _CheckinSheet extends ConsumerStatefulWidget {
  const _CheckinSheet();

  @override
  ConsumerState<_CheckinSheet> createState() => _CheckinSheetState();
}

class _CheckinSheetState extends ConsumerState<_CheckinSheet> {
  final _custom = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _post(String label) async {
    if (_busy) return;
    setState(() => _busy = true);
    final id = await ref.read(circlesRepoProvider).checkIn(label);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? 'Sign in to check in.'
              : 'Checked in at $label. Your circles and friends can see it.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final places = ref.watch(placesProvider).value ?? const <Place>[];
    final auto = ref.watch(autoCheckinEnabledProvider).value ?? false;
    final sorted = [...places]
      ..sort((a, b) {
        final ah = PlaceKind.fromWire(a.kind) == PlaceKind.home ? 0 : 1;
        final bh = PlaceKind.fromWire(b.kind) == PlaceKind.home ? 0 : 1;
        return ah.compareTo(bh);
      });
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Check in', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Posts "Checked in at …" to your circles and friends. Only the '
              'label is shared, never where that is.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (sorted.isEmpty)
              ListTile(
                leading: const Icon(Icons.add_location_alt_outlined),
                title: const Text('Save Home first'),
                subtitle: const Text('Places live only on this phone.'),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push(Routes.places);
                },
              ),
            for (final p in sorted)
              ListTile(
                leading: Icon(PlaceKind.fromWire(p.kind).icon),
                title: Text("I'm at ${p.label}"),
                onTap: _busy ? null : () => _post(p.label),
              ),
            TextField(
              controller: _custom,
              decoration: const InputDecoration(
                labelText: 'Somewhere else',
                hintText: 'e.g. Grandma\'s',
                prefixIcon: Icon(Icons.edit_location_alt_outlined),
              ),
              textInputAction: TextInputAction.send,
              maxLength: 40,
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _post(v.trim());
              },
            ),
            SwitchListTile(
              key: const Key('auto-checkin'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto check-in when I get Home'),
              subtitle: const Text(
                'Posts once when a drive ends inside a Home place.',
              ),
              value: auto,
              onChanged: (v) => ref
                  .read(databaseProvider)
                  .setSetting(autoCheckinSettingKey, v ? 'true' : 'false'),
            ),
          ],
        ),
      ),
    );
  }
}
