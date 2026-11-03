import 'package:drivalry/features/convoy/channel/safe_send.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('safeSend reports success and swallows a dropped socket', () async {
    expect(await safeSend('ok', () async {}), isTrue);
    expect(
      await safeSend('dropped', () async => throw StateError('socket closed')),
      isFalse,
      reason: 'a fire-and-forget send must never surface as an unhandled error',
    );
  });
}
