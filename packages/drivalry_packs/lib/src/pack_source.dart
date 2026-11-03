/// Where tiles come from: an abstract source plus an in-memory implementation.
library;

import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:drivalry_scoring/drivalry_scoring.dart' show haversine;

import 'geohash.dart';
import 'pack_way.dart';
import 'tile_codec.dart';

/// Read access to one region's pack.
abstract class PackSource {
  /// The `meta` table as a map. Always contains `schema_version`.
  Map<String, String> get meta;

  /// The compressed `ways` blob for a cell, or null when the pack has no
  /// ways there.
  Uint8List? tileBlob(String geohash);

  /// Street name for a `names.name_id`, or null.
  String? name(int nameId);

  /// Releases any native resources. Safe to call twice.
  void close();

  /// Convenience: decoded ways for a cell (empty when absent).
  List<PackWay> tile(String geohash) {
    final blob = tileBlob(geohash);
    if (blob == null) return const [];
    return TileCodec.decode(blob, name);
  }
}

/// A pack held entirely in memory. Used by tests and by code that builds
/// small packs on the fly.
class MemoryPack extends PackSource {
  MemoryPack({
    required Map<String, String> meta,
    required Map<String, Uint8List> tiles,
    required Map<int, String> names,
  }) : _meta = Map.unmodifiable(meta),
       _tiles = Map.of(tiles),
       _names = Map.of(names);

  /// Builds a pack from ways: assigns 1-based name ids in UTF-8 byte order
  /// and stores every way in each 5-character cell its polyline passes
  /// through (sampled every 500 m plus both endpoints of each segment).
  factory MemoryPack.fromWays(List<PackWay> ways, {Map<String, String>? meta}) {
    final nameSet = <String>{for (final w in ways) ?w.name};
    final sortedNames = nameSet.toList()..sort(_compareUtf8);
    final nameId = <String, int>{
      for (var i = 0; i < sortedNames.length; i++) sortedNames[i]: i + 1,
    };
    final cells = <String, List<PackWay>>{};
    for (final way in ways) {
      for (final cell in cellsForWay(way)) {
        (cells[cell] ??= []).add(way);
      }
    }
    final tiles = <String, Uint8List>{
      for (final e in cells.entries)
        e.key: TileCodec.encode(e.value, (n) => nameId[n]!),
    };
    return MemoryPack(
      meta: {
        'schema_version': '1',
        'region': 'memory',
        'region_name': 'In-memory pack',
        'geohash_precision': '5',
        'way_count': '${ways.length}',
        'tile_count': '${tiles.length}',
        ...?meta,
      },
      tiles: tiles,
      names: {for (final e in nameId.entries) e.value: e.key},
    );
  }

  final Map<String, String> _meta;
  final Map<String, Uint8List> _tiles;
  final Map<int, String> _names;

  @override
  Map<String, String> get meta => _meta;

  @override
  Uint8List? tileBlob(String geohash) => _tiles[geohash];

  @override
  String? name(int nameId) => _names[nameId];

  /// Cells present in this pack.
  Iterable<String> get cells => _tiles.keys;

  @override
  void close() {}

  /// The set of 5-character cells a way's polyline passes through, following
  /// the builder's rule: both endpoints of every segment plus points every
  /// 500 m along it.
  static Set<String> cellsForWay(PackWay way, {int precision = 5}) {
    final out = <String>{};
    for (var i = 0; i < way.pointCount; i++) {
      out.add(Geohash.encode(way.lats[i], way.lons[i], precision: precision));
      if (i == 0) continue;
      final la0 = way.lats[i - 1], lo0 = way.lons[i - 1];
      final la1 = way.lats[i], lo1 = way.lons[i];
      final len = haversine(la0, lo0, la1, lo1);
      final steps = (len / 500).floor();
      for (var s = 1; s <= steps; s++) {
        final f = (s * 500) / len;
        if (f >= 1) break;
        out.add(
          Geohash.encode(
            la0 + (la1 - la0) * f,
            lo0 + (lo1 - lo0) * f,
            precision: precision,
          ),
        );
      }
    }
    return out;
  }

  static int _compareUtf8(String a, String b) {
    final ba = utf8.encode(a);
    final bb = utf8.encode(b);
    final n = ba.length < bb.length ? ba.length : bb.length;
    for (var i = 0; i < n; i++) {
      final d = ba[i] - bb[i];
      if (d != 0) return d;
    }
    return ba.length - bb.length;
  }
}
