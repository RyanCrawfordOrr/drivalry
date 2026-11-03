import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/ui/ui.dart';
import '../../data/db/database.dart';
import '../../tracking/simulated_tracking.dart';
import '../../tracking/tracking_controller.dart';
import '../../widgets/friendly_error.dart';

/// Developer action: replay a trip through the whole pipeline and open it.
Future<void> showSimulateSheet(BuildContext context, WidgetRef ref) async {
  final packs = await ref.read(databaseProvider).installedPacks();
  if (!context.mounted) return;
  final choice = await showDrivalrySheet<_SimChoice>(
    context,
    title: 'Simulate a drive',
    scrollable: true,
    builder: (_) => _SimulateSheet(packs: packs),
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
    messenger.showSnackBar(
      SnackBar(content: Text(friendlyError(e, doing: 'replay the drive'))),
    );
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Plays a pretend drive through the same scoring as a real one.',
            style: context.bodyMuted,
          ),
          const SizedBox(height: Space.lg),
          SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Instant')),
              ButtonSegment(value: 60, label: Text('60×')),
              ButtonSegment(value: 10, label: Text('10×')),
            ],
            selected: {_speedUp},
            onSelectionChanged: (s) => setState(() => _speedUp = s.first),
          ),
          const SizedBox(height: Space.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sentiment_satisfied_alt),
            title: const Text('Clean commute'),
            subtitle: const Text('Synthetic, 20 minutes, nothing to roast'),
            onTap: () => Navigator.pop(
              context,
              _SimChoice(_SimKind.clean, speedUp: _speedUp),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.local_fire_department_outlined),
            title: const Text('Messy commute'),
            subtitle: const Text('Synthetic, speeding, a slam and phone use'),
            onTap: () => Navigator.pop(
              context,
              _SimChoice(_SimKind.messy, speedUp: _speedUp),
            ),
          ),
          const SizedBox(height: Space.xl),
          const Kicker('From an installed pack'),
          const SizedBox(height: Space.md),
          if (widget.packs.isEmpty)
            Text(
              'Install a speed-limit pack first (Settings › Speed-limit packs).',
              style: context.caption,
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
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lat,
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: TextField(
                    controller: _lon,
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Text('Speeding', style: context.body),
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
            const SizedBox(height: Space.md),
            PrimaryButton(
              label: 'Drive from here',
              icon: Icons.route,
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
            ),
          ],
        ],
      ),
    );
  }
}
