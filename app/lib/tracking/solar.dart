import 'dart:math' as math;

import 'package:drivalry_scoring/drivalry_scoring.dart' show GpsSample;

/// Sun position maths (NOAA Solar Calculator algorithm). Used for the night
/// fraction the scoring context wants, with no network and no third party.
abstract final class Solar {
  /// Sun elevation above the horizon in degrees at [utc] for a location.
  /// Negative when the sun is below the horizon; civil twilight ends at -6°.
  static double elevationDeg(DateTime utc, double lat, double lon) {
    final jd = _julianDay(utc.toUtc());
    final t = (jd - 2451545.0) / 36525.0; // Julian centuries since J2000

    final l0 = _norm360(280.46646 + t * (36000.76983 + t * 0.0003032));
    final m = _rad(357.52911 + t * (35999.05029 - 0.0001537 * t));
    final e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    final c =
        math.sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        math.sin(2 * m) * (0.019993 - 0.000101 * t) +
        math.sin(3 * m) * 0.000289;
    final trueLon = l0 + c;
    final omega = _rad(125.04 - 1934.136 * t);
    final apparentLon = trueLon - 0.00569 - 0.00478 * math.sin(omega);

    final obliq0 =
        23.0 +
        (26.0 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60.0) /
            60.0;
    final obliq = obliq0 + 0.00256 * math.cos(omega);
    final obliqR = _rad(obliq);

    final decl = math.asin(math.sin(obliqR) * math.sin(_rad(apparentLon)));

    final y = math.tan(obliqR / 2) * math.tan(obliqR / 2);
    final l0r = _rad(l0);
    final eqTime =
        4 *
        _deg(
          y * math.sin(2 * l0r) -
              2 * e * math.sin(m) +
              4 * e * y * math.sin(m) * math.cos(2 * l0r) -
              0.5 * y * y * math.sin(4 * l0r) -
              1.25 * e * e * math.sin(2 * m),
        ); // minutes

    final minutesUtc = utc.hour * 60 + utc.minute + utc.second / 60.0;
    final trueSolarTime = (minutesUtc + eqTime + 4 * lon) % 1440;
    var hourAngle = trueSolarTime / 4 - 180;
    if (hourAngle < -180) hourAngle += 360;

    final latR = _rad(lat);
    final cosZenith =
        math.sin(latR) * math.sin(decl) +
        math.cos(latR) * math.cos(decl) * math.cos(_rad(hourAngle));
    final zenith = _deg(math.acos(cosZenith.clamp(-1.0, 1.0)));
    return 90 - zenith;
  }

  /// True when it is "night" for scoring: the sun is below civil twilight.
  static bool isNight(DateTime utc, double lat, double lon) =>
      elevationDeg(utc, lat, lon) < -6;

  /// Fraction of the trip's samples taken at night. Evaluates one sample per
  /// minute (sun position moves 0.25° a minute at most, far below what
  /// matters) and returns 0 for an empty trip.
  static double nightFraction(List<GpsSample> samples) {
    if (samples.isEmpty) return 0;
    var night = 0;
    var total = 0;
    var lastMinute = -1;
    var lastIsNight = false;
    for (final s in samples) {
      final minute = s.t ~/ 60000;
      if (minute != lastMinute) {
        lastMinute = minute;
        lastIsNight = isNight(
          DateTime.fromMillisecondsSinceEpoch(s.t, isUtc: true),
          s.lat,
          s.lon,
        );
      }
      if (lastIsNight) night++;
      total++;
    }
    return night / total;
  }

  /// First minute on [dayUtc] (a UTC date) when the sun crosses below the
  /// horizon at a location, scanning at one-minute resolution. Null for
  /// polar day/night. Mostly for tests and diagnostics.
  static DateTime? sunsetUtc(DateTime dayUtc, double lat, double lon) {
    final start = DateTime.utc(dayUtc.year, dayUtc.month, dayUtc.day);
    var prev = elevationDeg(start, lat, lon);
    for (var m = 1; m <= 1440; m++) {
      final t = start.add(Duration(minutes: m));
      final e = elevationDeg(t, lat, lon);
      if (prev >= -0.833 && e < -0.833) return t;
      prev = e;
    }
    return null;
  }

  static double _julianDay(DateTime utc) {
    var y = utc.year;
    var mo = utc.month;
    final d =
        utc.day + (utc.hour + (utc.minute + utc.second / 60.0) / 60.0) / 24.0;
    if (mo <= 2) {
      y -= 1;
      mo += 12;
    }
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    return (365.25 * (y + 4716)).floor() +
        (30.6001 * (mo + 1)).floor() +
        d +
        b -
        1524.5;
  }

  static double _norm360(double v) {
    final r = v % 360;
    return r < 0 ? r + 360 : r;
  }

  static double _rad(double deg) => deg * math.pi / 180;
  static double _deg(double rad) => rad * 180 / math.pi;
}
