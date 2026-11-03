/// Single-fix matcher for spoken cues and the live card.
library;

import 'dart:math' as math;

import 'package:drivalry_scoring/drivalry_scoring.dart' show GpsSample;

import 'geometry.dart';
import 'pack_source.dart';
import 'pack_way.dart';
import 'road_matcher.dart';
import 'tile_cache.dart';

/// The road a fix is on right now.
class RoadMatch {
  const RoadMatch({
    required this.way,
    required this.forward,
    required this.distanceM,
    required this.limitMps,
    required this.confidence,
  });

  final PackWay way;

  /// Travelling in the way's point order.
  final bool forward;
  final double distanceM;

  /// Limit for the direction of travel (override applied), m/s, or null.
  final double? limitMps;

  /// Confidence (override applied).
  final double confidence;

  /// Posted integer for display, or null.
  int? get postedLimit => way.postedLimit(forward: forward);

  String? get name => way.name;
}

/// Locates one fix at a time against a pack, keeping the previous match for
/// stickiness. Never touches the network; tiles come from the cache.
class LiveMatcher {
  LiveMatcher(
    PackSource source, {
    this.maxDistanceM = 35,
    this.switchMargin = 1.0,
    this.maxAccuracyM = 50,
    this.minHeadingSpeedMps = 2,
  }) : _cache = TileCache(source);

  final TileCache _cache;
  final double maxDistanceM;
  final double switchMargin;
  final double maxAccuracyM;
  final double minHeadingSpeedMps;
  RoadMatch? _last;

  /// The most recent match, if any.
  RoadMatch? get last => _last;

  /// Matches [fix]. Inaccurate fixes return the previous match unchanged.
  RoadMatch? locate(
    GpsSample fix, {
    Map<int, LimitOverride> overrides = const {},
  }) {
    if (fix.accuracy > maxAccuracyM) return _last;
    final h = fix.heading;
    final heading = (h != null && fix.speed >= minHeadingSpeedMps)
        ? normalizeHeading(h)
        : null;
    final candidates = scoreCandidates(
      _cache.waysNear(fix.lat, fix.lon),
      fix.lat,
      fix.lon,
      radiusM: math.max(maxDistanceM, fix.accuracy),
      heading: heading,
      currentWayId: _last?.way.id,
      currentForward: _last?.forward ?? true,
    );
    if (candidates.isEmpty) {
      _last = null;
      return null;
    }
    RoadCandidate chosen = candidates.first;
    final lastId = _last?.way.id;
    if (lastId != null && chosen.way.id != lastId) {
      for (final c in candidates) {
        if (c.way.id == lastId) {
          if (!(chosen.cost < c.cost - switchMargin)) chosen = c;
          break;
        }
      }
    }
    final ov = overrides[chosen.way.id];
    _last = RoadMatch(
      way: chosen.way,
      forward: chosen.forward,
      distanceM: chosen.distanceM,
      limitMps: ov?.limitMps ?? chosen.way.limitMps(forward: chosen.forward),
      confidence: ov?.confidence ?? chosen.way.confidence,
    );
    return _last;
  }

  /// Forgets the previous match (new trip).
  void reset() => _last = null;

  /// Drops cached tiles (pack swapped).
  void clearCache() {
    _cache.clear();
    _last = null;
  }
}
