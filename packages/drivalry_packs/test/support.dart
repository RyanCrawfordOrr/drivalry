/// Helpers for building roads and GPS traces in tests.
library;

import 'package:drivalry_scoring/drivalry_scoring.dart';
import 'package:drivalry_packs/drivalry_packs.dart';

/// Reference point: a flat spot near the White House.
const double baseLat = 38.8977;
const double baseLon = -77.0365;

/// A straight road from (lat, lon) along [bearingDeg] for [lengthM], with an
/// intermediate point every [stepM] so the polyline has several segments.
PackWay road(
  int id, {
  required double lat,
  required double lon,
  required double bearingDeg,
  required double lengthM,
  int? limit,
  int? limitBack,
  bool mph = true,
  int oneway = 0,
  String? name,
  RoadClass roadClass = RoadClass.residential,
  double stepM = 250,
  LimitSource? source,
}) {
  final lats = <double>[lat];
  final lons = <double>[lon];
  var d = stepM;
  while (d < lengthM) {
    final p = destination(lat, lon, bearingDeg, d);
    lats.add(p.lat);
    lons.add(p.lon);
    d += stepM;
  }
  final end = destination(lat, lon, bearingDeg, lengthM);
  lats.add(end.lat);
  lons.add(end.lon);
  return PackWay(
    id: id,
    roadClass: roadClass,
    name: name,
    maxForward: limit,
    maxBackward: limitBack,
    mph: mph,
    oneway: oneway,
    source:
        source ??
        (limit != null || limitBack != null
            ? LimitSource.tag
            : LimitSource.none),
    lats: lats,
    lons: lons,
  );
}

/// [count] fixes at 1 Hz starting at (lat, lon) travelling along
/// [bearingDeg] at [speed] m/s. The reported heading is [bearingDeg] unless
/// [heading] is given; [headingNull] drops it entirely.
List<GpsSample> trace({
  required double lat,
  required double lon,
  required double bearingDeg,
  required int count,
  double speed = 15,
  double accuracy = 5,
  double? heading,
  bool headingNull = false,
  int startT = 1_700_000_000_000,
  int startIdx = 0,
}) {
  return List.generate(count, (i) {
    final p = destination(lat, lon, bearingDeg, speed * i);
    return GpsSample(
      t: startT + (startIdx + i) * 1000,
      lat: p.lat,
      lon: p.lon,
      speed: speed,
      accuracy: accuracy,
      heading: headingNull ? null : (heading ?? bearingDeg),
    );
  });
}

/// Concatenates traces so timestamps stay 1 Hz across legs.
List<GpsSample> legs(List<List<GpsSample>> parts) {
  final out = <GpsSample>[];
  var t = parts.first.first.t;
  for (final part in parts) {
    for (final s in part) {
      out.add(
        GpsSample(
          t: t,
          lat: s.lat,
          lon: s.lon,
          speed: s.speed,
          accuracy: s.accuracy,
          heading: s.heading,
          altitude: s.altitude,
        ),
      );
      t += 1000;
    }
  }
  return out;
}

/// Asserts that segments cover 0..n-1 exactly once, in order.
void expectTiles(List<RoadSegment> segments, int n) {
  if (n == 0) {
    if (segments.isNotEmpty) throw StateError('segments for empty trace');
    return;
  }
  var expected = 0;
  for (final s in segments) {
    if (s.fromIdx != expected) {
      throw StateError('segment starts at ${s.fromIdx}, expected $expected');
    }
    if (s.toIdx < s.fromIdx) throw StateError('segment ends before it starts');
    expected = s.toIdx + 1;
  }
  if (expected != n) throw StateError('segments end at $expected, expected $n');
}
