/// Roast and praise copy. Mirrors `packages/scoring/src/roast/index.ts`.
library;

import '../constants.dart';
import '../js_compat.dart';
import '../types.dart';
import 'templates.dart';

/// FNV-1a 32-bit over the UTF-16 code units of [s]. Deterministic template choice per trip.
///
/// TS: `h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0`. The multiply is split so
/// every intermediate stays below 2^53: `h * 0x01000193 mod 2^32` equals
/// `((h & 0xFF) << 24) + h * 0x193` masked to 32 bits (0x01000193 = 2^24 + 0x193), which is
/// also exact if this package is ever compiled to JavaScript.
int hash(String s) {
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (((h & 0xFF) << 24) + h * 0x193) & 0xFFFFFFFF;
  }
  return h;
}

String formatDuration(double seconds) {
  final s = jsRound(seconds);
  if (s < 60) return '${jsIntegerString(s)} seconds';
  if (s < 120) {
    final rem = s.remainder(60);
    return rem < 10
        ? 'a minute'
        : '${jsIntegerString((s / 60).floorToDouble())} min ${jsIntegerString(rem)} s';
  }
  final m = jsRound(s / 60);
  return '${jsIntegerString(m)} minutes';
}

String formatSaved(double seconds) {
  final s = jsRound(seconds);
  if (s <= 0) return 'nothing';
  if (s < 60) return '${jsIntegerString(s)} seconds';
  return '${jsIntegerString(jsRound(s / 60))} minutes';
}

String _speedStr(double mps, SpeedUnits units) {
  final v = units == SpeedUnits.mph ? mpsToMph(mps) : mpsToKmh(mps);
  return jsIntegerString(jsRound(v));
}

String _distanceStr(double m, SpeedUnits units) {
  if (units == SpeedUnits.mph) {
    final mi = m / 1609.344;
    // Number.prototype.toFixed and double.toStringAsFixed share the same rounding rules.
    return mi < 10
        ? '${mi.toStringAsFixed(1)} miles'
        : '${jsIntegerString(jsRound(mi))} miles';
  }
  final km = m / 1000;
  return km < 10
      ? '${km.toStringAsFixed(1)} km'
      : '${jsIntegerString(jsRound(km))} km';
}

String _roadStr(TripEvent e) {
  final detail = e.detail;
  if (detail is SpeedingDetail) {
    final name = detail.roadName;
    // JS truthiness: an empty road name falls through to the class description.
    if (name != null && name.isNotEmpty) return name;
    return switch (detail.roadClass) {
      RoadClass.motorway || RoadClass.trunk => 'the highway',
      RoadClass.residential => 'a residential street',
      _ => 'that road',
    };
  }
  return 'that road';
}

final RegExp _slot = RegExp(r'\{(\w+)\}');

String _fill(String template, Map<String, String> slots) =>
    template.replaceAllMapped(_slot, (m) {
      final k = m[1]!;
      return slots[k] ?? '{$k}';
    });

String _pick(TemplateKey key, Intensity intensity, String seed) {
  final list = templates[key]![intensity]!;
  return list[hash(seed) % list.length];
}

StateError _impossible(TripEvent e) =>
    StateError('${e.kind.wire} events are never ${e.severity.wire}');

TemplateKey _templateKeyFor(TripEvent e) => switch (e.kind) {
  EventKind.speeding => switch (e.severity) {
    Severity.minor => TemplateKey.speedingMinor,
    Severity.moderate => TemplateKey.speedingModerate,
    Severity.major => TemplateKey.speedingMajor,
    Severity.reckless => TemplateKey.speedingReckless,
    Severity.severe => throw _impossible(e),
  },
  EventKind.harshBrake => switch (e.severity) {
    Severity.moderate => TemplateKey.harshBrakeModerate,
    Severity.severe => TemplateKey.harshBrakeSevere,
    _ => throw _impossible(e),
  },
  EventKind.harshAccel => switch (e.severity) {
    Severity.moderate => TemplateKey.harshAccelModerate,
    Severity.severe => TemplateKey.harshAccelSevere,
    _ => throw _impossible(e),
  },
  EventKind.hardCorner => switch (e.severity) {
    Severity.moderate => TemplateKey.hardCornerModerate,
    Severity.severe => TemplateKey.hardCornerSevere,
    _ => throw _impossible(e),
  },
  EventKind.phoneHandling => switch (e.severity) {
    Severity.minor => TemplateKey.phoneHandlingMinor,
    Severity.moderate => TemplateKey.phoneHandlingModerate,
    Severity.major => TemplateKey.phoneHandlingMajor,
    _ => throw _impossible(e),
  },
  EventKind.idling => TemplateKey.idling,
  EventKind.highSpeedCruise => TemplateKey.highSpeedCruise,
};

Map<String, String> _slotsFor(TripEvent e, SpeedUnits units) {
  final slots = <String, String>{
    'unit': units == SpeedUnits.mph ? 'mph' : 'km/h',
    'duration': formatDuration(e.durationS),
    'road': _roadStr(e),
  };
  switch (e.detail) {
    case SpeedingDetail d:
      slots['speed'] = _speedStr(d.maxSpeed, units);
      slots['limit'] = d.limit.isNaN ? 'zone with no posted limit' : _speedStr(d.limit, units);
      slots['over'] = d.maxOver.isNaN ? '?' : _speedStr(d.maxOver, units);
      slots['saved'] = formatSaved(d.timeSavedS);
    case MotionDetail d:
      slots['peak'] = d.peak.toStringAsFixed(1);
      slots['speed'] = _speedStr(d.speedAtStart, units);
    case PhoneDetail d:
      slots['speed'] = _speedStr(d.maxSpeed, units);
      slots['phoneSeconds'] = formatDuration(e.durationS);
      slots['count'] = '${d.interactions}';
    case IdleDetail():
      slots['idleMinutes'] = formatDuration(e.durationS);
    case CruiseDetail d:
      slots['cruiseMinutes'] = formatDuration(e.durationS);
      slots['speed'] = _speedStr(d.maxSpeed, units);
  }
  return slots;
}

const Map<Severity, int> _rank = {
  Severity.minor: 1,
  Severity.moderate: 2,
  Severity.major: 3,
  Severity.severe: 3,
  Severity.reckless: 4,
};

/// Roast line for one event. Exported for the UI's per-event detail view.
///
/// Always returns a line: every (kind, severity) the detectors can produce has a template.
/// (The TypeScript signature is `FeedbackLine | null`; its null branch is unreachable.)
FeedbackLine roastEvent(
  TripEvent e,
  String tripId,
  int index, [
  ScoreOptions options = const ScoreOptions(),
]) {
  final key = _templateKeyFor(e);
  final intensity = options.intensity ?? Intensity.sassy;
  final units = options.units ?? SpeedUnits.mph;
  final text = _fill(
    _pick(key, intensity, '$tripId:${key.key}:$index'),
    _slotsFor(e, units),
  );
  return FeedbackLine(tone: FeedbackTone.roast, text: text, eventIndex: index);
}

/// Builds the headline and supporting lines for a scored trip.
/// Headline: reckless event > worst event > praise. Then up to two more roasts and one praise line.
Feedback buildFeedback(
  TripScoreBase base, [
  ScoreOptions options = const ScoreOptions(),
]) {
  final intensity = options.intensity ?? Intensity.sassy;
  final units = options.units ?? SpeedUnits.mph;
  final distance = _distanceStr(base.summary.distanceM, units);
  final common = <String, String>{
    'distance': distance,
    'score': '${base.score}',
    'unit': units == SpeedUnits.mph ? 'mph' : 'km/h',
  };

  if (!base.scored) {
    final key = base.unscoredReason == UnscoredReason.passenger
        ? TemplateKey.unscoredPassenger
        : TemplateKey.unscoredTooShort;
    final headline = FeedbackLine(
      tone: FeedbackTone.praise,
      text: _fill(_pick(key, intensity, base.tripId), common),
    );
    return Feedback(headline: headline, lines: const []);
  }

  final ranked = stableSorted(
    [
      for (final (i, e) in base.events.indexed)
        if (e.kind != EventKind.idling || e.durationS > 180)
          (e: e, i: i), // tiny idles are not worth a line
    ],
    (a, b) {
      final r = _rank[b.e.severity]! - _rank[a.e.severity]!;
      return r != 0 ? r : b.e.durationS.compareTo(a.e.durationS);
    },
  );

  final roasts = <FeedbackLine>[];
  for (final (:e, :i) in ranked) {
    roasts.add(roastEvent(e, base.tripId, i, options));
    if (roasts.length >= 3) break;
  }

  final praise = <FeedbackLine>[];
  bool hasKind(EventKind k) => base.events.any((e) => e.kind == k);
  FeedbackLine praiseLine(TemplateKey key, String seed) => FeedbackLine(
    tone: FeedbackTone.praise,
    text: _fill(_pick(key, intensity, seed), common),
  );
  final longEnough = base.summary.distanceM >= 5000;
  if (base.events.isEmpty) {
    final key = base.summary.distanceM >= 20000
        ? TemplateKey.praiseCleanLong
        : TemplateKey.praisePerfect;
    praise.add(praiseLine(key, base.tripId));
  } else {
    if (!hasKind(EventKind.phoneHandling) && longEnough) {
      praise.add(praiseLine(TemplateKey.praisePhoneFree, '${base.tripId}:pf'));
    } else if (!hasKind(EventKind.harshBrake) &&
        !hasKind(EventKind.harshAccel) &&
        !hasKind(EventKind.hardCorner) &&
        longEnough) {
      praise.add(praiseLine(TemplateKey.praiseSmooth, '${base.tripId}:sm'));
    } else if (!hasKind(EventKind.speeding) &&
        base.summary.secondsWithKnownLimit > 120) {
      praise.add(
        praiseLine(TemplateKey.praiseLimitRespect, '${base.tripId}:lr'),
      );
    }
  }

  final worst = ranked.isEmpty ? null : ranked.first.e;
  final worthLeadingWith =
      worst != null && _rank[worst.severity]! >= _rank[Severity.moderate]!;
  final FeedbackLine headline;
  if (roasts.isNotEmpty &&
      (base.reckless || worthLeadingWith || base.score < 90)) {
    headline = roasts.first;
  } else if (praise.isNotEmpty) {
    headline = praise.first;
  } else {
    headline = praiseLine(TemplateKey.praiseGood, base.tripId);
  }

  final lines = [
    ...roasts,
    ...praise,
  ].where((l) => !identical(l, headline)).take(3).toList();
  return Feedback(headline: headline, lines: lines);
}
