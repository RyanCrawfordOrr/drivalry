/// Encoder and decoder for the tile blob (`docs/07-pack-format.md` §2–§4).
///
/// The phone only decodes. [TileCodec.encode] exists so tests and
/// [MemoryPack] can build tiles without the Python builder, and so the
/// decoder can be checked against an independent round trip.
library;

import 'dart:io' show ZLibDecoder, ZLibEncoder;
import 'dart:typed_data';

import 'pack_way.dart';
import 'varint.dart';

/// Blob format version this reader understands.
const int tileBlobVersion = 1;

/// Static codec for one tile's `ways` blob.
abstract final class TileCodec {
  static const int _flagOnewayMask = 0x03;
  static const int _flagSrcShift = 2;
  static const int _flagSrcMask = 0x03 << _flagSrcShift;
  static const int _flagMph = 0x10;
  static const int _flagRoundabout = 0x20;

  /// Decodes a zlib-compressed tile blob into its ways.
  ///
  /// [nameOf] resolves a `names.name_id` to the street name (null if absent).
  static List<PackWay> decode(
    Uint8List compressedBlob,
    String? Function(int nameId) nameOf,
  ) {
    final raw = Uint8List.fromList(ZLibDecoder().convert(compressedBlob));
    return decodeRaw(raw, nameOf);
  }

  /// Decodes an already-decompressed tile byte stream.
  static List<PackWay> decodeRaw(
    Uint8List raw,
    String? Function(int nameId) nameOf,
  ) {
    final r = ByteReader(raw);
    final version = r.readU8();
    if (version != tileBlobVersion) {
      throw FormatException('Unknown tile blob version $version');
    }
    final count = r.readVarint();
    final ways = List<PackWay>.generate(count, (_) => _readWay(r, nameOf));
    if (!r.isAtEnd) {
      throw FormatException('${r.remaining} trailing bytes in tile blob');
    }
    return ways;
  }

  static PackWay _readWay(ByteReader r, String? Function(int) nameOf) {
    final id = r.readVarint();
    final cls = r.readU8();
    if (cls >= roadClassByCode.length) {
      throw FormatException('Unknown road class $cls on way $id');
    }
    final nameIdPlusOne = r.readVarint();
    final maxPlusOne = r.readVarint();
    final maxbPlusOne = r.readVarint();
    final flags = r.readU8();
    final pointCount = r.readVarint();
    if (pointCount < 2) {
      throw FormatException('Way $id has $pointCount points');
    }
    final lats = Float64List(pointCount);
    final lons = Float64List(pointCount);
    var latE6 = r.readZigzag();
    var lonE6 = r.readZigzag();
    lats[0] = latE6 / 1e6;
    lons[0] = lonE6 / 1e6;
    for (var i = 1; i < pointCount; i++) {
      latE6 += r.readZigzag();
      lonE6 += r.readZigzag();
      lats[i] = latE6 / 1e6;
      lons[i] = lonE6 / 1e6;
    }
    final srcCode = (flags & _flagSrcMask) >> _flagSrcShift;
    return PackWay(
      id: id,
      roadClass: roadClassByCode[cls],
      name: nameIdPlusOne == 0 ? null : nameOf(nameIdPlusOne - 1),
      maxForward: maxPlusOne == 0 ? null : maxPlusOne - 1,
      maxBackward: maxbPlusOne == 0 ? null : maxbPlusOne - 1,
      mph: flags & _flagMph != 0,
      oneway: flags & _flagOnewayMask,
      roundabout: flags & _flagRoundabout != 0,
      source: switch (srcCode) {
        1 => LimitSource.tag,
        2 => LimitSource.implied,
        _ => LimitSource.none,
      },
      lats: lats,
      lons: lons,
    );
  }

  /// Encodes ways into a zlib-compressed (level 9) tile blob.
  ///
  /// Ways are written sorted by id. [nameIdOf] must return the 1-based
  /// `names.name_id` for a street name.
  static Uint8List encode(List<PackWay> ways, int Function(String) nameIdOf) {
    return Uint8List.fromList(
      ZLibEncoder(level: 9).convert(encodeRaw(ways, nameIdOf)),
    );
  }

  /// Encodes ways into the uncompressed tile byte stream.
  static Uint8List encodeRaw(
    List<PackWay> ways,
    int Function(String) nameIdOf,
  ) {
    final sorted = [...ways]..sort((a, b) => a.id.compareTo(b.id));
    final w = ByteWriter();
    w.writeU8(tileBlobVersion);
    w.writeVarint(sorted.length);
    for (final way in sorted) {
      _writeWay(w, way, nameIdOf);
    }
    return w.takeBytes();
  }

  static void _writeWay(
    ByteWriter w,
    PackWay way,
    int Function(String) nameIdOf,
  ) {
    w.writeVarint(way.id);
    w.writeU8(roadClassCode(way.roadClass));
    final name = way.name;
    w.writeVarint(name == null ? 0 : nameIdOf(name) + 1);
    w.writeVarint(way.maxForward == null ? 0 : way.maxForward! + 1);
    w.writeVarint(way.maxBackward == null ? 0 : way.maxBackward! + 1);
    final src = switch (way.source) {
      LimitSource.none => 0,
      LimitSource.tag => 1,
      LimitSource.implied => 2,
    };
    final flags =
        (way.oneway & _flagOnewayMask) |
        (src << _flagSrcShift) |
        (way.mph ? _flagMph : 0) |
        (way.roundabout ? _flagRoundabout : 0);
    w.writeU8(flags);
    final n = way.pointCount;
    w.writeVarint(n);
    var prevLat = _e6(way.lats[0]);
    var prevLon = _e6(way.lons[0]);
    w.writeZigzag(prevLat);
    w.writeZigzag(prevLon);
    for (var i = 1; i < n; i++) {
      final la = _e6(way.lats[i]);
      final lo = _e6(way.lons[i]);
      w.writeZigzag(la - prevLat);
      w.writeZigzag(lo - prevLon);
      prevLat = la;
      prevLon = lo;
    }
  }

  static int _e6(double deg) => (deg * 1e6).round();
}
