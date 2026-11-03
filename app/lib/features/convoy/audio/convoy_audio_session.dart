import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../tracking/tracking_controller.dart';
import '../../../tracking/tracking_models.dart';
import '../radio/radio_controller.dart';

/// Dart side of the `app.drivalry/convoy_audio` method channel (docs/10 §4).
///
/// `start` puts the phone in communication mode (Android: MODE_IN_COMMUNICATION,
/// audio focus, foreground service; iOS: playAndRecord/voiceChat session that
/// ducks music and allows Bluetooth routes). `duck` is held while the PTT
/// button is down. Every call swallows a missing plugin so tests, the
/// simulator and desktop runs keep working.
class ConvoyAudioSession {
  ConvoyAudioSession({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('app.drivalry/convoy_audio') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopped') _stopped.add(null);
      return null;
    });
  }

  final MethodChannel _channel;
  final _stopped = StreamController<void>.broadcast();
  bool _running = false;

  bool get running => _running;

  /// Fires when the user tapped Stop on the Android service notification.
  Stream<void> get stopped => _stopped.stream;

  Future<void> start() async {
    await _call('start');
    _running = true;
  }

  Future<void> stop() async {
    _running = false;
    await _call('stop');
  }

  Future<void> duck(bool on) => _call('duck', {'on': on});

  Future<void> setSpeaker(bool on) => _call('setSpeaker', {'on': on});

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No native side (tests, simulator): behave as if it worked.
    } on PlatformException catch (e) {
      debugPrint('convoy audio $method failed: ${e.message}');
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _stopped.close();
  }
}

final convoyAudioSessionProvider = Provider<ConvoyAudioSession>((ref) {
  final s = ConvoyAudioSession();
  ref.onDispose(s.dispose);
  return s;
});

/// Plugs the native session into the radio: override
/// `convoyAudioSessionHookProvider` with [nativeAudioSessionHookProvider] in
/// the app's root scope so starting the radio also starts the foreground
/// service / AVAudioSession, and Stop on the notification ends the radio.
class NativeAudioSessionHook implements ConvoyAudioSessionHook {
  NativeAudioSessionHook(this._session);
  final ConvoyAudioSession _session;

  @override
  Future<void> start() => _session.start();

  @override
  Future<void> stop() => _session.stop();

  @override
  Stream<void> get stopped => _session.stopped;
}

final nativeAudioSessionHookProvider = Provider<ConvoyAudioSessionHook>(
  (ref) => NativeAudioSessionHook(ref.watch(convoyAudioSessionProvider)),
);

/// True while this phone is recording a drive (the plugin's `active` phase).
/// Chat composing and games are for passengers, so screens gate on this.
final isDrivingNowProvider = Provider<bool>(
  (ref) =>
      ref.watch(trackingControllerProvider).plugin.phase ==
      TrackingPhase.active,
);

/// Spoken output for drivers: read-aloud chat and game results. Tests inject
/// [RecordingSpeaker]; the app uses [TtsSpeaker].
abstract class Speaker {
  Future<void> say(String text);
}

class TtsSpeaker implements Speaker {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  @override
  Future<void> say(String text) async {
    try {
      if (!_ready) {
        await _tts.awaitSpeakCompletion(true);
        _ready = true;
      }
      await _tts.speak(text);
    } catch (e) {
      debugPrint('tts failed: $e');
    }
  }
}

/// Collects what would have been spoken.
class RecordingSpeaker implements Speaker {
  final List<String> spoken = [];

  @override
  Future<void> say(String text) async => spoken.add(text);
}

final speakerProvider = Provider<Speaker>((ref) => TtsSpeaker());
