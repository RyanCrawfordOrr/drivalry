import 'package:drivalry/features/convoy/radio/ptt_controller.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/radio_fakes.dart';

void main() {
  test('press unmutes and announces; release mutes and announces', () {
    fakeAsync((async) {
      final channel = FakeConvoyChannel('c');
      final audio = FakeLocalAudio();
      final haptics = <bool>[];
      final ptt = PttController(
        audio: audio,
        channel: channel,
        haptic: haptics.add,
      );
      ptt.press();
      async.flushMicrotasks();
      expect(audio.muted, isFalse);
      expect(ptt.state.holding, isTrue);
      expect(channel.sent.last.type, 'ptt');
      expect(channel.sent.last.payload['on'], isTrue);
      ptt.press(); // idempotent
      async.flushMicrotasks();
      expect(channel.sent, hasLength(1));
      ptt.release();
      async.flushMicrotasks();
      expect(audio.muted, isTrue);
      expect(ptt.state.holding, isFalse);
      expect(channel.sent.last.payload['on'], isFalse);
      expect(haptics, [true, false]);
      ptt.dispose();
      channel.dispose();
    });
  });

  test('a hold is cut after the maximum', () {
    fakeAsync((async) {
      final channel = FakeConvoyChannel('c');
      final audio = FakeLocalAudio();
      final ptt = PttController(
        audio: audio,
        channel: channel,
        maxHold: const Duration(seconds: 20),
      );
      ptt.press();
      async.elapse(const Duration(seconds: 19));
      expect(audio.muted, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(audio.muted, isTrue);
      expect(ptt.state.holding, isFalse);
      ptt.dispose();
      channel.dispose();
    });
  });

  test('who is talking follows ptt messages and expires', () {
    fakeAsync((async) {
      final channel = FakeConvoyChannel('c');
      final ptt = PttController(
        audio: FakeLocalAudio(),
        channel: channel,
        talkerTimeout: const Duration(seconds: 25),
      );
      channel.messages.listen(ptt.onMessage);
      channel.inject('ptt', 'sam', payload: {'on': true});
      channel.inject('ptt', 'eve', payload: {'on': true});
      async.flushMicrotasks();
      expect(ptt.state.talking, {'sam', 'eve'});
      channel.inject('ptt', 'sam', payload: {'on': false});
      async.flushMicrotasks();
      expect(ptt.state.talking, {'eve'});
      async.elapse(const Duration(seconds: 26));
      expect(ptt.state.talking, isEmpty, reason: 'lost ptt-off expires');
      channel.inject('ptt', 'eve', payload: {'on': true});
      async.flushMicrotasks();
      ptt.forget('eve');
      expect(ptt.state.talking, isEmpty);
      ptt.dispose();
      channel.dispose();
    });
  });
}
