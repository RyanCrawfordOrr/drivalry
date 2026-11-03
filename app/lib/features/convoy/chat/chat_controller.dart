import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../data/db/database.dart';
import '../../../data/repos/convoy_sync.dart';
import '../../../data/supabase/supabase_providers.dart';
import '../../../widgets/friendly_error.dart';
import '../audio/convoy_audio_session.dart';
import '../channel/convoy_channel.dart';
import '../radio/data_bus.dart';
import 'voice_notes.dart';

/// One line in the convoy chat: text (broadcast) or a voice note (data bus).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.from,
    required this.t,
    this.text,
    this.voice,
    this.mine = false,
  });

  final String id;
  final String from;
  final int t;
  final String? text;
  final VoiceNote? voice;
  final bool mine;

  bool get isVoice => voice != null;

  Map<String, Object?> toJson() => {
    'id': id,
    'from': from,
    't': t,
    'text': ?text,
    'mine': mine,
  };

  static ChatMessage fromJson(Map<String, dynamic> j) => ChatMessage(
    id: j['id'] as String,
    from: j['from'] as String,
    t: (j['t'] as num).toInt(),
    text: j['text'] as String?,
    mine: j['mine'] == true,
  );
}

class ChatState {
  const ChatState({
    this.messages = const [],
    this.recording = false,
    this.recordingMs = 0,
    this.readAloud = true,
    this.error,
  });

  final List<ChatMessage> messages;
  final bool recording;
  final int recordingMs;

  /// Whether incoming text is spoken while this phone is driving.
  final bool readAloud;
  final String? error;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? recording,
    int? recordingMs,
    bool? readAloud,
    String? error,
    bool clearError = false,
  }) => ChatState(
    messages: messages ?? this.messages,
    recording: recording ?? this.recording,
    recordingMs: recordingMs ?? this.recordingMs,
    readAloud: readAloud ?? this.readAloud,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Records a voice note to a file. The app uses `record`; tests inject bytes.
abstract class VoiceRecorder {
  Future<bool> hasPermission();

  /// Begins capturing to a temporary file the recorder owns.
  Future<void> start();

  /// Returns the recorded bytes, or null when nothing was captured.
  Future<Uint8List?> stop();
  Future<void> dispose();
}

class RecordVoiceRecorder implements VoiceRecorder {
  final AudioRecorder _rec = AudioRecorder();
  String? _path;

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final noteId = const Uuid().v4();
    final path = p.join(dir.path, 'voice-$noteId.m4a');
    _path = path;
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 24000,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<Uint8List?> stop() async {
    final out = await _rec.stop() ?? _path;
    if (out == null) return null;
    final f = File(out);
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    await f.delete();
    return bytes;
  }

  @override
  Future<void> dispose() => _rec.dispose();
}

/// Plays a received note. The app uses audioplayers; tests record calls.
abstract class VoicePlayer {
  Future<void> play(Uint8List bytes, String mimeType);
}

class AudioplayersVoicePlayer implements VoicePlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> play(Uint8List bytes, String mimeType) async {
    try {
      await _player.stop();
      await _player.play(BytesSource(bytes, mimeType: mimeType));
    } catch (e) {
      debugPrint('voice playback failed: $e');
    }
  }
}

/// The chat for one convoy. Text goes over the Realtime channel (`chat`),
/// voice notes over the data channel in chunks (docs/10 §3, §5). While this
/// phone is driving, incoming text is read aloud and notes auto-play; the
/// composer is for passengers.
class ChatController extends Notifier<ChatState> {
  ChatController(this.convoyId);

  final String convoyId;
  final List<StreamSubscription<void>> _subs = [];
  StreamSubscription<void>? _busSub;
  final _assembler = VoiceNoteAssembler();
  final _chunker = const VoiceNoteChunker();
  Timer? _recordTimer;
  int _recordStartedAt = 0;
  static const _uuid = Uuid();
  static const keepMessages = 100;
  static const readAloudKey = 'chat_read_aloud';

  static String cacheKey(String convoyId) => 'chat:$convoyId';

  @override
  ChatState build() {
    final channel = ref.watch(convoyChannelProvider(convoyId));
    if (channel != null) {
      _subs.add(
        channel.messages.where((m) => m.type == 'chat').listen(_onText),
      );
    }
    // The data bus swaps between Noop and the mesh as the radio starts and
    // stops. Follow it with a listener, not a watch: a rebuild here would
    // drop the message list and any note being recorded.
    _attachBus(ref.read(convoyDataBusProvider(convoyId)));
    ref.listen(convoyDataBusProvider(convoyId), (_, next) => _attachBus(next));
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _busSub?.cancel();
      _recordTimer?.cancel();
    });
    _restore();
    loadReadAloudSetting();
    return const ChatState();
  }

  String get _me => ref.read(currentUserIdProvider) ?? 'me';

  void _attachBus(ConvoyDataBus bus) {
    _busSub?.cancel();
    _busSub = bus.messages.where((m) => m.type == 'voice').listen(_onVoice);
  }

  Future<void> _restore() async {
    try {
      final raw = await ref.read(databaseProvider).cacheGet(cacheKey(convoyId));
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((j) => ChatMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(messages: [...list, ...state.messages]);
    } catch (e) {
      debugPrint('chat restore failed: $e');
    }
  }

  Future<void> _persist() async {
    final texts = state.messages.where((m) => !m.isVoice).toList();
    try {
      await ref
          .read(databaseProvider)
          .cachePut(
            cacheKey(convoyId),
            jsonEncode([for (final m in texts) m.toJson()]),
            DateTime.now().millisecondsSinceEpoch,
          );
    } catch (e) {
      debugPrint('chat persist failed: $e');
    }
  }

  void _append(ChatMessage m) {
    final list = [...state.messages, m];
    if (list.length > keepMessages) {
      list.removeRange(0, list.length - keepMessages);
    }
    state = state.copyWith(messages: list);
    _persist();
  }

  // --------------------------------------------------------------- text --

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final channel = ref.read(convoyChannelProvider(convoyId));
    final m = ChatMessage(
      id: _uuid.v4(),
      from: _me,
      t: DateTime.now().millisecondsSinceEpoch,
      text: trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed,
      mine: true,
    );
    _append(m);
    if (channel == null) return;
    try {
      await channel.send('chat', {'text': m.text});
    } catch (e) {
      state = state.copyWith(
        error: friendlyError(e, doing: 'send the message'),
      );
    }
  }

  void _onText(ConvoyMessage m) {
    final text = m.payload['text'];
    if (text is! String || text.isEmpty) return;
    final msg = ChatMessage(
      id: '${m.from}:${m.t}',
      from: m.from,
      t: m.t,
      text: text,
    );
    _append(msg);
    if (shouldReadAloud()) unawaited(_readAloud(m.from, text));
  }

  /// Drivers hear "Message from Ana": the name comes from the cached
  /// member list, never a UUID.
  Future<void> _readAloud(String from, String text) async {
    final names = await ref.read(convoyRepoProvider).memberNames(convoyId);
    if (!ref.mounted) return;
    final who = names[from] ?? 'Someone';
    await ref.read(speakerProvider).say('Message from $who: $text');
  }

  /// Drivers hear chat; the setting (default on) can turn it off.
  bool shouldReadAloud() {
    if (!ref.read(isDrivingNowProvider)) return false;
    return state.readAloud;
  }

  Future<void> loadReadAloudSetting() async {
    try {
      final v = await ref.read(databaseProvider).getSetting(readAloudKey);
      state = state.copyWith(readAloud: v != 'false');
    } catch (e) {
      debugPrint('read-aloud setting not loaded: $e');
    }
  }

  Future<void> setReadAloud(bool on) async {
    state = state.copyWith(readAloud: on);
    await ref
        .read(databaseProvider)
        .setSetting(readAloudKey, on ? 'true' : 'false');
  }

  // -------------------------------------------------------------- voice --

  VoiceRecorder? _recorder;

  Future<void> startRecording() async {
    if (state.recording) return;
    final VoiceRecorder rec = _recorder ?? ref.read(voiceRecorderProvider);
    _recorder = rec;
    if (!await rec.hasPermission()) {
      state = state.copyWith(
        error: 'Microphone permission is needed for voice notes.',
      );
      return;
    }
    await rec.start();
    _recordStartedAt = DateTime.now().millisecondsSinceEpoch;
    state = state.copyWith(recording: true, recordingMs: 0, clearError: true);
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final ms = DateTime.now().millisecondsSinceEpoch - _recordStartedAt;
      state = state.copyWith(recordingMs: ms);
      if (ms >= VoiceNoteChunker.maxDuration.inMilliseconds) {
        stopRecordingAndSend();
      }
    });
  }

  Future<void> stopRecordingAndSend() async {
    if (!state.recording) return;
    _recordTimer?.cancel();
    final rec = _recorder;
    state = state.copyWith(recording: false);
    final bytes = await rec?.stop();
    if (bytes == null || bytes.isEmpty) return;
    final durationMs = DateTime.now().millisecondsSinceEpoch - _recordStartedAt;
    await sendVoiceBytes(bytes, 'audio/aac', durationMs);
  }

  Future<void> cancelRecording() async {
    _recordTimer?.cancel();
    if (!state.recording) return;
    state = state.copyWith(recording: false);
    await _recorder?.stop();
  }

  /// Chunks and sends a note; also shows it locally.
  Future<void> sendVoiceBytes(
    Uint8List bytes,
    String mimeType,
    int durationMs,
  ) async {
    if (bytes.length > VoiceNoteChunker.maxNoteBytes) {
      state = state.copyWith(error: 'That note is too long to send.');
      return;
    }
    final id = _uuid.v4();
    final bus = ref.read(convoyDataBusProvider(convoyId));
    for (final chunk in _chunker.split(
      id: id,
      bytes: bytes,
      mimeType: mimeType,
      durationMs: durationMs,
    )) {
      bus.send('voice', chunk);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _append(
      ChatMessage(
        id: id,
        from: _me,
        t: now,
        mine: true,
        voice: VoiceNote(
          id: id,
          from: _me,
          bytes: bytes,
          mimeType: mimeType,
          durationMs: durationMs,
          t: now,
        ),
      ),
    );
  }

  void _onVoice(DataMessage m) {
    if (m.from == _me) return;
    final note = _assembler.add(m.from, m.payload);
    if (note == null) return;
    _append(ChatMessage(id: note.id, from: note.from, t: note.t, voice: note));
    if (ref.read(isDrivingNowProvider)) play(note);
  }

  Future<void> play(VoiceNote note) =>
      ref.read(voicePlayerProvider).play(note.bytes, note.mimeType);
}

final voiceRecorderProvider = Provider<VoiceRecorder>((ref) {
  final r = RecordVoiceRecorder();
  ref.onDispose(r.dispose);
  return r;
});

final voicePlayerProvider = Provider<VoicePlayer>(
  (ref) => AudioplayersVoicePlayer(),
);

final chatControllerProvider =
    NotifierProvider.family<ChatController, ChatState, String>(
      ChatController.new,
    );
