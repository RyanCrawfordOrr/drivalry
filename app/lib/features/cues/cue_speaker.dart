import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Speaks short cues through the active audio route, ducking music. Abstract
/// so tests and the simulator stay silent.
abstract class CueSpeaker {
  Future<void> speak(String text);
  Future<void> stop();

  /// Voice speed as a multiplier of normal (0.6–1.2).
  Future<void> setRate(double multiplier);
}

class SilentCueSpeaker implements CueSpeaker {
  SilentCueSpeaker();
  final List<String> spoken = [];
  double rate = 0.9;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {}

  @override
  Future<void> setRate(double multiplier) async => rate = multiplier;
}

/// On-device TTS. The engine is created on first use so building the provider
/// graph never touches the platform. On iOS the audio category ducks other
/// audio and mixes so music resumes right after the cue.
class TtsCueSpeaker implements CueSpeaker {
  FlutterTts? _tts;
  double _rate = 0.9;

  /// flutter_tts rates are platform-normalised with 0.5 as normal speed.
  static double engineRate(double multiplier) =>
      (0.5 * multiplier).clamp(0.1, 1.0);

  Future<FlutterTts?> _engine() async {
    if (_tts != null) return _tts;
    try {
      final tts = FlutterTts();
      await tts.setVolume(1.0);
      await tts.setSpeechRate(engineRate(_rate));
      if (!kIsWeb && Platform.isIOS) {
        await tts.setSharedInstance(true);
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.duckOthers,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
          IosTextToSpeechAudioMode.voicePrompt,
        );
      }
      _tts = tts;
    } catch (e) {
      debugPrint('cue TTS unavailable: $e');
    }
    return _tts;
  }

  @override
  Future<void> speak(String text) async {
    try {
      await (await _engine())?.speak(text);
    } catch (e) {
      debugPrint('cue speak failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  @override
  Future<void> setRate(double multiplier) async {
    _rate = multiplier;
    try {
      await _tts?.setSpeechRate(engineRate(multiplier));
    } catch (_) {}
  }
}

final cueSpeakerProvider = Provider<CueSpeaker>((ref) => TtsCueSpeaker());
