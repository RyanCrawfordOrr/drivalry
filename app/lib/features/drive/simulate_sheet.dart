import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../data/db/database.dart';
import '../../tracking/simulated_tracking.dart';
import '../../tracking/tracking_controller.dart';

/// Developer action: replay a trip through the whole pipeline and open it.
Future<void> showSimulateSheet(BuildContext context, WidgetRef ref) async {
  final packs = await ref.read(databaseProvider).installedPacks();
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<_SimChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SimulateSheet(packs: packs),
  );
  if (choice == null || !context.mounted) return;

  final controller = ref.read(trackingControllerProvider.notifier);
  TripInput? input;
  switch (choice.kind) {
    case _SimKind.clean:
      input = cleanCommute('sim-clean');
    case _SimKind.messy:
      input = messyCommute('sim-messy');
    case _SimKind.fromPack:
      final pack = SqlitePack.open(choice.pack!.path);
      try {
        input = RouteSynthesizer(pack).build(
          lat: choice.lat!,
          lon: choice.lon!,
          speedingFraction: choice.speeding,
          id: 'sim-route',
        );
      } finally {
        pack.close();
      }
      if (input == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No road within 300 m of that point in the pack.'),
          ),
        );
        return;
      }
  }

  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  try {
    final id = await controller.simulate(input, speedUp: choice.speedUp);
    router.push(Routes.tripDetail(id));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Simulation failed: $e')));
  }
}

enum _SimKind { clean, messy, fromPack }

class _SimChoice {
  const _SimChoice(
    this.kind, {
    this.pack,
    this.lat,
    this.lon,
    this.speeding = 0.25,
    this.speedUp = 60,
  });
  final _SimKind kind;
  final Pack? pack;
  final double? lat;
  final double? lon;
  final double speeding;
  final double speedUp;
}

class _SimulateSheet extends StatefulWidget {
  const _SimulateSheet({required this.packs});
  final List<Pack> packs;

  @override
  State<_SimulateSheet> createState() => _SimulateSheetState();
}

class _SimulateSheetState extends State<_SimulateSheet> {
  Pack? _pack;
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  double _speeding = 0.25;
  double _speedUp = 0;

  @override
  void initState() {
    super.initState();
    _pack = widget.packs.isEmpty ? null : widget.packs.first;
    final p = _pack;
    _lat = TextEditingController(
      text: p == null
          ? ''
          : ((p.bboxMinLat + p.bboxMaxLat) / 2).toStringAsFixed(5),
    );
    _lon = TextEditingController(
      text: p == null
          ? ''
          : ((p.bboxMinLon + p.bboxMaxLon) / 2).toStringAsFixed(5),
    );
  }

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('Simulate a drive', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Replays a trip through the recorder, matcher and scorer exactly '
            'as the native plugin would deliver it.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Instant')),
              ButtonSegment(value: 60, label: Text('60×')),
              ButtonSegment(value: 10, label: Text('10×')),
            ],
            selected: {_speedUp},
            onSelectionChanged: (s) => setState(() => _speedUp = s.first),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.sentiment_satisfied_alt),
            title: const Text('Clean commute'),
            subtitle: const Text('Synthetic, 20 minutes, nothing to roast'),
            onTap: () => Navigator.pop(
              context,
              _SimChoice(_SimKind.clean, speedUp: _speedUp),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.local_fire_department_outlined),
            title: const Text('Messy commute'),
            subtitle: const Text('Synthetic, speeding, a slam and phone use'),
            onTap: () => Navigator.pop(
              context,
              _SimChoice(_SimKind.messy, speedUp: _speedUp),
            ),
          ),
          const Divider(),
          Text('From an installed pack', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          if (widget.packs.isEmpty)
            Text(
              'Install a speed-limit pack first (menu › Speed-limit packs).',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            DropdownButtonFormField<Pack>(
              initialValue: _pack,
              items: [
                for (final p in widget.packs)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: (p) => setState(() {
                _pack = p;
                if (p != null) {
                  _lat.text = ((p.bboxMinLat + p.bboxMaxLat) / 2)
                      .toStringAsFixed(5);
                  _lon.text = ((p.bboxMinLon + p.bboxMaxLon) / 2)
                      .toStringAsFixed(5);
                }
              }),
              decoration: const InputDecoration(labelText: 'Pack'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    decoration: const InputDecoration(
                      labelText: 'Start latitude',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lon,
                    decoration: const InputDecoration(
                      labelText: 'Start longitude',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Speeding'),
                Expanded(
                  child: Slider(
                    value: _speeding,
                    divisions: 4,
                    label: '${(_speeding * 100).round()}% of roads',
                    onChanged: (v) => setState(() => _speeding = v),
                  ),
                ),
              ],
            ),
            FilledButton.icon(
              onPressed: () {
                final lat = double.tryParse(_lat.text.trim());
                final lon = double.tryParse(_lon.text.trim());
                if (_pack == null || lat == null || lon == null) return;
                Navigator.pop(
                  context,
                  _SimChoice(
                    _SimKind.fromPack,
                    pack: _pack,
                    lat: lat,
                    lon: lon,
                    speeding: _speeding,
                    speedUp: _speedUp,
                  ),
                );
              },
              icon: const Icon(Icons.route),
              label: const Text('Drive from here'),
            ),
          ],
        ],
      ),
    );
  }
}
