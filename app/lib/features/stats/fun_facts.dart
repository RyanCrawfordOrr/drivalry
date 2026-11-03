import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/garage/fuel_math.dart' show formatEconomy;
import '../../data/stats/stats_engine.dart';
import '../../widgets/units.dart';

/// One number with its words: the unit the Stats screen, the Wrapped and
/// the share cards are built from.
class FunFact {
  const FunFact({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    this.shareable = true,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;

  /// False for facts that would leak a place: road names, place labels,
  /// friends' names. They stay on the screen and off the image.
  final bool shareable;
}

class FactSection {
  const FactSection({required this.title, required this.facts});
  final String title;
  final List<FunFact> facts;
}

String formatHours(double seconds) {
  final h = seconds / 3600;
  if (h >= 100) return '${h.round()} h';
  if (h >= 1) return '${h.toStringAsFixed(1)} h';
  return '${(seconds / 60).round()} min';
}

String formatMoney(double amount) => NumberFormat.simpleCurrency(
  decimalDigits: amount >= 100 ? 0 : 2,
).format(amount);

String formatAltitude(double metres, SpeedUnits units) =>
    units == SpeedUnits.mph
    ? '${(metres * 3.28084).round()} ft'
    : '${metres.round()} m';

String formatClock(DateTime t) => DateFormat.jm().format(t);

String formatDay(DateTime d) => DateFormat.MMMd().format(d);

String formatEconomyFor(double? lPer100km, SpeedUnits units) =>
    lPer100km == null
    ? 'default economy'
    : formatEconomy(lPer100km, useMpg: units == SpeedUnits.mph);

String scoreText(double? score) => score == null ? '–' : '${score.round()}';

/// The three or four numbers on the shareable headline card.
List<FunFact> headlineFacts(DriverStats s, SpeedUnits units) {
  final t = s.totals;
  final facts = <FunFact>[
    FunFact(
      label: 'Trips',
      value: '${t.trips}',
      hint: '${t.cleanTrips} clean',
      icon: Icons.route_outlined,
    ),
    FunFact(
      label: 'Distance',
      value: formatDistance(t.distanceM, units),
      hint: formatHours(t.movingS),
      icon: Icons.straighten,
    ),
    FunFact(
      label: 'Average score',
      value: scoreText(t.averageScore),
      hint: t.bestScore == null ? 'No scored trips' : 'Best ${t.bestScore}',
      icon: Icons.speed_outlined,
    ),
  ];
  if (s.geography.stateCodes.isNotEmpty) {
    facts.add(
      FunFact(
        label: 'States',
        value: '${s.geography.stateCodes.length}',
        hint: s.geography.stateCodes.take(6).join(' '),
        icon: Icons.public,
      ),
    );
  }
  return facts;
}
