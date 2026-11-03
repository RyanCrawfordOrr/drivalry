import 'package:drivalry/data/spotify/spotify_client.dart';
import 'package:drivalry/features/convoy/music/dj_core.dart';
import 'package:flutter_test/flutter_test.dart';

SpotifyTrack track(String id) => SpotifyTrack(
  uri: 'spotify:track:$id',
  name: id,
  artists: 'x',
  durationMs: 180000,
);

void main() {
  var now = 100_000;
  setUp(() => now = 100_000);
  DjCore core(String id) => DjCore(selfId: id, now: () => now);
  DjCommand cmd(String from, Map<String, dynamic> p) =>
      DjCommand(from: from, t: now, payload: p);

  group('claiming', () {
    test('the first claim wins locally and is announced', () {
      final c = core('mmm');
      final fx = c.claim();
      expect(c.isDj, isTrue);
      expect(
        fx.single,
        isA<SendDj>().having((e) => e.payload['cmd'], 'cmd', 'claim'),
      );
    });

    test('the lower user id wins, whichever order claims arrive', () {
      final c = core('mmm')..claim();
      expect(
        c.onCommand(cmd('aaa', {'cmd': 'claim'}), participants: {'aaa'}),
        isEmpty,
      );
      expect(c.dj, 'aaa');

      // A higher id claiming while a lower id holds it: the holder re-asserts.
      final d = core('aaa')..claim();
      final fx = d.onCommand(
        cmd('zzz', {'cmd': 'claim'}),
        participants: {'zzz'},
      );
      expect(d.dj, 'aaa');
      expect(fx.single, isA<SendDj>());

      // A bystander ignores the losing claim.
      final e = core('mmm');
      e.onCommand(cmd('aaa', {'cmd': 'claim'}), participants: {});
      expect(
        e.onCommand(cmd('zzz', {'cmd': 'claim'}), participants: {}),
        isEmpty,
      );
      expect(e.dj, 'aaa');
    });

    test('release clears only the holder', () {
      final c = core('mmm');
      c.onCommand(cmd('aaa', {'cmd': 'claim'}), participants: {});
      c.onCommand(cmd('bbb', {'cmd': 'release'}), participants: {});
      expect(c.dj, 'aaa');
      c.onCommand(cmd('aaa', {'cmd': 'release'}), participants: {});
      expect(c.dj, isNull);
      expect(c.release(), isEmpty);
      c.claim();
      expect(c.release().single, isA<SendDj>());
      expect(c.dj, isNull);
    });
  });

  group('clock offsets', () {
    test('median of the last five samples', () {
      final o = ClockOffset();
      // sentAt 0, rtt 100 → midpoint 50; peerNow 1050 → offset 1000.
      o.addSample(sentAt: 0, peerNow: 1050, receivedAt: 100);
      expect(o.offsetMs, 1000);
      for (final v in [1010, 990, 5000, 1005, 995, 1000]) {
        o.addSample(sentAt: 0, peerNow: v + 50, receivedAt: 100);
      }
      expect(o.sampleCount, 5);
      // Last five: 990, 5000, 1005, 995, 1000 → the outlier does not win.
      expect(o.offsetMs, 1000);
    });

    test('ping/pong feeds the offset for that peer only', () {
      final c = core('mmm');
      final send = c.ping('ppp').single as SendDj;
      expect(send.to, 'ppp');
      expect(send.payload, {'cmd': 'ping', 't': now});
      now += 200;
      // Peer clock 1 s ahead of ours at the round-trip midpoint.
      c.onCommand(
        cmd('ppp', {'cmd': 'pong', 't': now - 200, 'rt': (now - 100) + 1000}),
        participants: {},
      );
      expect(c.offsets['ppp']!.offsetMs, 1000);

      // An unsolicited pong is ignored.
      c.onCommand(
        cmd('qqq', {'cmd': 'pong', 't': 1, 'rt': 2}),
        participants: {},
      );
      expect(c.offsets.containsKey('qqq'), isFalse);

      // Answering a ping echoes t and adds our clock.
      final pong =
          c
                  .onCommand(
                    cmd('ppp', {'cmd': 'ping', 't': 42}),
                    participants: {},
                  )
                  .single
              as SendDj;
      expect(pong.to, 'ppp');
      expect(pong.payload, {'cmd': 'pong', 't': 42, 'rt': now});
    });
  });

  group('playing', () {
    test('the DJ schedules 1.5 s ahead and counts the track', () {
      final c = core('mmm')..claim();
      c.enqueue(track('a'));
      c.enqueue(track('b'));
      final fx = c.playNext();
      final send = fx.whereType<SendDj>().single;
      expect(send.payload['cmd'], 'play');
      expect(send.payload['uri'], 'spotify:track:a');
      expect(send.payload['positionMs'], 0);
      expect(send.payload['atT'], now + 1500);
      expect((send.payload['track'] as Map)['name'], 'a');
      final sched = fx.whereType<SchedulePlay>().single;
      expect(sched.atLocalMs, now + 1500);
      expect(sched.positionMs, 0);
      expect(c.queue.map((t) => t.name), ['b']);
      expect(c.current?.name, 'a');
      expect(c.tracksByDj['mmm'], 1);
      now += 1500 + 4000;
      expect(c.expectedPositionMs(), 4000);
    });

    test('an empty queue pauses everyone', () {
      final c = core('mmm')..claim();
      final fx = c.playNext();
      expect(fx.whereType<PauseAll>(), hasLength(1));
      expect(fx.whereType<SendDj>().single.payload['cmd'], 'pause');
    });

    test('only the DJ starts playback', () {
      final c = core('mmm');
      c.enqueue(track('a'));
      expect(c.playNext(), isEmpty);
      expect(c.current, isNull);
    });

    test(
      "a play command from the DJ is shifted by that peer's clock offset",
      () {
        final c = core('mmm');
        c.onCommand(cmd('aaa', {'cmd': 'claim'}), participants: {});
        // aaa's clock runs 1 s ahead of ours.
        c.ping('aaa');
        c.onCommand(
          cmd('aaa', {'cmd': 'pong', 't': now, 'rt': now + 1000}),
          participants: {},
        );
        final fx = c.onCommand(
          cmd('aaa', {
            'cmd': 'play',
            'uri': 'spotify:track:z',
            'positionMs': 0,
            'atT': now + 2500,
            'track': track('z').toJson(),
          }),
          participants: {},
        );
        final s = fx.single as SchedulePlay;
        expect(s.uri, 'spotify:track:z');
        expect(s.atLocalMs, now + 1500);
        expect(c.current?.name, 'z');
        expect(c.tracksByDj['aaa'], 1);
      },
    );

    test('play from someone who is not the DJ is ignored', () {
      final c = core('mmm');
      c.onCommand(cmd('aaa', {'cmd': 'claim'}), participants: {});
      expect(
        c.onCommand(
          cmd('bbb', {'cmd': 'play', 'uri': 'u', 'atT': 1}),
          participants: {},
        ),
        isEmpty,
      );
      expect(c.current, isNull);
    });

    test('a late arrival starts now at a caught-up position', () {
      final late = DjCore.localStart(
        atT: 10_000,
        positionMs: 0,
        offsetMs: 0,
        nowMs: 10_700,
      );
      expect(late.atLocalMs, 10_700);
      expect(late.positionMs, 700);
      final early = DjCore.localStart(
        atT: 10_000,
        positionMs: 500,
        offsetMs: 0,
        nowMs: 9_000,
      );
      expect(early, (atLocalMs: 10_000, positionMs: 500));
    });

    test('pause from the DJ stops expectations', () {
      final c = core('mmm');
      c.onCommand(cmd('aaa', {'cmd': 'claim'}), participants: {});
      c.onCommand(
        cmd('aaa', {'cmd': 'play', 'uri': 'u', 'atT': now}),
        participants: {},
      );
      expect(c.expectedPositionMs(), 0);
      final fx = c.onCommand(cmd('aaa', {'cmd': 'pause'}), participants: {});
      expect(fx.single, isA<PauseAll>());
      expect(c.expectedPositionMs(), isNull);
      // Nobody else can pause the room.
      expect(
        c.onCommand(cmd('bbb', {'cmd': 'pause'}), participants: {}),
        isEmpty,
      );
    });
  });

  group('resync', () {
    test('seeks only past 500 ms of drift', () {
      final c = core('mmm')..claim();
      c.enqueue(track('a'));
      c.playNext();
      now += 1500 + 10_000; // expected position 10 000
      NowPlaying np(int progress, {String id = 'a', bool playing = true}) =>
          NowPlaying(
            isPlaying: playing,
            progressMs: progress,
            track: track(id),
          );
      expect(c.resyncTarget(np(10_300)), isNull);
      expect(c.resyncTarget(np(9_400)), 10_000);
      expect(c.resyncTarget(np(10_000, id: 'other')), 10_000);
      expect(c.resyncTarget(np(10_000, playing: false)), 10_000);
      expect(c.resyncTarget(null), 10_000);
    });

    test('nothing to sync before a track starts', () {
      expect(core('m').resyncTarget(null), isNull);
    });
  });

  group('skip votes', () {
    test('a majority of the mesh makes the DJ skip', () {
      final c = core('mmm')..claim();
      c.enqueue(track('a'));
      c.enqueue(track('b'));
      c.playNext();
      final peers = {'aaa', 'bbb'}; // three participants including me
      var fx = c.voteSkip(peers);
      expect(fx.whereType<SendDj>().single.payload['cmd'], 'skip-vote');
      expect(c.current?.name, 'a');
      fx = c.onCommand(cmd('aaa', {'cmd': 'skip-vote'}), participants: peers);
      expect(c.current?.name, 'b');
      expect(fx.whereType<SendDj>().single.payload['cmd'], 'play');
      expect(c.skipVotes, isEmpty); // cleared for the new track
    });

    test('non-DJs only record votes', () {
      final c = core('mmm');
      c.onCommand(cmd('aaa', {'cmd': 'claim'}), participants: {});
      expect(
        c.onCommand(
          cmd('bbb', {'cmd': 'skip-vote'}),
          participants: {'aaa', 'bbb'},
        ),
        isEmpty,
      );
      expect(c.skipVotes, {'bbb'});
      expect(c.hasMajority({'aaa', 'bbb'}), isFalse);
    });
  });

  test('median and clamp helpers', () {
    expect(DjCore.median([]), 0);
    expect(DjCore.median([3, 1, 2]), 2);
    expect(DjCore.clampPosition(-5), 0);
  });
}
