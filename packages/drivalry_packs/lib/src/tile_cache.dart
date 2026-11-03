/// Decoded-tile cache with neighbourhood lookups.
library;

import 'dart:collection';

import 'geohash.dart';
import 'pack_source.dart';
import 'pack_way.dart';

/// Loads and caches decoded tiles from a [PackSource], and answers "which
/// ways are near this point" with the point's cell plus its eight
/// neighbours, deduplicated by way id.
class TileCache {
  TileCache(this.source, {this.capacity = 64, this.precision = 5});

  final PackSource source;

  /// Maximum number of decoded cells kept. A cell is a few thousand ways at
  /// most, so 64 cells is a comfortable in-memory working set for a trip.
  final int capacity;
  final int precision;

  final LinkedHashMap<String, List<PackWay>> _cells = LinkedHashMap();
  String? _lastCenter;
  List<PackWay> _lastMerged = const [];

  /// Number of decoded cells currently held.
  int get cachedCells => _cells.length;

  /// Decoded ways for one cell (empty when the pack has none there).
  List<PackWay> cell(String geohash) {
    final hit = _cells.remove(geohash);
    if (hit != null) {
      _cells[geohash] = hit; // move to most-recent
      return hit;
    }
    final ways = source.tile(geohash);
    _cells[geohash] = ways;
    if (_cells.length > capacity) {
      _cells.remove(_cells.keys.first);
    }
    return ways;
  }

  /// All ways in the cell containing the point and its eight neighbours,
  /// deduplicated by id. Consecutive calls from the same cell return the
  /// same list instance.
  List<PackWay> waysNear(double lat, double lon) {
    final center = Geohash.encode(lat, lon, precision: precision);
    if (center == _lastCenter) return _lastMerged;
    final seen = <int>{};
    final merged = <PackWay>[];
    for (final w in cell(center)) {
      if (seen.add(w.id)) merged.add(w);
    }
    for (final n in Geohash.neighbors(center)) {
      for (final w in cell(n)) {
        if (seen.add(w.id)) merged.add(w);
      }
    }
    _lastCenter = center;
    _lastMerged = merged;
    return merged;
  }

  /// Drops every cached cell.
  void clear() {
    _cells.clear();
    _lastCenter = null;
    _lastMerged = const [];
  }
}
