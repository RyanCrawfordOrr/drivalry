/// Drivalry speed-limit packs: reader and on-device road matcher.
///
/// A pack is one SQLite file per region holding OpenStreetMap road geometry
/// and `maxspeed` values, indexed by 5-character geohash (`docs/07-pack-format.md`).
/// [SqlitePack] reads one; [TileCache] decodes and caches cells; [RoadMatcher]
/// turns a trip's GPS samples into the `RoadSegment` list the scoring engine in
/// `package:drivalry_scoring` consumes; [LiveMatcher] answers "what road am I
/// on right now" for spoken cues. [PackIndex] models the release `index.json`.
///
/// Pure Dart. `dart:io` is used only for zlib and SQLite.
library;

export 'src/geohash.dart';
export 'src/geometry.dart'
    show
        LocalProjection,
        PolylineHit,
        angleDiff,
        flatDistanceM,
        metresPerDegree,
        nearestPointOnPolyline,
        normalizeHeading,
        planarBearing;
export 'src/live_matcher.dart';
export 'src/pack_index.dart';
export 'src/pack_source.dart';
export 'src/pack_way.dart';
export 'src/road_matcher.dart';
export 'src/sqlite_pack.dart';
export 'src/tile_cache.dart';
export 'src/tile_codec.dart';
export 'src/varint.dart';
