import 'dart:math';

import 'package:drivalry/features/convoy/games/games_core.dart';
import 'package:drivalry/features/convoy/games/trivia_questions.dart';
import 'package:flutter_test/flutter_test.dart';

GameMessage msg(String from, Map<String, dynamic> p, {int t = 0}) =>
    GameMessage(from: from, t: t, payload: p);

void main() {
  test('the trivia bank has 60 well-formed questions', () {
    expect(triviaQuestions, hasLength(60));
    for (final q in triviaQuestions) {
      expect(q.prompt, isNotEmpty);
      expect(q.choices, hasLength(4));
      expect(q.choices.toSet(), hasLength(4));
      expect(q.answer, inInclusiveRange(0, 3));
    }
    expect(triviaQuestions.map((q) => q.prompt).toSet(), hasLength(60));
  });

  group('license-plate bingo', () {
    test('toggle marks and unmarks, broadcasting my whole list', () {
      final b = PlatesBingo('me');
      expect(b.toggle('TX'), {
        'game': 'plates',
        'event': 'mark',
        'state': ['TX'],
      });
      expect(b.toggle('CA')['state'], ['CA', 'TX']);
      expect(b.toggle('TX')['state'], ['CA']);
      expect(b.toggle('ZZ'), isEmpty);
      expect(plateStates, hasLength(51));
    });

    test('peer marks feed the standings, highest first', () {
      final b = PlatesBingo('me')..toggle('TX');
      b.onMessage(
        msg('sam', {
          'game': 'plates',
          'event': 'mark',
          'state': ['CA', 'NY', 'ZZ'],
        }),
      );
      b.onMessage(
        msg('eve', {
          'game': 'plates',
          'event': 'mark',
          'state': ['CA'],
        }),
      );
      b.onMessage(msg('eve', {'game': 'trivia', 'event': 'mark'}));
      expect(b.standings(), [('sam', 2), ('eve', 1), ('me', 1)]);
    });
  });

  group('trivia', () {
    test('the host is the lowest id in the mesh', () {
      expect(Trivia.hostOf({'bbb', 'ccc'}, 'aaa'), 'aaa');
      expect(Trivia('zzz').isHost({'aaa'}), isFalse);
      expect(Trivia('a').isHost({}), isTrue);
    });

    test('a round: question, answers, reveal, scores, deadline', () {
      var now = 1000;
      final host = Trivia('aaa', now: () => now);
      final guest = Trivia('bbb', now: () => now);

      final q = host.nextQuestion(random: Random(1));
      expect(q['game'], 'trivia');
      expect(q['event'], 'question');
      expect(q['endsAt'], now + 20_000);
      guest.onMessage(msg('aaa', q.cast<String, dynamic>()));
      expect(guest.current, same(host.current));
      expect(guest.open, isTrue);

      final right = host.current!.answer;
      final wrong = (right + 1) % 4;
      final a1 = guest.answer(right)!;
      expect(a1['event'], 'answer');
      expect(guest.answer(wrong), isNull); // one answer per player
      host.onMessage(msg('bbb', a1.cast<String, dynamic>()));
      expect(host.answer(wrong), isNotNull);
      // An answer to a different question is ignored.
      host.onMessage(
        msg('ccc', {
          'game': 'trivia',
          'event': 'answer',
          'index': -1,
          'choice': right,
        }),
      );
      expect(host.answers.keys, unorderedEquals(['aaa', 'bbb']));

      final reveal = host.reveal();
      expect(reveal['right'], ['bbb']);
      expect(reveal['answer'], right);
      expect(host.scores, {'bbb': 1});
      expect(host.open, isFalse);
      guest.onMessage(msg('aaa', reveal.cast<String, dynamic>()));
      expect(guest.scores, {'bbb': 1});
      expect(guest.open, isFalse);
      expect(
        host.spokenResult(
          reveal.cast<String, dynamic>(),
          (id) => id.toUpperCase(),
        ),
        'BBB got it: ${host.current!.choices[right]}.',
      );

      // The deadline closes answers; questions do not repeat.
      final q2 = host.nextQuestion(random: Random(2));
      guest.onMessage(msg('aaa', q2.cast<String, dynamic>()));
      now += 20_001;
      expect(guest.open, isFalse);
      expect(guest.answer(0), isNull);
      expect(host.asked.toSet(), hasLength(2));
    });

    test('when nobody is right the answer is read out', () {
      final t = Trivia('a', now: () => 0);
      t.nextQuestion(random: Random(3));
      final r = t.reveal();
      expect(
        t.spokenResult(r.cast<String, dynamic>(), (id) => id),
        startsWith('Nobody got it. The answer was '),
      );
      expect(t.reveal(), isNotEmpty);
      expect(Trivia('b').reveal(), isEmpty);
    });

    test('the bank recycles once every question has been asked', () {
      final t = Trivia('a', now: () => 0);
      for (var i = 0; i < triviaQuestions.length; i++) {
        t.nextQuestion(random: Random(i));
      }
      expect(t.asked.toSet(), hasLength(triviaQuestions.length));
      t.nextQuestion(random: Random(99));
      expect(t.asked, hasLength(1));
    });
  });

  group('scavenger hunt', () {
    test('first claim wins, ties go to the lower id, everyone agrees', () {
      final a = Scavenger('aaa');
      final b = Scavenger('bbb');
      final ca = a.claim('Red barn', 500)!;
      final cb = b.claim('Red barn', 400)!;
      a.onMessage(msg('bbb', cb.cast<String, dynamic>()));
      b.onMessage(msg('aaa', ca.cast<String, dynamic>()));
      expect(a.claims['Red barn'], ('bbb', 400));
      expect(b.claims['Red barn'], ('bbb', 400));

      final ta = a.claim('Horse', 900)!;
      final tb = b.claim('Horse', 900)!;
      a.onMessage(msg('bbb', tb.cast<String, dynamic>()));
      b.onMessage(msg('aaa', ta.cast<String, dynamic>()));
      expect(a.claims['Horse']!.$1, 'aaa');
      expect(b.claims['Horse']!.$1, 'aaa');

      expect(a.tally(), {'bbb': 1, 'aaa': 1});
      expect(a.claim('Red barn', 1), isNull);
      expect(a.claim('Unicorn', 1), isNull);
      a.onMessage(
        msg('zzz', {
          'game': 'scavenger',
          'event': 'claim',
          'item': 'Unicorn',
          't': 1,
        }),
      );
      expect(a.claims.containsKey('Unicorn'), isFalse);
    });
  });

  group('smoothest leg', () {
    test('ranks by steadiness, never by speed', () {
      final s = SmoothestLeg();
      // "fast" is quick but steady; "slow" is slow but jerky; "few" has
      // too little data to rank.
      for (var i = 0; i < 10; i++) {
        s.addSpeed('fast', i * 1000, 30 + (i.isEven ? 0.2 : -0.2));
        s.addSpeed('slow', i * 1000, 10 + (i.isEven ? 6 : -6));
        if (i < 4) s.addSpeed('few', i * 1000, 0);
      }
      final r = s.ranking();
      expect(r.map((e) => e.$1), ['fast', 'slow']);
      expect(SmoothestLeg.label(r[0].$2), 'Glassy');
      expect(SmoothestLeg.label(r[1].$2), 'Choppy');
    });

    test('old samples fall out of the window', () {
      final s = SmoothestLeg(windowMs: 1000);
      for (var i = 0; i < 6; i++) {
        s.addSpeed('a', i * 100, 1);
      }
      expect(s.ranking(), hasLength(1));
      s.addSpeed('a', 5000, 1);
      expect(s.ranking(), isEmpty);
    });

    test('labels never mention a number', () {
      expect(SmoothestLeg.label(1), 'Glassy');
      expect(SmoothestLeg.label(2), 'Steady');
      expect(SmoothestLeg.label(4), 'Wavy');
      expect(SmoothestLeg.label(9), 'Choppy');
    });
  });
}
