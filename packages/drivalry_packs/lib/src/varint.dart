/// LEB128 varints and zigzag encoding, as used inside tile blobs
/// (`docs/07-pack-format.md` §2).
library;

import 'dart:typed_data';

/// Zigzag-encodes a signed integer so small magnitudes become small varints.
///
/// Equivalent to the 32-bit `(n << 1) ^ (n >> 31)` in the format document for
/// every value in the int32 range, and correct for all 64-bit values.
int zigzagEncode(int n) => (n << 1) ^ (n >> 63);

/// Inverse of [zigzagEncode].
int zigzagDecode(int v) => (v >>> 1) ^ -(v & 1);

/// Append-only byte sink with varint helpers.
class ByteWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  /// Bytes written so far.
  int get length => _b.length;

  /// Writes one unsigned byte (0–255).
  void writeU8(int v) {
    assert(v >= 0 && v <= 0xff, 'u8 out of range: $v');
    _b.addByte(v);
  }

  /// Writes an unsigned LEB128 varint. [v] must be non-negative.
  void writeVarint(int v) {
    assert(v >= 0, 'varint must be unsigned: $v');
    var n = v;
    while (n >= 0x80) {
      _b.addByte((n & 0x7f) | 0x80);
      n >>>= 7;
    }
    _b.addByte(n);
  }

  /// Writes a signed integer as a zigzag varint.
  void writeZigzag(int v) => writeVarint(zigzagEncode(v));

  /// Writes raw bytes.
  void writeBytes(List<int> bytes) => _b.add(bytes);

  /// Returns the bytes written. The writer must not be used afterwards.
  Uint8List takeBytes() => _b.takeBytes();
}

/// Sequential reader over a byte buffer with varint helpers.
class ByteReader {
  ByteReader(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  /// Current read offset.
  int get position => _pos;

  /// True when every byte has been consumed.
  bool get isAtEnd => _pos >= _bytes.length;

  /// Bytes left to read.
  int get remaining => _bytes.length - _pos;

  /// Reads one unsigned byte.
  int readU8() {
    if (_pos >= _bytes.length) {
      throw const FormatException('Unexpected end of tile blob');
    }
    return _bytes[_pos++];
  }

  /// Reads an unsigned LEB128 varint.
  int readVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final byte = readU8();
      result |= (byte & 0x7f) << shift;
      if (byte & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) {
        throw const FormatException('Varint too long');
      }
    }
  }

  /// Reads a zigzag varint as a signed integer.
  int readZigzag() => zigzagDecode(readVarint());
}
