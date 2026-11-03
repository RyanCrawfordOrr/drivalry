/// One road way as stored in a pack tile (`docs/07-pack-format.md` §2–§5).
library;

import 'package:drivalry_scoring/drivalry_scoring.dart' show RoadClass;

/// Where a way's speed limit came from. Determines confidence.
enum LimitSource {
  /// No limit known. Confidence 0.
  none,

  /// A numeric `maxspeed` tag. Confidence 0.9.
  tag,

  /// Implied by `maxspeed:type`, a zone, or a class default. Confidence 0.5.
  implied,
}

/// m/s per mph.
const double mphToMps = 0.44704;

/// Road class codes 0–8 in tile order, mapped to the scoring engine's enum.
const List<RoadClass> roadClassByCode = [
  RoadClass.motorway,
  RoadClass.trunk,
  RoadClass.primary,
  RoadClass.secondary,
  RoadClass.tertiary,
  RoadClass.residential,
  RoadClass.service,
  RoadClass.unclassified,
  RoadClass.unknown,
];

/// Inverse of [roadClassByCode].
int roadClassCode(RoadClass c) => roadClassByCode.indexOf(c);

/// A decoded way: metadata plus its simplified polyline.
class PackWay {
  PackWay({
    required this.id,
    required this.roadClass,
    required this.lats,
    required this.lons,
    this.name,
    this.maxForward,
    this.maxBackward,
    this.mph = false,
    this.oneway = 0,
    this.roundabout = false,
    this.source = LimitSource.none,
  }) : assert(lats.length == lons.length, 'lats/lons length mismatch'),
       assert(lats.length >= 2, 'a way needs at least two points') {
    var minLa = lats[0], maxLa = lats[0], minLo = lons[0], maxLo = lons[0];
    for (var i = 1; i < lats.length; i++) {
      final la = lats[i], lo = lons[i];
      if (la < minLa) minLa = la;
      if (la > maxLa) maxLa = la;
      if (lo < minLo) minLo = lo;
      if (lo > maxLo) maxLo = lo;
    }
    minLat = minLa;
    maxLat = maxLa;
    minLon = minLo;
    maxLon = maxLo;
  }

  /// OSM way id.
  final int id;
  final RoadClass roadClass;

  /// Street name, or null.
  final String? name;

  /// Posted limit in point order, as an integer in the posted unit, or null.
  final int? maxForward;

  /// Posted limit against point order when it differs from [maxForward].
  /// Null means "same as forward" (or also unknown).
  final int? maxBackward;

  /// True when [maxForward] and [maxBackward] are in mph, false for km/h.
  final bool mph;

  /// 0 two-way, 1 oneway in point order, 2 oneway against point order.
  final int oneway;
  final bool roundabout;
  final LimitSource source;

  /// Polyline latitudes, degrees. Same length as [lons], at least 2.
  final List<double> lats;

  /// Polyline longitudes, degrees.
  final List<double> lons;

  /// Bounding box, degrees. Used for fast candidate rejection.
  late final double minLat;
  late final double maxLat;
  late final double minLon;
  late final double maxLon;

  /// Number of polyline points.
  int get pointCount => lats.length;

  /// 0.9 for a numeric tag, 0.5 for an implied limit, 0 for none.
  double get confidence => switch (source) {
    LimitSource.tag => 0.9,
    LimitSource.implied => 0.5,
    LimitSource.none => 0,
  };

  /// True when travel in the given direction is allowed on this way.
  bool allows({required bool forward}) =>
      oneway == 0 || (forward ? oneway == 1 : oneway == 2);

  /// The posted integer for the direction of travel, for display.
  ///
  /// In point order this is [maxForward]. Against point order it is
  /// [maxBackward] when set, otherwise [maxForward].
  int? postedLimit({required bool forward}) =>
      forward ? maxForward : (maxBackward ?? maxForward);

  /// The limit for the direction of travel in m/s, or null when unknown.
  double? limitMps({required bool forward}) {
    final posted = postedLimit(forward: forward);
    if (posted == null) return null;
    return mph ? posted * mphToMps : posted / 3.6;
  }

  /// Unit label for display.
  String get unitLabel => mph ? 'mph' : 'km/h';

  @override
  String toString() =>
      'PackWay($id ${roadClass.name} ${name ?? '-'} '
      '${maxForward ?? '-'}${maxBackward == null ? '' : '/$maxBackward'} '
      '$unitLabel ow=$oneway pts=${lats.length})';
}
