import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks the countdown prompt through the car speakers. Abstract so tests
/// and the simulator stay silent.
abstract class CrashSpeaker {
  Future<void> speak(String text);
  Future<void> stop();
}

class SilentCrashSpeaker implements CrashSpeaker {
  const SilentCrashSpeaker();
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
}

/// On-device TTS, created on first use so building the provider graph never
/// touches the platform.
class TtsCrashSpeaker implements CrashSpeaker {
  FlutterTts? _tts;

  Future<FlutterTts?> _engine() async {
    if (_tts != null) return _tts;
    try {
      final tts = FlutterTts();
      await tts.setSpeechRate(0.5);
      await tts.setVolume(1.0);
      _tts = tts;
    } catch (e) {
      debugPrint('TTS unavailable: $e');
    }
    return _tts;
  }

  @override
  Future<void> speak(String text) async {
    try {
      await (await _engine())?.speak(text);
    } catch (e) {
      debugPrint('TTS speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}

final crashSpeakerProvider = Provider<CrashSpeaker>((ref) => TtsCrashSpeaker());
