import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:flutter/material.dart';

import '../../data/models/trip_score_view.dart';
import '../../widgets/units.dart';

/// Human text for one engine event, e.g. "41 in a 25 for 90 s on Elm St".
String describeEvent(TripEventView e, SpeedUnits units) {
  switch (e.kind) {
    case EventKind.speeding:
      final limit = e.limitMps;
      final road =
          e.roadName ??
          switch (e.detail['roadClass']) {
            'motorway' || 'trunk' => 'the highway',
            'residential' => 'a residential street',
            _ => 'that road',
          };
      final max = e.maxSpeedMps ?? 0;
      if (limit == null || limit.isNaN) {
        return '${formatSpeed(max, units)} for ${formatDuration(e.durationS)} on $road';
      }
      return '${formatSpeed(max, units, withUnit: false)} in a '
          '${formatSpeed(limit, units, withUnit: false)} for '
          '${formatDuration(e.durationS)} on $road';
    case EventKind.harshBrake:
      return 'Hard brake, ${_g(e.peak)} at ${formatSpeed(_speedAtStart(e), units)}';
    case EventKind.harshAccel:
      return 'Hard acceleration, ${_g(e.peak)} from ${formatSpeed(_speedAtStart(e), units)}';
    case EventKind.hardCorner:
      return 'Hard corner, ${_g(e.peak)} at ${formatSpeed(_speedAtStart(e), units)}';
    case EventKind.phoneHandling:
      final n = (e.detail['interactions'] as num?)?.toInt() ?? 1;
      return 'Phone handled ${n == 1 ? 'once' : '$n times'} over '
          '${formatDuration(e.durationS)} at up to ${formatSpeed(e.maxSpeedMps ?? 0, units)}';
    case EventKind.idling:
      return 'Idled for ${formatDuration(e.durationS)}';
    case EventKind.highSpeedCruise:
      return 'Cruised at ${formatSpeed(e.maxSpeedMps ?? 0, units)} for ${formatDuration(e.durationS)}';
  }
}

double _speedAtStart(TripEventView e) =>
    (e.detail['speedAtStart'] as num?)?.toDouble() ?? 0;

String _g(double? peak) => '${(peak ?? 0).toStringAsFixed(1)} m/s²';

/// Short label for an event kind.
String eventTitle(EventKind kind) => switch (kind) {
  EventKind.speeding => 'Speeding',
  EventKind.harshBrake => 'Harsh brake',
  EventKind.harshAccel => 'Harsh acceleration',
  EventKind.hardCorner => 'Hard corner',
  EventKind.phoneHandling => 'Phone handling',
  EventKind.idling => 'Idling',
  EventKind.highSpeedCruise => 'High-speed cruise',
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
