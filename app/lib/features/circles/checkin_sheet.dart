import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/ui/ui.dart';
import '../../data/alerts/auto_checkin.dart';
import '../../data/db/database.dart';
import '../../data/repos/circles_sync.dart';
import '../../data/repos/places_repo.dart';
import '../friends/widgets/page_insets.dart';

/// "I got home": pick a saved place (or type one) and post a check-in that
/// carries only the label. Also hosts the auto check-in switch.
Future<void> showCheckinSheet(BuildContext context) {
  return showDrivalrySheet<void>(
    context,
    title: 'Check in',
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
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (id != null) Haptics.success();
    messenger.showSnackBar(
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
    final places = ref.watch(placesProvider).value ?? const <Place>[];
    final auto = ref.watch(autoCheckinEnabledProvider).value ?? false;
    final sorted = [...places]
      ..sort((a, b) {
        final ah = PlaceKind.fromWire(a.kind) == PlaceKind.home ? 0 : 1;
        final bh = PlaceKind.fromWire(b.kind) == PlaceKind.home ? 0 : 1;
        return ah.compareTo(bh);
      });
    return Padding(
      padding: sheetBottomInset(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tells your circles and friends the name of the place, never '
            'where it is.',
            style: context.caption,
          ),
          const SizedBox(height: Space.md),
          if (sorted.isEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_location_alt_outlined),
              title: const Text('Save Home first'),
              subtitle: const Text('Places stay on this phone.'),
              onTap: () {
                Navigator.of(context).pop();
                context.push(Routes.places);
              },
            ),
          for (final p in sorted)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(PlaceKind.fromWire(p.kind).icon),
              title: Text("I'm at ${p.label}"),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : () => _post(p.label),
            ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _custom,
            decoration: const InputDecoration(
              labelText: 'Place name',
              hintText: 'Grandma\'s',
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
            title: const Text('Check in on my own at Home'),
            subtitle: const Text('Posts once when a drive ends at Home.'),
            value: auto,
            onChanged: (v) => ref
                .read(databaseProvider)
                .setSetting(autoCheckinSettingKey, v ? 'true' : 'false'),
          ),
        ],
      ),
    );
  }
}
