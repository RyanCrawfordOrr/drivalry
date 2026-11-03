import 'package:drivalry/data/repos/leagues_repo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localWeekStart', () {
    test('a Wednesday afternoon maps to that week\'s Monday 00:00', () {
      final ws = localWeekStart(DateTime(2026, 11, 4, 15, 30)); // Wednesday
      expect(ws, DateTime(2026, 11, 2));
      expect(ws.weekday, DateTime.monday);
    });

    test(
      'Sunday 23:59 still belongs to the week that started six days ago',
      () {
        expect(
          localWeekStart(DateTime(2026, 11, 8, 23, 59, 59)),
          DateTime(2026, 11, 2),
        );
      },
    );

    test('Monday 00:00 is its own week start', () {
      expect(localWeekStart(DateTime(2026, 11, 9)), DateTime(2026, 11, 9));
    });

    test('crossing a month boundary', () {
      expect(localWeekStart(DateTime(2026, 12, 1, 9)), DateTime(2026, 11, 30));
    });

    test(
      'a week with a daylight-saving change is still seven calendar days',
      () {
        // US DST begins Sunday 2026-03-08; EU on 2026-03-29. Whatever the host
        // zone, the week start and the next week start are calendar midnights.
        for (final probe in [
          DateTime(2026, 3, 11, 12),
          DateTime(2026, 4, 1, 12),
        ]) {
          final ws = localWeekStart(probe);
          final next = nextWeekStart(ws);
          expect(ws.hour, 0);
          expect(next.hour, 0);
          expect(next.day - ws.day == 7 || next.month != ws.month, isTrue);
          expect(next.weekday, DateTime.monday);
          expect(previousWeekStart(next), ws);
        }
      },
    );

    test('date string round-trips', () {
      final ws = DateTime(2026, 1, 5);
      expect(weekStartDate(ws), '2026-01-05');
      expect(parseWeekStartDate('2026-01-05'), ws);
      expect(parseWeekStartDate('2026-01-05T00:00:00'), ws);
    });
  });

  group('projectTier', () {
    LeagueTier run(LeagueTier tier, int rank, int total, int trips) =>
        projectTier(tier: tier, rank: rank, total: total, trips: trips);

    test('zero trips demotes, except from Learner', () {
      expect(run(LeagueTier.gold, 1, 10, 0), LeagueTier.silver);
      expect(run(LeagueTier.learner, 1, 10, 0), LeagueTier.learner);
    });

    test('top five promote once the league has more than five members', () {
      expect(run(LeagueTier.bronze, 5, 6, 3), LeagueTier.silver);
      expect(run(LeagueTier.bronze, 6, 6, 3), LeagueTier.learner);
      expect(run(LeagueTier.bronze, 1, 5, 3), LeagueTier.bronze);
    });

    test('bottom five demote; the middle stays', () {
      expect(run(LeagueTier.gold, 12, 12, 2), LeagueTier.silver);
      expect(run(LeagueTier.gold, 7, 12, 2), LeagueTier.gold);
      expect(run(LeagueTier.gold, 8, 12, 2), LeagueTier.silver);
    });

    test('Chauffeur has nowhere to go up', () {
      expect(run(LeagueTier.chauffeur, 1, 10, 4), LeagueTier.chauffeur);
    });
  });
}
