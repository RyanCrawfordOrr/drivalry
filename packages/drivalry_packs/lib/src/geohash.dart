/// Niemeyer geohash encode, decode and neighbours.
///
/// Packs index ways by 5-character cells (about 4.9 km × 4.9 km). The matcher
/// loads a sample's cell plus its eight neighbours.
library;

const String _alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';

final Map<int, int> _charValue = {
  for (var i = 0; i < _alphabet.length; i++) _alphabet.codeUnitAt(i): i,
};

/// Bounding box of a geohash cell, degrees.
class GeohashBox {
  const GeohashBox({
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;

  double get centerLat => (minLat + maxLat) / 2;
  double get centerLon => (minLon + maxLon) / 2;

  /// Height of the cell in degrees of latitude.
  double get latSize => maxLat - minLat;

  /// Width of the cell in degrees of longitude.
  double get lonSize => maxLon - minLon;

  /// True when the point lies inside or on the edge of the box.
  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  @override
  String toString() => 'GeohashBox($minLat, $minLon, $maxLat, $maxLon)';
}

/// Geohash helpers. All methods are pure and allocation-light.
abstract final class Geohash {
  /// Encodes a coordinate to a geohash of [precision] characters (default 5).
  static String encode(double lat, double lon, {int precision = 5}) {
    if (precision < 1 || precision > 12) {
      throw ArgumentError.value(precision, 'precision', 'must be 1..12');
    }
    var minLat = -90.0, maxLat = 90.0, minLon = -180.0, maxLon = 180.0;
    final out = StringBuffer();
    var bit = 0;
    var ch = 0;
    var even = true;
    while (out.length < precision) {
      if (even) {
        final mid = (minLon + maxLon) / 2;
        if (lon >= mid) {
          ch = (ch << 1) | 1;
          minLon = mid;
        } else {
          ch = ch << 1;
          maxLon = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          ch = (ch << 1) | 1;
          minLat = mid;
        } else {
          ch = ch << 1;
          maxLat = mid;
        }
      }
      even = !even;
      if (++bit == 5) {
        out.write(_alphabet[ch]);
        bit = 0;
        ch = 0;
      }
    }
    return out.toString();
  }

  /// Decodes a geohash to its cell bounding box.
  static GeohashBox decode(String hash) {
    if (hash.isEmpty) throw ArgumentError.value(hash, 'hash', 'empty');
    var minLat = -90.0, maxLat = 90.0, minLon = -180.0, maxLon = 180.0;
    var even = true;
    for (var i = 0; i < hash.length; i++) {
      final v = _charValue[hash.codeUnitAt(i)];
      if (v == null) {
        throw ArgumentError.value(hash, 'hash', 'invalid character');
      }
      for (var mask = 16; mask > 0; mask >>= 1) {
        if (even) {
          final mid = (minLon + maxLon) / 2;
          if (v & mask != 0) {
            minLon = mid;
          } else {
            maxLon = mid;
          }
        } else {
          final mid = (minLat + maxLat) / 2;
          if (v & mask != 0) {
            minLat = mid;
          } else {
            maxLat = mid;
          }
        }
        even = !even;
      }
    }
    return GeohashBox(
      minLat: minLat,
      minLon: minLon,
      maxLat: maxLat,
      maxLon: maxLon,
    );
  }

  /// The eight cells surrounding [hash], at the same precision, in the order
  /// N, NE, E, SE, S, SW, W, NW. Longitude wraps; cells past the poles are
  /// omitted, so the list is shorter than eight only at the very edges of the
  /// world.
  static List<String> neighbors(String hash) {
    final box = decode(hash);
    final dLat = box.latSize;
    final dLon = box.lonSize;
    final lat = box.centerLat;
    final lon = box.centerLon;
    const offsets = [
      (1, 0),
      (1, 1),
      (0, 1),
      (-1, 1),
      (-1, 0),
      (-1, -1),
      (0, -1),
      (1, -1),
    ];
    final out = <String>[];
    for (final (dy, dx) in offsets) {
      final nLat = lat + dy * dLat;
      if (nLat <= -90 || nLat >= 90) continue;
      var nLon = lon + dx * dLon;
      if (nLon >= 180) nLon -= 360;
      if (nLon < -180) nLon += 360;
      out.add(encode(nLat, nLon, precision: hash.length));
    }
    return out;
  }
}
