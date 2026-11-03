import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/database.dart';
import '../../../data/garage/vehicle_matcher.dart';
import '../../../data/repos/garage_repo.dart';

/// "New car audio 'X'. Add it to the Garage?" One card, shown until answered.
class NewVehiclePromptCard extends ConsumerWidget {
  const NewVehiclePromptCard({super.key, required this.prompt});

  final VehiclePrompt prompt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vehicles = ref.watch(vehiclesProvider).value ?? const <Vehicle>[];
    final repo = ref.read(garageRepoProvider);
    return Card(
      key: const Key('vehicle-prompt-card'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth_audio, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "New car audio '${prompt.name}'. Add it to the Garage?",
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Trips in cars you own are scored for you. Unknown cars are '
              'treated as a passenger ride until you say otherwise.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => repo.acceptPrompt(prompt),
                  child: const Text('Add'),
                ),
                if (vehicles.isNotEmpty)
                  PopupMenuButton<String>(
                    onSelected: (id) =>
                        repo.acceptPrompt(prompt, vehicleId: id),
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
      ),
    );
  }
}
