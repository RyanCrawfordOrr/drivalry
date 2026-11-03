import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;

import '../tracking/tracking_models.dart';
import '../widgets/units.dart';
import 'car_snapshot.dart';

/// The text of the Android foreground notification while a trip records
/// (docs/04 §3 "Without Android Auto"). Dart owns the words so they match
/// the Drive tab; `TrackingService` only displays them.
class OngoingNotificationLine {
  const OngoingNotificationLine({
    required this.title,
    required this.text,
    this.subText,
    this.passengerAction = false,
    this.tripId,
  });

  final String title;
  final String text;

  /// Secondary line, e.g. the convoy.
  final String? subText;

  /// Whether to offer the "Passenger" action (active trip, not yet marked).
  final bool passengerAction;
  final String? tripId;

  Map<String, Object?> toWire() => {
    'title': title,
    'text': text,
    'subText': subText,
    'passengerAction': passengerAction,
    'tripId': tripId,
  };

  @override
  bool operator ==(Object other) =>
      other is OngoingNotificationLine &&
      other.title == title &&
      other.text == text &&
      other.subText == subText &&
      other.passengerAction == passengerAction &&
      other.tripId == tripId;

  @override
  int get hashCode =>
      Object.hash(title, text, subText, passengerAction, tripId);

  @override
  String toString() => 'OngoingNotificationLine($text)';
}

/// Builds the line for a snapshot, or null when no trip is in progress (the
/// service is not running then, so there is nothing to update).
///
/// Examples: "Recording · Limit 35 · 31 mph · Clean so far",
/// "Recording · 41 mph · No limit data here", "Recording · Passenger · not
/// scored", "Looks like a drive · confirming".
OngoingNotificationLine? ongoingNotificationFor(CarSnapshot s) {
  final d = s.drive;
  switch (d.phase) {
    case TrackingPhase.idle:
      return null;
    case TrackingPhase.tentative:
      return OngoingNotificationLine(
        title: 'Drivalry',
        text: 'Looks like a drive · confirming',
        subText: _convoyLine(s),
        tripId: d.tripId,
      );
    case TrackingPhase.active:
      final parts = <String>['Recording'];
      if (d.passenger) {
        parts.add('Passenger · not scored');
      } else {
        if (d.posted != null) parts.add('Limit ${d.posted}');
        final speed = d.speedMps;
        if (speed != null) parts.add(formatSpeed(speed, _units(s, d)));
        parts.add(d.statusText(_units(s, d)));
      }
      return OngoingNotificationLine(
        title: 'Drivalry',
        text: parts.join(' · '),
        subText: _convoyLine(s),
        passengerAction: !d.passenger,
        tripId: d.tripId,
      );
  }
}

/// Speeds follow the limit's posted unit when one is known, so "Limit 35"
/// and "31 mph" never disagree; otherwise the user's units setting.
SpeedUnits _units(CarSnapshot s, CarDrive d) {
  if (d.posted != null) {
    return d.limitUnit == 'km/h' ? SpeedUnits.kmh : SpeedUnits.mph;
  }
  return s.units;
}

String? _convoyLine(CarSnapshot s) {
  final c = s.convoy;
  if (c == null || !c.isActive) return null;
  final n = c.members.length;
  return 'Convoy · ${c.name} · $n ${n == 1 ? 'car' : 'cars'}';
}
