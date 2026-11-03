import 'package:drivalry/features/convoy/channel/convoy_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts the real open/close calls behind the reference-counted facade.
class _Counted extends RefCountedConvoyChannel {
  int opens = 0;
  int closes = 0;

  @override
  String get convoyId => 'c1';
  @override
  Stream<ConvoyMessage> get messages => const Stream.empty();
  @override
  Stream<Set<String>> get present => const Stream.empty();
  @override
  Set<String> get presentNow => const {};
  @override
  Future<void> open() async => opens++;
  @override
  Future<void> close() async => closes++;
  @override
  Future<void> send(
    String type,
    Map<String, Object?> payload, {
    String? to,
  }) async {}
}

void main() {
  test('opens on the first join and closes on the last leave', () async {
    final ch = _Counted();
    await ch.join(); // live wiring (positions, regroup, lost sheep)
    await ch.join(); // radio
    expect(ch.listeners, 2);
    expect(ch.opens, 1);

    await ch.leave(); // radio stops
    expect(ch.closes, 0, reason: 'the live wiring still needs the socket');
    expect(ch.listeners, 1);

    await ch.leave(); // live wiring disposed
    expect(ch.closes, 1);
    expect(ch.listeners, 0);
  });

  test('extra leaves are ignored; shutdown closes regardless', () async {
    final ch = _Counted();
    await ch.leave();
    expect(ch.closes, 0);

    await ch.join();
    await ch.join();
    await ch.shutdown();
    expect(ch.closes, 1);
    expect(ch.listeners, 0);

    await ch.join();
    expect(ch.opens, 2, reason: 'usable again after shutdown');
  });
}
