import '../channel/convoy_channel.dart';
import 'peer_link.dart';

/// Broadcast message types used by the radio (docs/10 §3).
abstract final class RadioSignal {
  static const hello = 'hello';
  static const offer = 'offer';
  static const answer = 'answer';
  static const ice = 'ice';
  static const bye = 'bye';
  static const ptt = 'ptt';

  static const caps = ['audio', 'data'];
}

/// Typed send helpers over a [ConvoyChannel].
extension RadioSignaling on ConvoyChannel {
  Future<void> sendHello() =>
      send(RadioSignal.hello, {'caps': RadioSignal.caps});

  Future<void> sendBye() => send(RadioSignal.bye, const {});

  Future<void> sendOffer(String to, String sdp) =>
      send(RadioSignal.offer, {'sdp': sdp}, to: to);

  Future<void> sendAnswer(String to, String sdp) =>
      send(RadioSignal.answer, {'sdp': sdp}, to: to);

  Future<void> sendIce(String to, IceCandidateData c) =>
      send(RadioSignal.ice, {'candidate': c.toJson()}, to: to);

  Future<void> sendPtt({required bool on}) => send(RadioSignal.ptt, {'on': on});
}

/// Decoded signaling payloads.
extension RadioMessage on ConvoyMessage {
  String? get sdp => payload['sdp'] as String?;
  IceCandidateData? get iceCandidate =>
      IceCandidateData.fromJson(payload['candidate']);
  bool get pttOn => payload['on'] == true;
}
