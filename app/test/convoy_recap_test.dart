import 'package:drivalry/data/convoy/recap_builder.dart';
import 'package:drivalry/data/db/database.dart';
import 'package:drivalry/data/google/places_client.dart' show StopCategory;
import 'package:drivalry/data/repos/convoy_models.dart';
import 'package:flutter_test/flutter_test.dart';

ConvoyTrack _t(String user, int t, double lat, double lon) =>
    ConvoyTrack(convoyId: 'c', userId: user, t: t, lat: lat, lon: lon);

ConvoyMember _m(String id, String name, {String role = 'member'}) =>
    ConvoyMember(
      userId: id,
      handle: id,
      displayName: name,
      role: role,
      joinedAt: DateTime.utc(2026, 11, 3),
    );

void main() {
  final convoy = Convoy(
    id: 'c',
    name: 'Coast run',
    createdBy: 'lead',
    status: ConvoyStatus.ended,
    inviteCode: 'abc',
    createdAt: DateTime.utc(2026, 11, 3, 8),
    startedAt: DateTime.utc(2026, 11, 3, 9),
    endedAt: DateTime.utc(2026, 11, 3, 12),
  );

  test('distance from tracks skips long gaps; awards pick winners', () {
    final recap = buildRecap(
      convoy: convoy,
      members: [
        _m('lead', 'Ana', role: 'leader'),
        _m('m1', 'Bo'),
      ],
      tracks: [
        _t('lead', 0, 40.0, -100.0),
        _t('lead', 10000, 40.01, -100.0), // ≈ 1.11 km
        _t('lead', 20000, 40.02, -100.0), // ≈ 1.11 km
        _t('m1', 0, 40.0, -100.0),
        _t('m1', 10000, 40.01, -100.0),
        // 20 min gap: out of contact, not 100 km of driving.
        _t('m1', 10000 + 20 * 60 * 1000, 41.0, -100.0),
      ],
      stops: [
        ConvoyStop(
          id: 's1',
          convoyId: 'c',
          proposedBy: 'm1',
          category: StopCategory.food,
          name: 'Tacos',
          lat: 40,
          lon: -100,
          status: StopStatus.done,
          createdAt: DateTime.utc(2026, 11, 3),
        ),
      ],
      expenses: [
        ConvoyExpense(
          id: 'e1',
          convoyId: 'c',
          payerId: 'lead',
          amountCents: 4500,
          category: 'gas',
          createdAt: DateTime.utc(2026, 11, 3),
        ),
      ],
      summaries: [
        ConvoyTripSummary(
          userId: 'lead',
          startedAt: DateTime.utc(2026, 11, 3, 9),
          endedAt: DateTime.utc(2026, 11, 3, 12),
          distanceM: 200000,
          scored: true,
          score: 92,
          speedingSeconds: 0,
        ),
        ConvoyTripSummary(
          userId: 'm1',
          startedAt: DateTime.utc(2026, 11, 3, 9),
          endedAt: DateTime.utc(2026, 11, 3, 12),
          distanceM: 200000,
          scored: true,
          score: 74,
          speedingSeconds: 300,
        ),
      ],
      djTracks: {'m1': 7},
      now: DateTime.utc(2026, 11, 3, 12, 5),
    );

    final lead = recap.members.singleWhere((m) => m.userId == 'lead');
    final bo = recap.members.singleWhere((m) => m.userId == 'm1');
    expect(lead.distanceM, closeTo(2224, 20));
    expect(bo.distanceM, closeTo(1112, 10));
    expect(lead.averageScore, 92);
    expect(bo.speedingMinutes, 5);
    expect(bo.stopsProposed, 1);

    String? winner(String id) =>
        recap.awards.where((a) => a.id == id).map((a) => a.userId).firstOrNull;
    expect(winner('smoothest'), 'lead');
    expect(winner('lead_foot'), 'm1');
    expect(winner('most_stops'), 'm1');
    expect(winner('dj'), 'm1');
    expect(winner('navigator'), 'lead');
    expect(
      recap.awards.singleWhere((a) => a.id == 'lead_foot').honourable,
      isFalse,
    );
    expect(recap.totalCostCents, 4500);
    expect(recap.stopsDone, 1);
    expect(recap.duration, const Duration(hours: 3));
  });

  test('no awards that need data nobody has', () {
    final recap = buildRecap(
      convoy: convoy,
      members: [_m('lead', 'Ana', role: 'leader')],
      tracks: const [],
      stops: const [],
      expenses: const [],
      summaries: const [],
      now: DateTime.utc(2026, 11, 3),
    );
    expect(recap.awards.map((a) => a.id), ['navigator']);
    expect(recap.members.single.distanceM, 0);
  });

  test('round-trips through JSON', () {
    final recap = buildRecap(
      convoy: convoy,
      members: [
        _m('lead', 'Ana', role: 'leader'),
        _m('m1', 'Bo'),
      ],
      tracks: [_t('lead', 0, 40, -100), _t('lead', 5000, 40.01, -100)],
      stops: const [],
      expenses: const [],
      summaries: const [],
      now: DateTime.utc(2026, 11, 3),
    );
    final back = ConvoyRecap.fromJson(recap.toJson())!;
    expect(back.name, 'Coast run');
    expect(back.members.length, 2);
    expect(back.awards.length, recap.awards.length);
    expect(back.startedAt, recap.startedAt);
    expect(ConvoyRecap.fromJson('not json'), isNull);
    expect(ConvoyRecap.fromJson(null), isNull);
  });

  test('the cost line shows the currency with the largest total', () {
    ConvoyExpense e(String id, int cents, String currency) => ConvoyExpense(
      id: id,
      convoyId: 'c',
      payerId: 'lead',
      amountCents: cents,
      category: 'gas',
      currency: currency,
      createdAt: DateTime.utc(2026, 11, 3),
    );
    final recap = buildRecap(
      convoy: convoy,
      members: [_m('lead', 'Ana', role: 'leader')],
      tracks: const [],
      stops: const [],
      expenses: [e('1', 3000, 'USD'), e('2', 5000, 'EUR'), e('3', 1000, 'EUR')],
      summaries: const [],
      now: DateTime.utc(2026, 11, 3),
    );
    expect(recap.totalCostCents, 6000, reason: 'EUR only, never 9000');
    expect(recap.costCurrency, 'EUR');
    final back = ConvoyRecap.fromJson(recap.toJson())!;
    expect(back.costCurrency, 'EUR');
    expect(back.totalCostCents, 6000);
  });

  test('a recap stays provisional for a day while no summaries exist', () {
    final ended = DateTime.utc(2026, 11, 3, 12);
    bool fin({required bool summaries, required Duration after}) =>
        recapIsFinal(
          ended: true,
          endedAt: ended,
          hasSummaries: summaries,
          now: ended.add(after),
        );
    expect(
      recapIsFinal(ended: false, endedAt: null, hasSummaries: true, now: ended),
      isFalse,
    );
    expect(fin(summaries: false, after: const Duration(hours: 2)), isFalse);
    expect(fin(summaries: true, after: const Duration(hours: 2)), isTrue);
    expect(fin(summaries: false, after: const Duration(hours: 24)), isTrue);
    expect(
      recapIsFinal(ended: true, endedAt: null, hasSummaries: false, now: ended),
      isTrue,
      reason: 'no end time to wait on',
    );
  });
}
