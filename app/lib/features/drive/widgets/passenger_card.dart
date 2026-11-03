import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';

import '../../../data/db/database.dart';
import '../../../widgets/units.dart';
import 'trip_card.dart';

/// "Were you the passenger?" for a trip that has not been confirmed yet.
/// The hinted answer is the filled button (docs/01 §4.1).
class PassengerCard extends StatelessWidget {
  const PassengerCard({
    super.key,
    required this.trip,
    required this.units,
    required this.onAnswer,
  });

  final Trip trip;
  final SpeedUnits units;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hintPassenger = trip.isPassenger ?? trip.passengerHint;
    final detail = [
      tripDateLabel(trip),
      formatDistance(trip.distanceM, units),
      if (trip.vehicleLabel != null) trip.vehicleLabel!,
    ].join(' · ');
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Were you the passenger?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                if (hintPassenger)
                  FilledButton(
                    onPressed: () => onAnswer(true),
                    child: const Text('Yes, passenger'),
                  )
                else
                  OutlinedButton(
                    onPressed: () => onAnswer(true),
                    child: const Text('Yes, passenger'),
                  ),
                const SizedBox(width: 8),
                if (!hintPassenger)
                  FilledButton(
                    onPressed: () => onAnswer(false),
                    child: const Text('No, I drove'),
                  )
                else
                  OutlinedButton(
                    onPressed: () => onAnswer(false),
                    child: const Text('No, I drove'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
