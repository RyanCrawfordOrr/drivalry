import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter/material.dart';

import '../../data/models/trip_score_view.dart';
import '../../widgets/units.dart';

/// Plain one-line text for one engine event, e.g. "41 in a 25 for 90 s on
/// Elm St" or "Hard brake at 40 mph". No m/s², no jargon (docs/12 §6).
String describeEvent(TripEventView e, SpeedUnits units) {
  switch (e.kind) {
    case EventKind.speeding:
      final limit = e.limitMps;
      final road = _road(e);
      final where = road == null ? '' : ' on $road';
      final max = e.maxSpeedMps ?? 0;
      if (limit == null || limit.isNaN) {
        return '${formatSpeed(max, units)} for ${formatDuration(e.durationS)}$where';
      }
      return '${formatSpeed(max, units, withUnit: false)} in a '
          '${formatSpeed(limit, units, withUnit: false)} for '
          '${formatDuration(e.durationS)}$where';
    case EventKind.harshBrake:
      return '${_intensity(e.severity)} brake at '
          '${formatSpeed(_speedAtStart(e), units)}';
    case EventKind.harshAccel:
      return '${_intensity(e.severity)} acceleration from '
          '${formatSpeed(_speedAtStart(e), units)}';
    case EventKind.hardCorner:
      return '${_intensity(e.severity)} corner at '
          '${formatSpeed(_speedAtStart(e), units)}';
    case EventKind.phoneHandling:
      final n = (e.detail['interactions'] as num?)?.toInt() ?? 1;
      final times = n == 1 ? 'once' : '$n times';
      return 'Phone picked up $times, ${formatDuration(e.durationS)} '
          'at up to ${formatSpeed(e.maxSpeedMps ?? 0, units)}';
    case EventKind.idling:
      return 'Engine idling for ${formatDuration(e.durationS)}';
    case EventKind.highSpeedCruise:
      return 'Cruised at ${formatSpeed(e.maxSpeedMps ?? 0, units)} '
          'for ${formatDuration(e.durationS)}';
  }
}

/// The road name, or a plain description of the road class; null when the
/// engine knows neither (the sentence then simply has no "on …").
String? _road(TripEventView e) {
  final name = e.roadName;
  if (name != null && name.isNotEmpty) return name;
  return switch (e.detail['roadClass']) {
    'motorway' || 'trunk' => 'the highway',
    'residential' => 'a residential street',
    _ => null,
  };
}

double _speedAtStart(TripEventView e) =>
    (e.detail['speedAtStart'] as num?)?.toDouble() ?? 0;

/// "Hard" for the everyday event, "Very hard" once the engine rates it major
/// or worse. Replaces the raw m/s² figure.
String _intensity(Severity s) => switch (s) {
  Severity.minor || Severity.moderate => 'Hard',
  Severity.major || Severity.severe || Severity.reckless => 'Very hard',
};

/// Short label for an event kind. "Hard" everywhere, never "Harsh".
String eventTitle(EventKind kind) => switch (kind) {
  EventKind.speeding => 'Speeding',
  EventKind.harshBrake => 'Hard brake',
  EventKind.harshAccel => 'Hard acceleration',
  EventKind.hardCorner => 'Hard corner',
  EventKind.phoneHandling => 'Phone use',
  EventKind.idling => 'Idling',
  EventKind.highSpeedCruise => 'Fast cruise',
};

IconData eventIcon(EventKind kind) => switch (kind) {
  EventKind.speeding => Icons.speed,
  EventKind.harshBrake => Icons.do_not_step,
  EventKind.harshAccel => Icons.rocket_launch_outlined,
  EventKind.hardCorner => Icons.turn_sharp_right,
  EventKind.phoneHandling => Icons.phone_android,
  EventKind.idling => Icons.hourglass_bottom,
  EventKind.highSpeedCruise => Icons.local_gas_station,
};

Color severityColor(Severity s, ColorScheme scheme) => switch (s) {
  Severity.minor => const Color(0xFFF1C40F),
  Severity.moderate => const Color(0xFFE67E22),
  Severity.major || Severity.severe => const Color(0xFFE74C3C),
  Severity.reckless => scheme.error,
};

String severityLabel(Severity s) => switch (s) {
  Severity.minor => 'Minor',
  Severity.moderate => 'Moderate',
  Severity.major => 'Major',
  Severity.severe => 'Severe',
  Severity.reckless => 'Reckless',
};
