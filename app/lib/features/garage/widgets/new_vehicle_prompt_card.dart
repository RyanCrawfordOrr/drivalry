import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../data/garage/vehicle_matcher.dart';
import '../../../data/repos/garage_repo.dart';

/// "New car audio 'X'. Add it to the Garage?" One tile, shown until answered.
class NewVehiclePromptCard extends ConsumerWidget {
  const NewVehiclePromptCard({super.key, required this.prompt});

  final VehiclePrompt prompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final vehicles = ref.watch(vehiclesProvider).value ?? const <Vehicle>[];
    final repo = ref.read(garageRepoProvider);
    return Tile(
      key: const Key('vehicle-prompt-card'),
      tone: TileTone.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bluetooth_audio, color: scheme.primary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  "New car audio '${prompt.name}'. Add it to the Garage?",
                  style: context.body.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Trips in your own cars are scored for you. Unknown cars count '
            'as a passenger ride until you say otherwise.',
            style: context.caption,
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: () {
                  Haptics.success();
                  repo.acceptPrompt(prompt);
                },
                child: const Text('Add'),
              ),
              if (vehicles.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'Pick one of your cars',
                  onSelected: (id) => repo.acceptPrompt(prompt, vehicleId: id),
                  itemBuilder: (_) => [
                    for (final v in vehicles)
                      PopupMenuItem(value: v.id, child: Text(v.name)),
                  ],
                  child: const Chip(label: Text('It is one of mine')),
                ),
              TextButton(
                onPressed: () => repo.dismissPrompt(prompt),
                child: const Text("It's not mine"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
