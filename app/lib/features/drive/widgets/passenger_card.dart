import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';

import '../../../app/ui/ui.dart';
import '../../../data/db/database.dart';
import '../../../widgets/units.dart';
import 'trip_card.dart';

/// "Were you the passenger?" for a trip that has not been confirmed yet, as
/// one tile in the Drive sheet. The hinted answer is the primary button
/// (docs/01 §4.1).
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
    final hintPassenger = trip.isPassenger ?? trip.passengerHint;
    final detail = [
      tripDateLabel(trip),
      formatDistance(trip.distanceM, units),
      if (trip.vehicleLabel != null) trip.vehicleLabel!,
    ].join(' · ');
    return Tile(
      key: const Key('passenger-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Were you the passenger?', style: context.title),
          const SizedBox(height: Space.xs),
          Text(detail, style: context.caption),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: hintPassenger
                    ? PrimaryButton(
                        label: 'Passenger',
                        onPressed: () => onAnswer(true),
                      )
                    : SecondaryButton(
                        label: 'Passenger',
                        onPressed: () => onAnswer(true),
                      ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: hintPassenger
                    ? SecondaryButton(
                        label: 'I drove',
                        onPressed: () => onAnswer(false),
                      )
                    : PrimaryButton(
                        label: 'I drove',
                        onPressed: () => onAnswer(false),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
