import 'package:drivalry/data/repos/challenges_repo.dart';
import 'package:drivalry/data/repos/duels_repo.dart';
import 'package:drivalry/data/repos/seasons_repo.dart';
import 'package:drivalry/features/leagues/challenges/challenge_card.dart';
import 'package:drivalry/features/leagues/duels/duel_card.dart';
import 'package:drivalry/features/leagues/duels/duels_screen.dart';
import 'package:drivalry/features/seasons/season_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/widget_support.dart';

DuelParty party(String id) =>
    DuelParty(userId: id, handle: id, displayName: id.toUpperCase());

Duel duel({
  DuelStatus status = DuelStatus.pending,
  DuelMetric metric = DuelMetric.xp,
  DateTime? endsAt,
  DateTime? finishedAt,
  String? winnerId,
  String? loserBadgeId,
}) => Duel(
  id: 'd1',
  challenger: party('me'),
  opponent: party('sam'),
  metric: metric,
  status: status,
  createdAt: DateTime(2026, 11, 1),
  startsAt: DateTime(2026, 11, 2, 9),
  endsAt: endsAt ?? DateTime(2026, 11, 9, 9),
  finishedAt: finishedAt,
  winnerId: winnerId,
  loserBadgeId: loserBadgeId,
);

Widget wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  final now = DateTime(2026, 11, 3, 12);

  group('DuelCard', () {
    testWidgets('pending: who is waiting on whom', (tester) async {
      await tester.pumpWidget(
        wrap(DuelCard(duel: duel(), me: 'sam', now: now)),
      );
      expect(find.text('Waiting for your answer'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('@me'), findsOneWidget);

      await tester.pumpWidget(wrap(DuelCard(duel: duel(), me: 'me', now: now)));
      expect(find.text('Waiting for @sam to answer'), findsOneWidget);
    });

    testWidgets('running: values, leader and time left', (tester) async {
      final d = duel(status: DuelStatus.active);
      await tester.pumpWidget(
        wrap(
          DuelCard(
            duel: d,
            me: 'me',
            now: now,
            board: const DuelScoreboard(
              challenger: DuelValue(value: 180, trips: 4),
              opponent: DuelValue(value: 120, trips: 3),
            ),
          ),
        ),
      );
      expect(find.text('180 XP'), findsOneWidget);
      expect(find.text('120 XP'), findsOneWidget);
      expect(find.textContaining('You lead'), findsOneWidget);
      expect(find.textContaining('5d 21h left'), findsOneWidget);

      await tester.pumpWidget(
        wrap(
          DuelCard(
            duel: d,
            me: 'me',
            now: now,
            board: const DuelScoreboard(
              challenger: DuelValue(value: 10, trips: 1),
              opponent: DuelValue(value: 10, trips: 1),
            ),
          ),
        ),
      );
      expect(find.textContaining('Level'), findsOneWidget);
    });

    testWidgets('score-average duel shows the three-trip floor', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          DuelCard(
            duel: duel(status: DuelStatus.active, metric: DuelMetric.scoreAvg),
            me: 'me',
            now: now,
            board: const DuelScoreboard(
              challenger: DuelValue(value: 0, trips: 2),
              opponent: DuelValue(value: 88.5, trips: 3),
            ),
          ),
        ),
      );
      expect(find.text('2 of 3 trips'), findsOneWidget);
      expect(find.text('88.5'), findsOneWidget);
      expect(find.textContaining('@sam leads'), findsOneWidget);
    });

    testWidgets('finished: the loser sees their badge and its end date', (
      tester,
    ) async {
      final d = duel(
        status: DuelStatus.finished,
        finishedAt: DateTime(2026, 11, 9, 10),
        winnerId: 'sam',
        loserBadgeId: 'sunday_driver',
      );
      await tester.pumpWidget(wrap(DuelCard(duel: d, me: 'me', now: now)));
      expect(
        find.text('You lost · you wear Sunday Driver until Nov 16'),
        findsOneWidget,
      );
      await tester.pumpWidget(wrap(DuelCard(duel: d, me: 'sam', now: now)));
      expect(
        find.text('You won · they wear Sunday Driver until Nov 16'),
        findsOneWidget,
      );
    });

    test('status lines for draws, declines and expiries', () {
      expect(
        duelStatusLine(duel(status: DuelStatus.finished), 'me', null, now),
        'Draw',
      );
      expect(
        duelStatusLine(duel(status: DuelStatus.declined), 'me', null, now),
        'Declined',
      );
      expect(
        duelStatusLine(duel(status: DuelStatus.expired), 'me', null, now),
        'Expired unanswered',
      );
    });
  });

  group('ChallengeProgressView', () {
    GroupChallenge challenge(
      ChallengeGoal goal,
      int target, {
      String status = 'active',
    }) => GroupChallenge(
      id: 'c1',
      leagueId: 'L1',
      createdBy: 'me',
      goal: goal,
      target: target,
      startsAt: DateTime(2026, 11, 2),
      endsAt: DateTime(2026, 11, 9),
      status: status,
      value: status == 'active' ? null : 3,
    );

    testWidgets('shows title, count and the end date', (tester) async {
      final c = challenge(ChallengeGoal.cleanTrips, 25);
      final p = computeChallengeProgress(
        c,
        ['a', 'b'],
        [
          for (var i = 0; i < 17; i++)
            const ChallengeTrip(
              userId: 'a',
              score: 90,
              reckless: false,
              phoneHandling: false,
            ),
        ],
      );
      await tester.pumpWidget(
        wrap(ChallengeProgressView(challenge: c, progress: p, now: now)),
      );
      expect(find.text('Clean trips · 25 trips'), findsOneWidget);
      expect(find.text('17 of 25 trips'), findsOneWidget);
      expect(find.textContaining('Ends Mon, Nov 9'), findsOneWidget);
      expect(find.textContaining('5 days left'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.68, 0.001));
    });

    testWidgets('everyone-drives wording and the cancel button', (
      tester,
    ) async {
      final c = challenge(ChallengeGoal.everyoneDrives, 3);
      final p = computeChallengeProgress(
        c,
        ['a', 'b', 'c'],
        [
          for (var i = 0; i < 3; i++)
            const ChallengeTrip(
              userId: 'a',
              score: 90,
              reckless: false,
              phoneHandling: false,
            ),
        ],
      );
      var cancelled = false;
      await tester.pumpWidget(
        wrap(
          ChallengeProgressView(
            challenge: c,
            progress: p,
            now: now,
            onCancel: () => cancelled = true,
          ),
        ),
      );
      expect(find.text('1 of 3 members have 3 trips'), findsOneWidget);
      await tester.tap(find.byTooltip('Call off'));
      expect(cancelled, isTrue);
    });

    test('result lines', () {
      expect(
        challengeResultLine(
          challenge(ChallengeGoal.cleanTrips, 25, status: 'succeeded'),
        ),
        'Met! Everyone earned Clean Sweep.',
      );
      expect(
        challengeResultLine(
          challenge(ChallengeGoal.cleanTrips, 25, status: 'failed'),
        ),
        'Missed: 3 of 25 trips.',
      );
      expect(
        challengeProgressLine(
          challenge(ChallengeGoal.scoreAvg, 85),
          const ChallengeProgress(
            value: 86.25,
            needed: 85,
            target: 85,
            members: 2,
            met: true,
            perMember: [],
          ),
        ),
        'Averaging 86.3, target 85',
      );
    });
  });

  group('SeasonCardView', () {
    testWidgets('days left, numbers and the Wrapped link', (tester) async {
      var wrapped = false;
      await tester.pumpWidget(
        wrap(
          SeasonCardView(
            season: builtInSeasons.first,
            stats: const SeasonStats(
              trips: 12,
              xp: 640,
              scoreAvg: 87.4,
              cleanTrips: 9,
              phoneFreeTrips: 11,
              bestScore: 98,
            ),
            now: now,
            onWrapped: () => wrapped = true,
            onAllSeasons: () {},
          ),
        ),
      );
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('59 days left'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('640'), findsOneWidget);
      expect(find.text('87'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      await tester.tap(find.text('Season Wrapped'));
      expect(wrapped, isTrue);
    });
  });

  testWidgets('DuelsScreen explains itself in an offline build', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DuelsScreen())),
    );
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Duels'), findsOneWidget);
    expect(find.text('Not available in this version yet.'), findsOneWidget);
    await unmountAndSettle(tester);
  });
}
