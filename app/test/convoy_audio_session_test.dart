import 'package:drivalry/features/convoy/audio/convoy_audio_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.drivalry/convoy_audio');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('forwards start, duck, speaker and stop with their arguments', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final s = ConvoyAudioSession();
    await s.start();
    expect(s.running, isTrue);
    await s.duck(true);
    await s.setSpeaker(true);
    await s.duck(false);
    await s.stop();
    expect(s.running, isFalse);
    expect(calls.map((c) => c.method), [
      'start',
      'duck',
      'setSpeaker',
      'duck',
      'stop',
    ]);
    expect(calls[1].arguments, {'on': true});
    expect(calls[2].arguments, {'on': true});
    expect(calls[3].arguments, {'on': false});
    s.dispose();
  });

  test('a missing native side is not an error', () async {
    final s = ConvoyAudioSession();
    await s.start();
    expect(s.running, isTrue);
    await s.duck(true);
    await s.stop();
    s.dispose();
  });

  test('a platform error is swallowed and logged', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'audio', message: 'busy');
    });
    final s = ConvoyAudioSession();
    await s.start();
    await s.setSpeaker(false);
    s.dispose();
  });

  test('Stop on the Android notification reaches Dart', () async {
    final s = ConvoyAudioSession();
    final stopped = s.stopped.first;
    await messenger.handlePlatformMessage(
      'app.drivalry/convoy_audio',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('stopped')),
      (_) {},
    );
    await stopped;
    s.dispose();
  });
}
