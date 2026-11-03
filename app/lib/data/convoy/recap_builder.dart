import 'dart:convert';

import '../db/database.dart' show ConvoyTrack;
import '../google/routes_client.dart' show LatLon;
import '../repos/convoy_models.dart';
import 'settle_up.dart';

/// One car's numbers in the recap.
class RecapMember {
  const RecapMember({
    required this.userId,
    required this.name,
    required this.distanceM,
    required this.points,
    this.averageScore,
    this.speedingMinutes = 0,
    this.stopsProposed = 0,
    this.djTracks = 0,
  });

  final String userId;
  final String name;

  /// From received positions (not from the cloud).
  final double distanceM;
  final int points;
  final double? averageScore;
  final double speedingMinutes;
  final int stopsProposed;
  final int djTracks;

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'name': name,
    'distance_m': distanceM,
    'points': points,
    'average_score': averageScore,
    'speeding_minutes': speedingMinutes,
    'stops_proposed': stopsProposed,
    'dj_tracks': djTracks,
  };

  factory RecapMember.fromJson(Map<String, dynamic> j) => RecapMember(
    userId: j['user_id'] as String,
    name: j['name'] as String? ?? '',
    distanceM: (j['distance_m'] as num?)?.toDouble() ?? 0,
    points: (j['points'] as num?)?.toInt() ?? 0,
    averageScore: (j['average_score'] as num?)?.toDouble(),
    speedingMinutes: (j['speeding_minutes'] as num?)?.toDouble() ?? 0,
    stopsProposed: (j['stops_proposed'] as num?)?.toInt() ?? 0,
    djTracks: (j['dj_tracks'] as num?)?.toInt() ?? 0,
  );
}

/// An award with its winner. `honourable` is false for Lead Foot.
class RecapAward {
  const RecapAward({
    required this.id,
    required this.title,
    required this.userId,
    required this.detail,
    this.honourable = true,
  });

  final String id;
  final String title;
  final String userId;
  final String detail;
  final bool honourable;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'user_id': userId,
    'detail': detail,
    'honourable': honourable,
  };

  factory RecapAward.fromJson(Map<String, dynamic> j) => RecapAward(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    userId: j['user_id'] as String? ?? '',
    detail: j['detail'] as String? ?? '',
    honourable: j['honourable'] as bool? ?? true,
  );
}

/// What the recap screen renders, built on this phone (docs/10 §8).
class ConvoyRecap {
  const ConvoyRecap({
    required this.convoyId,
    required this.name,
    required this.members,
    required this.awards,
    required this.totalCostCents,
    required this.stopsDone,
    required this.builtAt,
    this.costCurrency = 'USD',
    this.startedAt,
    this.endedAt,
  });

  final String convoyId;
  final String name;
  final List<RecapMember> members;
  final List<RecapAward> awards;

  /// Spend in [costCurrency], the currency with the largest total; other
  /// currencies are not added in.
  final int totalCostCents;
  final String costCurrency;
  final int stopsDone;
  final DateTime builtAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  Duration? get duration => startedAt == null || endedAt == null
      ? null
      : endedAt!.difference(startedAt!);

  String toJson() => jsonEncode({
    'convoy_id': convoyId,
    'name': name,
    'members': [for (final m in members) m.toJson()],
    'awards': [for (final a in awards) a.toJson()],
    'total_cost_cents': totalCostCents,
    'cost_currency': costCurrency,
    'stops_done': stopsDone,
    'built_at': builtAt.toIso8601String(),
    'started_at': startedAt?.toIso8601String(),
    'ended_at': endedAt?.toIso8601String(),
  });

  static ConvoyRecap? fromJson(String? json) {
    if (json == null) return null;
    try {
      final j = jsonDecode(json) as Map<String, dynamic>;
      return ConvoyRecap(
        convoyId: j['convoy_id'] as String,
        name: j['name'] as String? ?? '',
        members: [
          for (final m in j['members'] as List)
            RecapMember.fromJson((m as Map).cast<String, dynamic>()),
        ],
        awards: [
          for (final a in j['awards'] as List)
            RecapAward.fromJson((a as Map).cast<String, dynamic>()),
        ],
        totalCostCents: (j['total_cost_cents'] as num?)?.toInt() ?? 0,
        costCurrency: j['cost_currency'] as String? ?? 'USD',
        stopsDone: (j['stops_done'] as num?)?.toInt() ?? 0,
        builtAt:
            DateTime.tryParse(j['built_at'] as String? ?? '') ?? DateTime.now(),
        startedAt: DateTime.tryParse(j['started_at'] as String? ?? ''),
        endedAt: DateTime.tryParse(j['ended_at'] as String? ?? ''),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Pure recap computation. Positions are the tracks this phone received;
/// scores come from members' uploaded summaries; nothing is sent anywhere.
ConvoyRecap buildRecap({
  required Convoy convoy,
  required List<ConvoyMember> members,
  required List<ConvoyTrack> tracks,
  required List<ConvoyStop> stops,
  required List<ConvoyExpense> expenses,
  required List<ConvoyTripSummary> summaries,
  Map<String, int> djTracks = const {},
  required DateTime now,
}) {
  final byUser = <String, List<ConvoyTrack>>{};
  for (final t in tracks) {
    (byUser[t.userId] ??= []).add(t);
  }
  final nameOf = {for (final m in members) m.userId: m.name};
  final ids = {
    ...members.map((m) => m.userId),
    ...byUser.keys,
    ...summaries.map((s) => s.userId),
  };

  final recapMembers = <RecapMember>[];
  for (final id in ids) {
    final pts = byUser[id] ?? const <ConvoyTrack>[];
    var distance = 0.0;
    for (var i = 1; i < pts.length; i++) {
      final gapMs = pts[i].t - pts[i - 1].t;
      // Skip gaps over 10 minutes: the car was out of contact, not teleporting.
      if (gapMs > 10 * 60 * 1000) continue;
      distance += LatLon(
        pts[i - 1].lat,
        pts[i - 1].lon,
      ).distanceTo(LatLon(pts[i].lat, pts[i].lon));
    }
    final mine = summaries.where((s) => s.userId == id && s.scored).toList();
    double? avg;
    if (mine.isNotEmpty) {
      final scores = mine.map((s) => s.score).whereType<int>().toList();
      if (scores.isNotEmpty) {
        avg = scores.reduce((a, b) => a + b) / scores.length;
      }
    }
    final speeding = summaries
        .where((s) => s.userId == id)
        .fold<int>(0, (a, s) => a + s.speedingSeconds);
    recapMembers.add(
      RecapMember(
        userId: id,
        name: nameOf[id] ?? 'Driver',
        distanceM: distance,
        points: pts.length,
        averageScore: avg,
        speedingMinutes: speeding / 60,
        stopsProposed: stops.where((s) => s.proposedBy == id).length,
        djTracks: djTracks[id] ?? 0,
      ),
    );
  }
  recapMembers.sort((a, b) => a.name.compareTo(b.name));

  final awards = <RecapAward>[];
  final scored = recapMembers.where((m) => m.averageScore != null).toList();
  if (scored.length >= 2) {
    scored.sort((a, b) => b.averageScore!.compareTo(a.averageScore!));
    awards.add(
      RecapAward(
        id: 'smoothest',
        title: 'Smoothest',
        userId: scored.first.userId,
        detail: 'Average Drive Score ${scored.first.averageScore!.round()}',
      ),
    );
  }
  final speeders = recapMembers.where((m) => m.speedingMinutes > 0).toList()
    ..sort((a, b) => b.speedingMinutes.compareTo(a.speedingMinutes));
  if (speeders.isNotEmpty) {
    awards.add(
      RecapAward(
        id: 'lead_foot',
        title: 'Lead Foot',
        userId: speeders.first.userId,
        detail:
            '${speeders.first.speedingMinutes.toStringAsFixed(0)} min over the limit',
        honourable: false,
      ),
    );
  }
  final proposers = recapMembers.where((m) => m.stopsProposed > 0).toList()
    ..sort((a, b) => b.stopsProposed.compareTo(a.stopsProposed));
  if (proposers.isNotEmpty) {
    awards.add(
      RecapAward(
        id: 'most_stops',
        title: 'Most Stops Proposed',
        userId: proposers.first.userId,
        detail: '${proposers.first.stopsProposed} proposed',
      ),
    );
  }
  final djs = recapMembers.where((m) => m.djTracks > 0).toList()
    ..sort((a, b) => b.djTracks.compareTo(a.djTracks));
  if (djs.isNotEmpty) {
    awards.add(
      RecapAward(
        id: 'dj',
        title: 'DJ',
        userId: djs.first.userId,
        detail: '${djs.first.djTracks} tracks',
      ),
    );
  }
  if (convoy.createdBy.isNotEmpty) {
    awards.add(
      RecapAward(
        id: 'navigator',
        title: 'Navigator',
        userId: convoy.createdBy,
        detail: 'Led the convoy',
      ),
    );
  }

  MapEntry<String, int>? mainCost;
  for (final e in totalsByCurrency(expenses).entries) {
    if (mainCost == null || e.value > mainCost.value) mainCost = e;
  }

  return ConvoyRecap(
    convoyId: convoy.id,
    name: convoy.name,
    members: recapMembers,
    awards: awards,
    totalCostCents: mainCost?.value ?? 0,
    costCurrency: mainCost?.key ?? 'USD',
    stopsDone: stops.where((s) => s.status == StopStatus.done).length,
    builtAt: now,
    startedAt: convoy.startedAt,
    endedAt: convoy.endedAt,
  );
}

/// Whether a recap built now can be stored as the final one. Members' trip
/// summaries upload after their drives end, so a recap built within a day of
/// the end with no summaries yet stays provisional and is rebuilt next time
/// the screen opens (docs/10 §8).
bool recapIsFinal({
  required bool ended,
  required DateTime? endedAt,
  required bool hasSummaries,
  required DateTime now,
}) {
  if (!ended) return false;
  if (hasSummaries || endedAt == null) return true;
  return now.difference(endedAt) >= const Duration(hours: 24);
}
