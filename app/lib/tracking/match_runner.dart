import 'dart:isolate';

import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart'
    show GpsSample, RoadSegment;

/// Which pack to match against. [path] is a `.pack` file for the real app;
/// tests hand an in-memory pack to an [InlineMatchRunner] instead.
class PackRef {
  const PackRef({
    required this.region,
    required this.path,
    required this.version,
  });

  final String region;
  final String path;

  /// The pack's `osm_replication_timestamp`, stored on the trip.
  final String version;
}

/// The part of a [MatchResult] the finalizer keeps.
class MatchOutcome {
  const MatchOutcome({
    required this.segments,
    required this.limitCoverage,
    required this.matchedFraction,
  });

  factory MatchOutcome.fromResult(MatchResult r) => MatchOutcome(
    segments: r.segments,
    limitCoverage: r.limitCoverage,
    matchedFraction: r.matchedFraction,
  );

  final List<RoadSegment> segments;
  final double limitCoverage;
  final double matchedFraction;
}

/// Runs the road matcher for one trip.
abstract class MatchRunner {
  Future<MatchOutcome> run(
    List<GpsSample> samples,
    PackRef pack, {
    Map<int, LimitOverride> overrides = const {},
  });
}

/// Opens the pack and matches on a worker isolate so a long trip never
/// stalls the UI (docs/03 §3.4).
class IsolateMatchRunner implements MatchRunner {
  const IsolateMatchRunner({this.matcher = const RoadMatcher()});

  final RoadMatcher matcher;

  @override
  Future<MatchOutcome> run(
    List<GpsSample> samples,
    PackRef pack, {
    Map<int, LimitOverride> overrides = const {},
  }) {
    final path = pack.path;
    final m = matcher;
    return Isolate.run(() {
      final source = SqlitePack.open(path);
      try {
        return MatchOutcome.fromResult(
          m.match(samples, source, overrides: overrides),
        );
      } finally {
        source.close();
      }
    });
  }
}

/// Matches on the calling isolate against whatever [open] returns. For tests
/// (in-memory packs) and tiny traces.
class InlineMatchRunner implements MatchRunner {
  const InlineMatchRunner(this.open, {this.matcher = const RoadMatcher()});

  final PackSource Function(PackRef pack) open;
  final RoadMatcher matcher;

  @override
  Future<MatchOutcome> run(
    List<GpsSample> samples,
    PackRef pack, {
    Map<int, LimitOverride> overrides = const {},
  }) async {
    final source = open(pack);
    try {
      return MatchOutcome.fromResult(
        matcher.match(samples, source, overrides: overrides),
      );
    } finally {
      source.close();
    }
  }
}
