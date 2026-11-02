/// Synthetic trip builder. Mirrors `packages/scoring/src/synthetic.ts`.
///
/// Used by tests and by the mobile app's mock tracking provider. Produces 1 Hz GPS samples
/// along a bearing with gentle ramps between legs unless told otherwise.
library;

import 'dart:math' as math;

import 'constants.dart';
import 'geo.dart';
import 'types.dart';

class LegSpec {
  const LegSpec({
    required this.durationS,
    required this.speedMph,
    this.limitMph,
    this.confidence,
    this.roadClass,
    this.name,
    this.rampAccel,
    this.turnRateDegS,
    this.accuracy,
  });

  factory LegSpec.fromJson(Map<String, dynamic> json) => LegSpec(
    durationS: (json['durationS'] as num).toInt(),
    speedMph: (json['speedMph'] as num).toDouble(),
    limitMph: (json['limitMph'] as num?)?.toDouble(),
    confidence: (json['confidence'] as num?)?.toDouble(),
    roadClass: json['roadClass'] == null
        ? null
        : RoadClass.fromWire(json['roadClass'] as String),
    name: json['name'] as String?,
    rampAccel: (json['rampAccel'] as num?)?.toDouble(),
    turnRateDegS: (json['turnRateDegS'] as num?)?.toDouble(),
    accuracy: (json['accuracy'] as num?)?.toDouble(),
  );

  /// Whole seconds at 1 Hz (the TS type is `number`; fractional legs are not meaningful).
  final int durationS;
  final double speedMph;

  /// Posted limit in mph. Null for "unknown".
  final double? limitMph;

  /// Segment confidence. Defaults to 0.9 when a limit is given, 0 otherwise.
  final double? confidence;
  final RoadClass? roadClass;
  final String? name;

  /// Max |accel| used to reach this leg's speed from the previous one. Default 1.5 m/s² (gentle).
  final double? rampAccel;

  /// Degrees per second of heading change applied throughout the leg (for cornering tests).
  final double? turnRateDegS;

  /// Override GPS accuracy for this leg (metres).
  final double? accuracy;

  Map<String, Object?> toJson() => {
    'durationS': durationS,
    'speedMph': speedMph,
    if (limitMph != null) 'limitMph': limitMph,
    if (confidence != null) 'confidence': confidence,
    if (roadClass != null) 'roadClass': roadClass!.wire,
    if (name != null) 'name': name,
    if (rampAccel != null) 'rampAccel': rampAccel,
    if (turnRateDegS != null) 'turnRateDegS': turnRateDegS,
    if (accuracy != null) 'accuracy': accuracy,
  };
}

/// A phone event at an offset (whole seconds from trip start).
class PhoneEventAt {
  const PhoneEventAt({required this.atS, this.kind});

  factory PhoneEventAt.fromJson(Map<String, dynamic> json) => PhoneEventAt(
    atS: (json['atS'] as num).toInt(),
    kind: json['kind'] == null
        ? null
        : PhoneEventKind.fromWire(json['kind'] as String),
  );

  final int atS;

  /// Defaults to `interaction`.
  final PhoneEventKind? kind;

  Map<String, Object?> toJson() => {
    'atS': atS,
    if (kind != null) 'kind': kind!.wire,
  };
}

class SyntheticSpec {
  const SyntheticSpec({
    this.id,
    this.startT,
    this.start,
    this.headingDeg,
    required this.legs,
    this.phoneEventsAt,
    this.accuracy,
    this.context,
  });

  factory SyntheticSpec.fromJson(Map<String, dynamic> json) {
    final start = json['start'] as Map<String, dynamic>?;
    return SyntheticSpec(
      id: json['id'] as String?,
      startT: (json['startT'] as num?)?.toInt(),
      start: start == null
          ? null
          : (
              lat: (start['lat'] as num).toDouble(),
              lon: (start['lon'] as num).toDouble(),
            ),
      headingDeg: (json['headingDeg'] as num?)?.toDouble(),
      legs: [
        for (final l in json['legs'] as List)
          LegSpec.fromJson(l as Map<String, dynamic>),
      ],
      phoneEventsAt: json['phoneEventsAt'] == null
          ? null
          : [
              for (final p in json['phoneEventsAt'] as List)
                PhoneEventAt.fromJson(p as Map<String, dynamic>),
            ],
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      context: json['context'] == null
          ? null
          : TripContext.fromJson(json['context'] as Map<String, dynamic>),
    );
  }

  final String? id;

  /// Epoch ms. Defaults to [defaultSyntheticStartT].
  final int? startT;
  final ({double lat, double lon})? start;
  final double? headingDeg;
  final List<LegSpec> legs;

  /// Phone events at offsets (seconds from trip start).
  final List<PhoneEventAt>? phoneEventsAt;
  final double? accuracy;
  final TripContext? context;

  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    if (startT != null) 'startT': startT,
    if (start != null) 'start': {'lat': start!.lat, 'lon': start!.lon},
    if (headingDeg != null) 'headingDeg': headingDeg,
    'legs': [for (final l in legs) l.toJson()],
    if (phoneEventsAt != null)
      'phoneEventsAt': [for (final p in phoneEventsAt!) p.toJson()],
    if (accuracy != null) 'accuracy': accuracy,
    if (context != null) 'context': context!.toJson(),
  };
}

/// `Date.UTC(2026, 10, 1, 17, 30, 0)`: 2026-11-01T17:30:00Z.
const int defaultSyntheticStartT = 1793554200000;

TripInput buildSyntheticTrip(SyntheticSpec spec) {
  final startT = spec.startT ?? defaultSyntheticStartT;
  var lat = spec.start?.lat ?? 36.1627;
  var lon = spec.start?.lon ?? -86.7816;
  var heading = spec.headingDeg ?? 90.0;
  var v = 0.0;
  var t = startT;
  var idx = 0;

  final samples = <GpsSample>[];
  final segments = <RoadSegment>[];

  void push(double accuracy) {
    samples.add(
      GpsSample(
        t: t,
        lat: lat,
        lon: lon,
        speed: v,
        accuracy: accuracy,
        heading: heading,
      ),
    );
    idx++;
  }

  push(spec.accuracy ?? 5);

  for (final leg in spec.legs) {
    final target = mphToMps(leg.speedMph);
    final ramp = leg.rampAccel ?? 1.5;
    final from = idx;
    for (var s = 0; s < leg.durationS; s++) {
      final dv = math.max(-ramp, math.min(ramp, target - v));
      v = math.max(0.0, v + dv);
      final turn = leg.turnRateDegS;
      // JS truthiness: a turn rate of 0 is skipped (which also leaves `heading` bit-identical).
      if (turn != null && turn != 0) {
        heading = (heading + turn + 360).remainder(360);
      }
      final next = destination(lat, lon, heading, v);
      lat = next.lat;
      lon = next.lon;
      t += 1000;
      push(leg.accuracy ?? spec.accuracy ?? 5);
    }
    final to = idx - 1;
    final limitMph = leg.limitMph;
    segments.add(
      RoadSegment(
        fromIdx: from,
        toIdx: to,
        speedLimit: limitMph == null ? null : mphToMps(limitMph),
        confidence: leg.confidence ?? (limitMph != null ? 0.9 : 0),
        roadClass:
            leg.roadClass ??
            (limitMph != null && limitMph >= 55
                ? RoadClass.motorway
                : RoadClass.residential),
        name: leg.name,
      ),
    );
  }

  final phoneEvents = spec.phoneEventsAt
      ?.map(
        (p) => PhoneEvent(
          t: startT + p.atS * 1000,
          kind: p.kind ?? PhoneEventKind.interaction,
        ),
      )
      .toList();

  return TripInput(
    id: spec.id ?? 'synthetic-$startT',
    samples: samples,
    segments: segments,
    phoneEvents: phoneEvents,
    context: spec.context,
  );
}

/// A clean 20-minute mixed trip. Handy default for mocks.
TripInput cleanCommute([String id = 'clean-commute']) => buildSyntheticTrip(
  SyntheticSpec(
    id: id,
    legs: const [
      LegSpec(
        durationS: 180,
        speedMph: 28,
        limitMph: 30,
        name: 'Elm St',
        roadClass: RoadClass.residential,
      ),
      LegSpec(
        durationS: 420,
        speedMph: 42,
        limitMph: 45,
        name: 'Route 9',
        roadClass: RoadClass.primary,
      ),
      LegSpec(
        durationS: 480,
        speedMph: 63,
        limitMph: 65,
        name: 'I-40',
        roadClass: RoadClass.motorway,
      ),
      LegSpec(
        durationS: 120,
        speedMph: 22,
        limitMph: 25,
        name: 'Maple Ave',
        roadClass: RoadClass.residential,
      ),
    ],
  ),
);

/// A trip with one of everything. Handy for UI mocks.
TripInput messyCommute([String id = 'messy-commute']) => buildSyntheticTrip(
  SyntheticSpec(
    id: id,
    legs: const [
      LegSpec(
        durationS: 120,
        speedMph: 38,
        limitMph: 25,
        name: 'Elm St',
        roadClass: RoadClass.residential,
      ),
      LegSpec(
        durationS: 300,
        speedMph: 44,
        limitMph: 45,
        name: 'Route 9',
        roadClass: RoadClass.primary,
      ),
      LegSpec(
        durationS: 5,
        speedMph: 10,
        limitMph: 45,
        name: 'Route 9',
        roadClass: RoadClass.primary,
        rampAccel: 5.5,
      ),
      LegSpec(
        durationS: 240,
        speedMph: 78,
        limitMph: 65,
        name: 'I-40',
        roadClass: RoadClass.motorway,
      ),
      LegSpec(
        durationS: 300,
        speedMph: 64,
        limitMph: 65,
        name: 'I-40',
        roadClass: RoadClass.motorway,
      ),
      LegSpec(
        durationS: 120,
        speedMph: 24,
        limitMph: 25,
        name: 'Maple Ave',
        roadClass: RoadClass.residential,
      ),
    ],
    phoneEventsAt: const [
      PhoneEventAt(atS: 500),
      PhoneEventAt(atS: 512),
      PhoneEventAt(atS: 530),
    ],
  ),
);
