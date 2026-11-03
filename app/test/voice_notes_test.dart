import 'dart:convert';
import 'dart:typed_data';

import 'package:drivalry/features/convoy/chat/voice_notes.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytesOf(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + 3) & 0xff));

void main() {
  const chunker = VoiceNoteChunker();

  test('splits into chunks that fit a data-channel message', () {
    final data = bytesOf(30 * 1024);
    final chunks = chunker.split(
      id: 'n1',
      bytes: data,
      mimeType: 'audio/aac',
      durationMs: 4000,
    );
    final expected =
        (data.length + chunker.chunkBytes - 1) ~/ chunker.chunkBytes;
    expect(chunks, hasLength(expected));
    expect(expected, greaterThan(1));
    for (var i = 0; i < chunks.length; i++) {
      final c = chunks[i];
      expect(c['id'], 'n1');
      expect(c['seq'], i);
      expect(c['count'], chunks.length);
      expect(c['last'], i == chunks.length - 1);
      expect(c['mime'], 'audio/aac');
      expect(c['durationMs'], 4000);
      expect((c['bytes'] as String).length, lessThanOrEqualTo(12 * 1024));
      expect(jsonEncode(c).length, lessThan(16 * 1024));
    }
  });

  test('reassembles chunks that arrive out of order', () {
    final data = bytesOf(20 * 1024);
    final chunks = chunker.split(
      id: 'n1',
      bytes: data,
      mimeType: 'audio/aac',
      durationMs: 4000,
    );
    final asm = VoiceNoteAssembler(now: () => 77);
    VoiceNote? done;
    var completions = 0;
    for (final c in chunks.reversed) {
      final n = asm.add('sam', c.cast<String, dynamic>());
      if (n != null) {
        done = n;
        completions++;
      }
    }
    expect(completions, 1);
    expect(done!.bytes, data);
    expect(done.from, 'sam');
    expect(done.id, 'n1');
    expect(done.mimeType, 'audio/aac');
    expect(done.durationMs, 4000);
    expect(done.t, 77);
    expect(asm.pendingCount, 0);
  });

  test('the same note id from two senders is kept apart', () {
    final a = chunker.split(
      id: 'n',
      bytes: bytesOf(100),
      mimeType: 'audio/aac',
      durationMs: 1,
    );
    final b = chunker.split(
      id: 'n',
      bytes: bytesOf(200),
      mimeType: 'audio/aac',
      durationMs: 2,
    );
    final asm = VoiceNoteAssembler();
    final na = asm.add('sam', a.single.cast<String, dynamic>());
    final nb = asm.add('eve', b.single.cast<String, dynamic>());
    expect(na!.bytes.length, 100);
    expect(nb!.bytes.length, 200);
  });

  test('incomplete notes stay pending and are evicted when stale', () {
    var now = 0;
    final asm = VoiceNoteAssembler(now: () => now, staleMs: 1000);
    final chunks = chunker.split(
      id: 'n',
      bytes: bytesOf(20 * 1024),
      mimeType: 'audio/aac',
      durationMs: 1,
    );
    expect(asm.add('sam', chunks.first.cast<String, dynamic>()), isNull);
    expect(asm.pendingCount, 1);
    now = 2000;
    // Any new chunk sweeps partials older than staleMs.
    expect(asm.add('eve', chunks.first.cast<String, dynamic>()), isNull);
    expect(asm.pendingCount, 1);
    // sam's late remainder starts over instead of completing the old partial.
    for (final c in chunks.skip(1)) {
      expect(asm.add('sam', c.cast<String, dynamic>()), isNull);
    }
    expect(asm.pendingCount, 2);
  });

  test('oversized notes are refused before they are sent', () {
    expect(
      () => chunker.split(
        id: 'x',
        bytes: bytesOf(VoiceNoteChunker.maxNoteBytes + 1),
        mimeType: 'audio/aac',
        durationMs: 1,
      ),
      throwsArgumentError,
    );
    expect(VoiceNoteChunker.maxDuration, const Duration(seconds: 20));
  });

  test('garbage chunks are ignored and an empty note is one chunk', () {
    expect(VoiceNoteAssembler().add('sam', {'seq': 'x'}), isNull);
    expect(VoiceNoteAssembler().add('sam', {'id': 'n', 'seq': 0}), isNull);
    final empty = chunker.split(
      id: 'e',
      bytes: Uint8List(0),
      mimeType: 'audio/aac',
      durationMs: 0,
    );
    expect(empty, hasLength(1));
    expect(empty.single['last'], isTrue);
    final n = VoiceNoteAssembler().add(
      'sam',
      empty.single.cast<String, dynamic>(),
    );
    expect(n!.bytes, isEmpty);
  });
}
