import 'package:drivalry/features/convoy/radio/mesh.dart';
import 'package:drivalry/features/convoy/radio/peer_link.dart';
import 'package:drivalry/features/convoy/radio/webrtc_peer_link.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/radio_fakes.dart';

void main() {
  late FakeConvoyChannel channel;
  late FakePeerLinkFactory factory;
  late FakeLocalAudio audio;

  ConvoyMesh mesh(String self, {int Function()? now}) => ConvoyMesh(
    selfId: self,
    channel: channel,
    linkFactory: factory,
    audio: audio,
    iceServers: const [
      {'urls': 'stun:x'},
    ],
    now: now ?? () => 0,
    tickInterval: const Duration(hours: 1), // ticks driven by hand in tests
  );

  setUp(() {
    channel = FakeConvoyChannel('c1', present: {'a', 'b', 'm'});
    factory = FakePeerLinkFactory();
    audio = FakeLocalAudio();
  });

  tearDown(() => channel.dispose());

  test('join: hello goes out, offers to higher ids, waits for lower', () async {
    final m = mesh('b');
    await m.join();
    expect(channel.joins, 1);
    expect(channel.sentTypes(), contains('hello'));
    // 'b' offers to 'm' (higher) and awaits 'a' (lower).
    expect(factory.links['m']!.offerer, isTrue);
    expect(factory.links['a']!.offerer, isFalse);
    final offers = channel.sent.where((s) => s.type == 'offer').toList();
    expect(offers.single.to, 'm');
    expect(offers.single.payload['sdp'], 'offer-from-m-link');
    expect(m.peersNow.keys.toSet(), {'a', 'm'});
    await m.dispose();
  });

  test('incoming offer is answered; answer and ice are applied', () async {
    final m = mesh('b');
    await m.join();
    channel.inject('offer', 'a', payload: {'sdp': 'A-OFFER'}, to: 'b');
    await settle();
    expect(factory.links['a']!.calls, contains('createAnswer:A-OFFER'));
    final answers = channel.sent.where((s) => s.type == 'answer').toList();
    expect(answers.single.to, 'a');
    expect(answers.single.payload['sdp'], 'answer-sdp');

    channel.inject('answer', 'm', payload: {'sdp': 'M-ANSWER'}, to: 'b');
    channel.inject(
      'ice',
      'm',
      payload: {
        'candidate': {'candidate': 'cand', 'sdpMid': '0', 'sdpMLineIndex': 0},
      },
      to: 'b',
    );
    await settle();
    expect(factory.links['m']!.calls, contains('answer:M-ANSWER'));
    expect(factory.links['m']!.ice.single.candidate, 'cand');
    await m.dispose();
  });

  test('an offer from an unknown peer still gets answered', () async {
    channel = FakeConvoyChannel('c1', present: const {});
    final m = mesh('z');
    await m.join();
    channel.inject('offer', 'a', payload: {'sdp': 'X'}, to: 'z');
    await settle();
    expect(factory.links['a']!.offerer, isFalse);
    expect(channel.sentTypes(), contains('answer'));
    await m.dispose();
  });

  test('newcomer hello: I offer when my id is lower', () async {
    channel = FakeConvoyChannel('c1', present: const {});
    final m = mesh('b');
    await m.join();
    channel.inject('hello', 'c');
    await settle();
    expect(factory.links['c']!.offerer, isTrue);
    expect(channel.sent.where((s) => s.type == 'offer').single.to, 'c');
    channel.inject('hello', 'a');
    await settle();
    expect(factory.links['a']!.offerer, isFalse);
    expect(channel.sent.where((s) => s.type == 'offer'), hasLength(1));
    await m.dispose();
  });

  test('link events surface as status, frames and relayed deltas', () async {
    final m = mesh('b');
    await m.join();
    final link = factory.links['m']!;
    final frames = <DataFrame>[];
    final deltas = <int>[];
    m.frames.listen(frames.add);
    m.relayedBytesDelta.listen(deltas.add);

    link.emit(const LinkStateChanged(LinkState.connected));
    link.emit(const LinkDataOpen());
    link.emit(const LinkDataText('{"v":1}'));
    link.emit(
      const LinkStats(relayed: true, bytesSent: 100, bytesReceived: 50),
    );
    link.emit(
      const LinkStats(relayed: true, bytesSent: 160, bytesReceived: 90),
    );
    link.emit(
      const LinkIceCandidate(IceCandidateData(candidate: 'mine', sdpMid: '0')),
    );
    await settle();

    final st = m.peersNow['m']!;
    expect(st.state, LinkState.connected);
    expect(st.dataOpen, isTrue);
    expect(st.relayed, isTrue);
    expect(st.bytesSent, 160);
    expect(m.openDataPeers, {'m'});
    expect(frames.single.from, 'm');
    expect(deltas, [150, 100]);
    final ice = channel.sent.where((s) => s.type == 'ice').single;
    expect(ice.to, 'm');
    expect(m.sendText('hi'), isTrue);
    expect(link.sentTexts, ['hi']);
    expect(m.sendText('x', to: 'a'), isFalse, reason: 'a has no open channel');
    await m.dispose();
  });

  test('bye and presence loss close links; leave says bye', () async {
    final m = mesh('b');
    await m.join();
    channel.inject('bye', 'm');
    await settle();
    expect(factory.links['m']!.closed, isTrue);
    expect(m.peersNow.containsKey('m'), isFalse);
    channel.setPresent({'b'});
    await settle();
    expect(factory.links['a']!.closed, isTrue);
    await m.leave();
    expect(channel.sentTypes(), contains('bye'));
    expect(channel.leaves, 1);
    await m.dispose();
  });

  test('presence sync after join opens links to peers already there', () async {
    channel = FakeConvoyChannel('c1', present: const {});
    final m = mesh('b');
    await m.join();
    expect(factory.links, isEmpty);
    channel.setPresent({'a', 'b', 'm'});
    await settle();
    expect(factory.links['a']!.offerer, isFalse);
    expect(factory.links['m']!.offerer, isTrue);
    // Their hello arriving right after does not reopen the young link.
    channel.inject('hello', 'm');
    await settle();
    expect(factory.created.where((p) => p == 'm'), hasLength(1));
    // An empty sync (Realtime hiccup) leaves the mesh alone.
    channel.setPresent(const {});
    await settle();
    expect(factory.links['m']!.closed, isFalse);
    await m.dispose();
  });

  test(
    'reconnect restarts ICE on the offerer side, re-hellos otherwise',
    () async {
      final m = mesh('b');
      await m.join();
      await m.reconnect('m');
      expect(factory.links['m']!.calls, contains('restart'));
      expect(
        channel.sent.where((s) => s.type == 'offer' && s.to == 'm'),
        hasLength(2),
      );
      final hellos = channel.sent.where((s) => s.type == 'hello').length;
      await m.reconnect('a');
      expect(channel.sent.where((s) => s.type == 'hello').length, hellos + 1);
      await m.dispose();
    },
  );

  test('incoming mute propagates to every link', () async {
    final m = mesh('b');
    await m.join();
    m.incomingMuted = true;
    expect(factory.links.values.every((l) => l.incomingMutedValue), isTrue);
    channel.inject('hello', 'q');
    await settle();
    expect(factory.links['q']!.incomingMutedValue, isTrue);
    await m.dispose();
  });

  group('tuneOpus', () {
    test('adds bitrate, DTX and mono to the Opus fmtp line', () {
      const sdp =
          'v=0\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111 63\r\n'
          'a=rtpmap:111 opus/48000/2\r\n'
          'a=fmtp:111 minptime=10;useinbandfec=1\r\n'
          'a=rtpmap:63 red/48000/2\r\n';
      final out = tuneOpus(sdp);
      expect(
        out,
        contains(
          'a=fmtp:111 minptime=10;useinbandfec=1;maxaveragebitrate=24000;'
          'usedtx=1;stereo=0;sprop-stereo=0',
        ),
      );
      expect(out, isNot(contains('a=fmtp:63')));
      // Idempotent.
      expect(tuneOpus(out), out);
    });

    test('adds an fmtp line when Opus has none and leaves other SDP alone', () {
      const sdp = 'a=rtpmap:111 opus/48000/2\r\na=rtpmap:0 PCMU/8000';
      final out = tuneOpus(sdp);
      expect(out.split('\r\n')[1], startsWith('a=fmtp:111 maxaveragebitrate'));
      expect(tuneOpus('a=rtpmap:0 PCMU/8000'), 'a=rtpmap:0 PCMU/8000');
    });
  });
}
