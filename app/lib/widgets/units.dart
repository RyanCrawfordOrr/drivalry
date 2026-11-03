import 'dart:ui' show PlatformDispatcher;

import 'package:drivalry_scoring/drivalry_scoring.dart'
    show SpeedUnits, mpsToKmh, mpsToMph;

/// The `units` setting: follow the pack / locale, or force one.
enum UnitsSetting {
  auto,
  mph,
  kmh;

  static UnitsSetting fromWire(String? wire) => switch (wire) {
    'mph' => mph,
    'kmh' => kmh,
    _ => auto,
  };
}

/// Pack regions whose roads post limits in mph.
const Set<String> _mphRegionPrefixes = {
  'us-',
  'gb',
  'uk',
  'pr',
  'vi',
  'gu',
  'as',
};

/// Picks display units. `auto` follows the pack the trip was matched against
/// (US packs post in mph), then the device locale.
SpeedUnits resolveUnits(
  UnitsSetting setting, {
  String? packRegion,
  String? countryCode,
}) {
  switch (setting) {
    case UnitsSetting.mph:
      return SpeedUnits.mph;
    case UnitsSetting.kmh:
      return SpeedUnits.kmh;
    case UnitsSetting.auto:
      if (packRegion != null) {
        final r = packRegion.toLowerCase();
        return _mphRegionPrefixes.any(r.startsWith)
            ? SpeedUnits.mph
            : SpeedUnits.kmh;
      }
      final cc =
          (countryCode ?? PlatformDispatcher.instance.locale.countryCode ?? '')
              .toUpperCase();
      return const {'US', 'GB', 'LR', 'MM', 'PR', 'VI', 'GU', 'AS'}.contains(cc)
          ? SpeedUnits.mph
          : SpeedUnits.kmh;
  }
}

String unitLabel(SpeedUnits u) => u == SpeedUnits.mph ? 'mph' : 'km/h';

/// "43 mph" / "70 km/h".
String formatSpeed(double mps, SpeedUnits u, {bool withUnit = true}) {
  final v = u == SpeedUnits.mph ? mpsToMph(mps) : mpsToKmh(mps);
  final n = v.round().toString();
  return withUnit ? '$n ${unitLabel(u)}' : n;
}

/// "3.2 mi" / "12 km".
String formatDistance(double metres, SpeedUnits u) {
  if (u == SpeedUnits.mph) {
    final mi = metres / 1609.344;
    return mi < 10 ? '${mi.toStringAsFixed(1)} mi' : '${mi.round()} mi';
  }
  final km = metres / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// "1h 12m" / "9 min" / "45 s".
String formatElapsed(Duration d) {
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

/// "30 ft" / "10 m", for a GPS accuracy radius. Never metres in copy for
/// people who drive in miles (docs/12 §6).
String formatShortDistance(double metres, SpeedUnits u) {
  if (u == SpeedUnits.mph) {
    final ft = metres * 3.28084;
    if (ft < 1000) return '${((ft / 10).round() * 10).clamp(10, 990)} ft';
    return formatDistance(metres, u);
  }
  if (metres < 1000) return '${((metres / 5).round() * 5).clamp(5, 995)} m';
  return formatDistance(metres, u);
}
