import 'dart:async';

import 'package:drivalry/app/ui/ui.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/repos/challenges_repo.dart';
import 'package:drivalry/data/repos/duels_repo.dart';
import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:drivalry/data/supabase/supabase_providers.dart';
import 'package:drivalry/data/sync/outbox.dart';
import 'package:drivalry/features/badges/badge_moments.dart';
import 'package:drivalry/features/badges/badges_screen.dart';
import 'package:drivalry/features/badges/moment_ledger.dart';
import 'package:drivalry/features/leagues/challenges/challenge_card.dart';
import 'package:drivalry/features/leagues/duels/duel_moments.dart';
import 'package:drivalry/features/leagues/promotion_moments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/scored_trips.dart';
import 'support/sqlite_support.dart';
import 'support/widget_support.dart';

/// Only the week rows; everything else is never called here.
class _WeeksApi implements LeaguesApi {
  _WeeksApi(this.rows);
  final List<(String, String, List<dynamic>)> rows;

  @override
  Future<List<(String, String, List<dynamic>)>> recentWeeks(
    String sinceDate,
  ) async => rows;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget scope(AppDatabase db, Widget body, {List<Object> extra = const []}) =>
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        currentUserIdProvider.overrideWithValue('me'),
        cloudConfiguredProvider.overrideWithValue(true),
        supabaseProvider.overrideWithValue(null),
        ...extra.cast(),
      ],
      child: MaterialApp(home: Scaffold(body: body)),
    );

Future<void> dismiss(WidgetTester tester) async {
  await tester.tap(find.text('Nice'));
  await tester.pumpAndSettle();
}

void main() {
  final skip = skipWithoutSqlite() != null;
  late AppDatabase db;
  setUp(() {
    Haptics.enabled = false;
    db = memoryDatabase();
  });
  tearDown(() => db.close());

  group('MomentLedger', () {
    test('claims an id once, across instances', () async {
      final ledger = MomentLedger(db);
      expect(await ledger.shown('x'), isFalse);
      expect(await ledger.claim('x'), isTrue);
      expect(await ledger.claim('x'), isFalse);
      expect(await ledger.shown('x'), isTrue);
      // Persisted: a fresh ledger over the same database agrees.
      expect(await MomentLedger(db).claim('x'), isFalse);
      expect(await MomentLedger(db).claim('y'), isTrue);
    }, skip: skip);

    test('recentlyAt tolerates an hour of skew and nothing older', () {
      final now = DateTime(2026, 11, 3, 12);
      const week = Duration(days: 7);
      expect(
        recentlyAt(now.subtract(const Duration(days: 2)), now, week),
        true,
      );
      expect(
        recentlyAt(now.subtract(const Duration(days: 8)), now, week),
        false,
      );
      expect(recentlyAt(now.add(const Duration(minutes: 30)), now, week), true);
      expect(recentlyAt(now.add(const Duration(days: 1)), now, week), false);
      expect(recentlyAt(null, now, week), false);
    });
  });

  group('promotion', () {
    test(
      'the week-badge pass emits one event per promoted week of mine',
      () async {
        final api = _WeeksApi([
          (
            'G0',
            '2026-10-26',
            [
              {
                'user_id': 'me',
                'rank': 2,
                'tier_before': 'bronze',
                'tier_after': 'silver',
              },
              {
                'user_id': 'u2',
                'rank': 1,
                'tier_before': 'bronze',
                'tier_after': 'silver',
              },
            ],
          ),
          (
            'L1',
            '2026-10-19',
            [
              {
                'user_id': 'me',
                'rank': 9,
                'tier_before': 'bronze',
                'tier_after': 'bronze',
              },
            ],
          ),
        ]);
        final worker = OutboxWorker(db, now: () => 1);
        addTearDown(worker.dispose);
        final repo = LeaguesRepo(
          db: db,
          api: api,
          outbox: worker,
          userId: () => 'me',
        );
        final events = <PromotionEvent>[];
        final sub = repo.promotions.listen(events.add);
        await repo.awardRecentWeekBadges(
          (_) async => true,
          now: DateTime(2026, 11, 3),
        );
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(events, hasLength(1));
        expect(events.single.id, 'promotion:G0:2026-10-26');
        expect(events.single.from, LeagueTier.bronze);
        expect(events.single.to, LeagueTier.silver);
      },
      skip: skip,
    );

    testWidgets('PromotionMoments shows "Promoted" once per league and week', (
      tester,
    ) async {
      final controller = StreamController<PromotionEvent>.broadcast();
      addTearDown(controller.close);
      PromotionEvent event() => const PromotionEvent(
        leagueId: 'L1',
        weekStart: '2026-10-26',
        from: LeagueTier.silver,
        to: LeagueTier.gold,
      );
      Widget build() => scope(
        db,
        const PromotionMoments(child: SizedBox.shrink()),
        extra: [promotionEventsProvider.overrideWith((_) => controller.stream)],
      );
      await tester.pumpWidget(build());
      await tester.pump();
      controller.add(event());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('PROMOTED'), findsOneWidget);
      expect(find.text('Silver → Gold'), findsOneWidget);
      await dismiss(tester);

      // The same promotion again, in the same session: nothing.
      controller.add(event());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('PROMOTED'), findsNothing);

      // And after a restart over the same database: still nothing.
      await unmountAndSettle(tester);
      await tester.pumpWidget(build());
      await tester.pump();
      controller.add(event());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('PROMOTED'), findsNothing);
      await unmountAndSettle(tester);
    }, skip: skip);
  });

  group('duel won', () {
    Duel won() => Duel(
      id: 'd9',
      challenger: const DuelParty(
        userId: 'me',
        handle: 'me',
        displayName: 'Me',
      ),
      opponent: const DuelParty(
        userId: 'sam',
        handle: 'sam',
        displayName: 'Sam',
      ),
      metric: DuelMetric.phoneFree,
      status: DuelStatus.finished,
      createdAt: DateTime.now().subtract(const Duration(days: 9)),
      finishedAt: DateTime.now().subtract(const Duration(days: 1)),
      winnerId: 'me',
      loserBadgeId: 'sunday_driver',
    );

    test('wonRecently keeps my recent wins only', () {
      final now = DateTime.now();
      final mine = won();
      expect(wonRecently([mine], 'me', now), [mine]);
      expect(wonRecently([mine], 'sam', now), isEmpty);
      expect(
        wonRecently([mine], 'me', now.add(const Duration(days: 30))),
        isEmpty,
      );
    });

    testWidgets('DuelMoments celebrates a win once', (tester) async {
      Widget build() => scope(
        db,
        const DuelMoments(child: SizedBox.shrink()),
        extra: [
          myDuelsProvider.overrideWith((_) => Stream.value([won()])),
        ],
      );
      await tester.pumpWidget(build());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('DUEL WON'), findsOneWidget);
      expect(find.text('You beat @sam on phone-free trips'), findsOneWidget);
      expect(find.text('Sunday Driver'), findsOneWidget);
      await dismiss(tester);
      await unmountAndSettle(tester);

      await tester.pumpWidget(build());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('DUEL WON'), findsNothing);
      await unmountAndSettle(tester);
    }, skip: skip);
  });

  group('challenge met', () {
    testWidgets('ChallengeCard celebrates a met challenge once', (
      tester,
    ) async {
      final met = GroupChallenge(
        id: 'c7',
        leagueId: 'L1',
        createdBy: 'sam',
        goal: ChallengeGoal.cleanTrips,
        target: 25,
        startsAt: DateTime.now().subtract(const Duration(days: 8)),
        endsAt: DateTime.now().subtract(const Duration(days: 1)),
        status: 'succeeded',
        value: 27,
        finalizedAt: DateTime.now().subtract(const Duration(hours: 20)),
      );
      Widget build() => scope(
        db,
        const SingleChildScrollView(child: ChallengeCard(leagueId: 'L1')),
        extra: [
          leagueChallengesProvider.overrideWith((_, _) async => [met]),
        ],
      );
      await tester.pumpWidget(build());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('CHALLENGE MET'), findsOneWidget);
      expect(find.text('Clean Sweep'), findsOneWidget);
      await dismiss(tester);
      expect(find.text('Met! Everyone earned Clean Sweep.'), findsOneWidget);
      await unmountAndSettle(tester);

      await tester.pumpWidget(build());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('CHALLENGE MET'), findsNothing);
      await unmountAndSettle(tester);
    }, skip: skip);
  });

  group('badge earned', () {
    testWidgets('BadgeMoments celebrates a new badge once', (tester) async {
      await db.awardBadge('perfect_100', DateTime.now().millisecondsSinceEpoch);
      Widget build() => scope(db, const BadgeMoments(child: SizedBox.shrink()));
      await tester.pumpWidget(build());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('BADGE EARNED'), findsOneWidget);
      expect(find.text('Flawless'), findsOneWidget);
      expect(find.text('A trip scored 100.'), findsOneWidget);
      await dismiss(tester);
      await unmountAndSettle(tester);

      await tester.pumpWidget(build());
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('BADGE EARNED'), findsNothing);
      await unmountAndSettle(tester);
    }, skip: skip);

    testWidgets('an old award is listed, not celebrated', (tester) async {
      await db.awardBadge(
        'first_trip',
        DateTime.now()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch,
      );
      await tester.pumpWidget(scope(db, const BadgesScreen()));
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('BADGE EARNED'), findsNothing);
      expect(find.text('First Trip'), findsOneWidget);
      await unmountAndSettle(tester);
    }, skip: skip);

    testWidgets(
      'BadgesScreen: streak tiles, the earned kicker, progress on streak '
      'badges and a lock pill on the rest',
      (tester) async {
        // Three clean, phone-free trips: Five Clean is 3/5, Hands Off 3/10.
        for (var i = 0; i < 3; i++) {
          await seedScoredTrip(
            db,
            id: 't$i',
            startedAt: DateTime(2026, 10, 10 + i, 8).millisecondsSinceEpoch,
            score: 90,
          );
        }
        await db.awardBadge(
          'first_trip',
          DateTime(2026, 10, 10, 9).millisecondsSinceEpoch,
        );
        await tester.pumpWidget(scope(db, const BadgesScreen()));
        await pumpFor(tester, const Duration(seconds: 2));
        expect(find.text('Clean streak'), findsOneWidget);
        expect(find.text('Phone-free'), findsOneWidget);
        expect(find.text('1 OF 20 BADGES EARNED'), findsOneWidget);
        expect(find.text('3/5'), findsOneWidget);
        expect(find.text('3/10'), findsOneWidget);
        expect(find.text('Locked'), findsWidgets);
        await tester.dragUntilVisible(
          find.text('DISHONOURABLE'),
          find.byType(ListView),
          const Offset(0, -400),
        );
        await pumpFor(tester, const Duration(seconds: 1));
        expect(find.text('DISHONOURABLE'), findsOneWidget);
        await unmountAndSettle(tester);
      },
      skip: skip,
    );
  });
}
