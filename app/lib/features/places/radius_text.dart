import 'package:drivalry_scoring/drivalry_scoring.dart' show SpeedUnits;

/// A place's radius in the person's units: feet to the nearest ten where
/// speeds are in mph, metres otherwise (docs/12 §6: never metres in copy
/// for mph people).
String radiusText(double metres, SpeedUnits units) {
  if (units == SpeedUnits.mph) {
    final ft = metres * 3.28084;
    return '${(ft / 10).round() * 10} ft';
  }
  return '${metres.round()} m';
}
