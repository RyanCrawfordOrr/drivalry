import 'dart:convert';
import 'dart:typed_data';

/// A complete voice note as sent or received.
class VoiceNote {
  const VoiceNote({
    required this.id,
    required this.from,
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
    required this.t,
  });

  final String id;
  final String from;
  final Uint8List bytes;
  final String mimeType;
  final int durationMs;

  /// Epoch milliseconds when the last chunk arrived (or the note was sent).
  final int t;
}

/// Splits a recording into data-channel `voice` payloads (docs/10 §5):
/// `{id, seq, count, bytes: <base64>, last, mime, durationMs}`. 9 KB of audio
/// becomes 12 KB of base64, which with JSON framing stays under the 16 KB
/// data-channel message ceiling.
class VoiceNoteChunker {
  const VoiceNoteChunker({this.chunkBytes = 9 * 1024});

  /// Raw audio bytes per chunk.
  final int chunkBytes;

  /// Hard cap on a note; the recorder stops before this.
  static const maxNoteBytes = 120 * 1024;
  static const maxDuration = Duration(seconds: 20);

  List<Map<String, Object?>> split({
    required String id,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) {
    if (bytes.length > maxNoteBytes) {
      throw ArgumentError('voice note too large: ${bytes.length} bytes');
    }
    final chunks = <Map<String, Object?>>[];
    final count = bytes.isEmpty
        ? 1
        : (bytes.length + chunkBytes - 1) ~/ chunkBytes;
    for (var i = 0; i < count; i++) {
      final start = i * chunkBytes;
      final end = (start + chunkBytes).clamp(0, bytes.length);
      chunks.add({
        'id': id,
        'seq': i,
        'count': count,
        'bytes': base64Encode(bytes.sublist(start, end)),
        'last': i == count - 1,
        'mime': mimeType,
        'durationMs': durationMs,
      });
    }
    return chunks;
  }
}

/// Reassembles chunks per (sender, note id); tolerates out-of-order arrival
/// and drops notes that never complete after [staleMs].
class VoiceNoteAssembler {
  VoiceNoteAssembler({int Function()? now, this.staleMs = 60_000})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _now;
  final int staleMs;
  final Map<String, _Partial> _partials = {};

  /// Returns the completed note when this chunk finished it, else null.
  VoiceNote? add(String from, Map<String, dynamic> payload) {
    final id = payload['id'];
    final seq = payload['seq'];
    final data = payload['bytes'];
    if (id is! String || seq is! num || data is! String) return null;
    _evictStale();
    final key = '$from:$id';
    final p = _partials.putIfAbsent(
      key,
      () => _Partial(
        count: (payload['count'] as num?)?.toInt(),
        mime: payload['mime'] as String? ?? 'audio/aac',
        durationMs: (payload['durationMs'] as num?)?.toInt() ?? 0,
        startedAt: _now(),
      ),
    );
    p.parts[seq.toInt()] = base64Decode(data);
    p.count ??= payload['last'] == true ? seq.toInt() + 1 : null;
    if (p.count == null || p.parts.length < p.count!) return null;
    for (var i = 0; i < p.count!; i++) {
      if (!p.parts.containsKey(i)) return null;
    }
    _partials.remove(key);
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < p.count!; i++) {
      builder.add(p.parts[i]!);
    }
    return VoiceNote(
      id: id,
      from: from,
      bytes: builder.takeBytes(),
      mimeType: p.mime,
      durationMs: p.durationMs,
      t: _now(),
    );
  }

  int get pendingCount => _partials.length;

  void _evictStale() {
    final cutoff = _now() - staleMs;
    _partials.removeWhere((_, p) => p.startedAt < cutoff);
  }
}

class _Partial {
  _Partial({
    required this.count,
    required this.mime,
    required this.durationMs,
    required this.startedAt,
  });
  int? count;
  final String mime;
  final int durationMs;
  final int startedAt;
  final Map<int, Uint8List> parts = {};
}
