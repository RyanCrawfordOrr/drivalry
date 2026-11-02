/// Drive Score, XP and the Reckless flag. Mirrors `packages/scoring/src/score.ts`.
library;

import 'dart:math' as math;

import 'constants.dart';
import 'events/attention.dart';
import 'events/efficiency.dart';
import 'events/smoothness.dart';
import 'events/speeding.dart';
import 'js_compat.dart';
import 'prepare.dart';
import 'roast/roast.dart';
import 'types.dart';

double _clamp(double v, double lo, double hi) => math.min(hi, math.max(lo, v));
double _round1(double v) => jsRound(v * 10) / 10;

TripSummary _summarise(PreparedTrip p, SpeedingResult speeding) {
  final samples = p.samples;
  final speed = p.speed;
  final dt = p.dt;
  final stepDistance = p.stepDistance;
  final goodFix = p.goodFix;
  final n = samples.length;
  var distanceM = 0.0;
  var movingTimeS = 0.0;
  var maxSpeed = 0.0;
  var good = 0;
  for (var i = 0; i < n; i++) {
    if (goodFix[i]) good++;
    if (i == 0) continue;
    distanceM += stepDistance[i];
    if (speed[i] > movingSpeed) movingTimeS += dt[i];
    if (goodFix[i] && speed[i] > maxSpeed) maxSpeed = speed[i];
  }
  final startT = n > 0 ? samples[0].t : 0;
  final endT = n > 0 ? samples[n - 1].t : startT;
  return TripSummary(
    distanceM: distanceM,
    movingTimeS: movingTimeS,
    totalTimeS: (endT - startT) / 1000,
    maxSpeed: maxSpeed,
    avgMovingSpeed: movingTimeS > 0 ? distanceM / movingTimeS : 0,
    secondsOverLimit: speeding.secondsOverLimit,
    secondsWithKnownLimit: speeding.secondsWithKnownLimit,
    timeSavedBySpeedingS: speeding.timeSavedBySpeedingS,
    startT: startT,
    endT: endT,
    nightFraction: p.input.context?.nightFraction ?? 0,
    gpsQuality: n > 0 ? good / n : 0,
  );
}

double _speedPenalty(List<TripEvent> events, TripSummary summary) {
  var total = 0.0;
  for (final e in events) {
    if (e.kind != EventKind.speeding) continue;
    final w =
        Speeding.weightPerMinute[e.severity] ??
        Speeding.weightPerMinute[Severity.minor]!;
    total += (w * math.min(e.durationS, Speeding.maxPenalisedDurationS)) / 60;
  }
  if (summary.movingTimeS > 0) {
    total +=
        Speeding.proportionWeight *
        (summary.secondsOverLimit / summary.movingTimeS);
  }
  return _clamp(total, 0, Speeding.cap);
}

double _smoothnessPenalty(List<TripEvent> events, TripSummary summary) {
  var raw = 0.0;
  for (final e in events) {
    if (!isMotionKind(e.kind)) continue;
    final table = Smoothness.weights[e.kind]!;
    raw += e.severity == Severity.severe ? table.severe : table.moderate;
  }
  final norm =
      Smoothness.normaliseDistanceM /
      math.max(summary.distanceM, Smoothness.minNormaliseDistanceM);
  return _clamp(raw * norm, 0, Smoothness.cap);
}

double _attentionPenalty(List<TripEvent> events) {
  var total = 0.0;
  for (final e in events) {
    if (e.kind != EventKind.phoneHandling) continue;
    total +=
        Attention.weights[e.severity] ?? Attention.weights[Severity.minor]!;
  }
  return _clamp(total, 0, Attention.cap);
}

double _efficiencyPenalty(List<TripEvent> events) {
  var idle = 0.0;
  var cruise = 0.0;
  var aggression = 0.0;
  for (final e in events) {
    final detail = e.detail;
    if (e.kind == EventKind.idling && detail is IdleDetail) {
      idle += (Efficiency.idle.weightPerMinute * detail.excessS) / 60;
    } else if (e.kind == EventKind.highSpeedCruise) {
      cruise += (Efficiency.cruise.weightPerMinute * e.durationS) / 60;
    } else if (e.kind == EventKind.harshAccel) {
      aggression += Efficiency.aggression.perHarshAccel;
    }
  }
  final total =
      _clamp(idle, 0, Efficiency.idle.cap) +
      _clamp(cruise, 0, Efficiency.cruise.cap) +
      _clamp(aggression, 0, Efficiency.aggression.cap);
  return _clamp(total, 0, Efficiency.cap);
}

bool _isRecklessPhone(TripEvent e) {
  final d = e.detail;
  return e.kind == EventKind.phoneHandling &&
      e.severity == Severity.major &&
      d is PhoneDetail &&
      d.maxSpeed >= Attention.majorSpeed &&
      e.durationS >= Attention.recklessDurationS;
}

List<Flag> _recklessFlags(List<TripEvent> events) {
  final flags = <Flag>[];
  if (events.any(
    (e) => e.kind == EventKind.speeding && e.severity == Severity.reckless,
  )) {
    flags.add(Flag.recklessSpeed);
  }
  if (events.any(_isRecklessPhone)) flags.add(Flag.recklessPhone);
  final severeMotion = events
      .where((e) => isMotionKind(e.kind) && e.severity == Severity.severe)
      .length;
  final majorSpeeding = events.any(
    (e) =>
        e.kind == EventKind.speeding &&
        (e.severity == Severity.major || e.severity == Severity.reckless),
  );
  if (severeMotion >= Reckless.patternSevereEvents && majorSpeeding) {
    flags.add(Flag.recklessPattern);
  }
  return flags;
}

/// XP for a trip: `baseline(score) × distanceFactor × contextBonus` plus streak bonuses.
/// See docs/02-game-design.md §5.
int computeXp(int score, double distanceM, TripContext? ctx, bool reckless) {
  if (reckless || score < Xp.minScore) return 0;
  final baseline =
      Xp.minXp +
      ((score - Xp.minScore) / (100 - Xp.minScore)) * (Xp.maxXp - Xp.minXp);

  final distanceKm = distanceM / 1000;
  final before = ctx?.dailyCreditedKmBefore ?? 0.0;
  final creditedKm = _clamp(
    math.min(distanceKm, Xp.dailyCapKm - before),
    0,
    Xp.dailyCapKm,
  );
  final distanceFactor = creditedKm <= 0
      ? Xp.distanceFloor
      : math.min(
          1.0,
          Xp.distanceFloor +
              (1 - Xp.distanceFloor) * (creditedKm / Xp.fullCreditKm),
        );

  var bonus = 1.0;
  if (score >= Xp.bonusMinScore) {
    if ((ctx?.nightFraction ?? 0) >= 0.5) bonus *= Xp.nightBonus;
    if (ctx?.weather == Weather.rain || ctx?.weather == Weather.snow) {
      bonus *= Xp.weatherBonus;
    }
  }
  bonus = math.min(bonus, Xp.maxContextBonus);

  var xp = baseline * distanceFactor * bonus;

  final streak = ctx?.cleanStreak ?? 0;
  if (score >= Xp.cleanTripScore) {
    if (streak >= Xp.streak.tier2) {
      xp += Xp.streak.tier2Xp;
    } else if (streak >= Xp.streak.tier1) {
      xp += Xp.streak.tier1Xp;
    }
  }
  return jsRoundInt(xp);
}

const Map<Severity, int> _severityRank = {
  Severity.minor: 1,
  Severity.moderate: 2,
  Severity.major: 3,
  Severity.severe: 3,
  Severity.reckless: 4,
};

/// Sort events by severity (worst first), then by time. Used for feedback and display.
List<TripEvent> sortBySeverity(List<TripEvent> events) =>
    stableSorted(events, (a, b) {
      final r = _severityRank[b.severity]! - _severityRank[a.severity]!;
      return r != 0 ? r : a.startT.compareTo(b.startT);
    });

TripScore _unscored(
  TripInput input,
  TripSummary summary,
  UnscoredReason reason,
  ScoreOptions options,
) {
  final base = TripScoreBase(
    tripId: input.id,
    scored: false,
    unscoredReason: reason,
    score: 0,
    penalties: ComponentPenalties.zero,
    flags: const [],
    reckless: false,
    xp: 0,
    events: const [],
    observations: const [],
    summary: summary,
  );
  return TripScore.fromBase(base, buildFeedback(base, options));
}

/// Score a trip. Pure function: same input, same output.
TripScore scoreTrip(
  TripInput input, [
  ScoreOptions options = const ScoreOptions(),
]) {
  final p = prepare(input);
  final speeding = detectSpeeding(p);
  final summary = _summarise(p, speeding);

  if (input.context?.isPassenger ?? false) {
    return _unscored(input, summary, UnscoredReason.passenger, options);
  }
  if (summary.distanceM < Minimums.distanceM ||
      summary.movingTimeS < Minimums.movingTimeS) {
    return _unscored(input, summary, UnscoredReason.tooShort, options);
  }

  final events = stableSorted([
    ...speeding.events,
    ...detectSmoothness(p),
    ...detectPhoneHandling(p),
    ...detectIdling(p),
    ...detectHighSpeedCruise(p),
  ], (a, b) => a.startT.compareTo(b.startT));

  final penalties = ComponentPenalties(
    speed: _round1(_speedPenalty(events, summary)),
    smoothness: _round1(_smoothnessPenalty(events, summary)),
    attention: _round1(_attentionPenalty(events)),
    efficiency: _round1(_efficiencyPenalty(events)),
  );

  final flags = _recklessFlags(events);
  if (summary.gpsQuality < 0.7) flags.add(Flag.lowGpsQuality);
  if (summary.movingTimeS > 0 &&
      summary.secondsWithKnownLimit / summary.movingTimeS < 0.5) {
    flags.add(Flag.limitsUnknown);
  }
  final reckless = flags.any((f) => f.wire.startsWith('reckless_'));

  var score = jsRoundInt(
    _clamp(
      100 -
          penalties.speed -
          penalties.smoothness -
          penalties.attention -
          penalties.efficiency,
      0,
      100,
    ),
  );
  if (reckless) score = math.min(score, Reckless.scoreCap);

  final xp = computeXp(score, summary.distanceM, input.context, reckless);

  final base = TripScoreBase(
    tripId: input.id,
    scored: true,
    score: score,
    penalties: penalties,
    flags: flags,
    reckless: reckless,
    xp: xp,
    events: events,
    observations: speeding.observations,
    summary: summary,
  );
  return TripScore.fromBase(base, buildFeedback(base, options));
}
