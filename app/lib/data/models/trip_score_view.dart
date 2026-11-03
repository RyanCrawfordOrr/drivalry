import 'dart:convert';

import 'package:drivalry_scoring/drivalry_scoring.dart';

/// Read-side view of a stored `TripScore.toJson()`.
///
/// The scoring package has no `TripScore.fromJson` (the engine only ever
/// produces scores), so the app parses the stored JSON itself. Only the
/// fields the UI needs are typed; the rest stays in [raw].
class TripScoreView {
  const TripScoreView({
    required this.tripId,
    required this.scored,
    required this.unscoredReason,
    required this.score,
    required this.penalties,
    required this.flags,
    required this.reckless,
    required this.xp,
    required this.events,
    required this.observations,
    required this.summary,
    required this.headline,
    required this.lines,
    required this.raw,
  });

  factory TripScoreView.fromScore(TripScore s) =>
      TripScoreView.fromJson(s.toJson());

  factory TripScoreView.fromJsonString(String json) =>
      TripScoreView.fromJson(jsonDecode(json) as Map<String, dynamic>);

  factory TripScoreView.fromJson(Map<String, dynamic> j) {
    final penalties = j['penalties'] as Map<String, dynamic>? ?? const {};
    final feedback = j['feedback'] as Map<String, dynamic>? ?? const {};
    final headline = feedback['headline'] as Map<String, dynamic>?;
    return TripScoreView(
      tripId: j['tripId'] as String? ?? '',
      scored: j['scored'] as bool? ?? false,
      unscoredReason: j['unscoredReason'] as String?,
      score: (j['score'] as num?)?.toInt() ?? 0,
      penalties: ComponentPenalties(
        speed: (penalties['speed'] as num?)?.toDouble() ?? 0,
        smoothness: (penalties['smoothness'] as num?)?.toDouble() ?? 0,
        attention: (penalties['attention'] as num?)?.toDouble() ?? 0,
        efficiency: (penalties['efficiency'] as num?)?.toDouble() ?? 0,
      ),
      flags: [for (final f in (j['flags'] as List?) ?? const []) f as String],
      reckless: j['reckless'] as bool? ?? false,
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      events: _events(j['events']),
      observations: _events(j['observations']),
      summary: TripSummaryView.fromJson(
        j['summary'] as Map<String, dynamic>? ?? const {},
      ),
      headline: headline == null ? null : FeedbackLineView.fromJson(headline),
      lines: [
        for (final l in (feedback['lines'] as List?) ?? const [])
          FeedbackLineView.fromJson(l as Map<String, dynamic>),
      ],
      raw: j,
    );
  }

  static List<TripEventView> _events(Object? list) => [
    for (final e in (list as List?) ?? const [])
      TripEventView.fromJson(e as Map<String, dynamic>),
  ];

  final String tripId;
  final bool scored;

  /// too_short | passenger
  final String? unscoredReason;
  final int score;
  final ComponentPenalties penalties;
  final List<String> flags;
  final bool reckless;
  final int xp;
  final List<TripEventView> events;
  final List<TripEventView> observations;
  final TripSummaryView summary;
  final FeedbackLineView? headline;
  final List<FeedbackLineView> lines;
  final Map<String, dynamic> raw;

  /// The one line that goes on the card and into the feed.
  String? get roastText => headline?.text;

  bool get headlineIsRoast => headline?.tone == 'roast';
}

class FeedbackLineView {
  const FeedbackLineView({
    required this.tone,
    required this.text,
    this.eventIndex,
  });

  factory FeedbackLineView.fromJson(Map<String, dynamic> j) => FeedbackLineView(
    tone: j['tone'] as String? ?? 'praise',
    text: j['text'] as String? ?? '',
    eventIndex: (j['eventIndex'] as num?)?.toInt(),
  );

  /// roast | praise
  final String tone;
  final String text;
  final int? eventIndex;
}

class TripSummaryView {
  const TripSummaryView({
    required this.distanceM,
    required this.movingTimeS,
    required this.totalTimeS,
    required this.maxSpeed,
    required this.avgMovingSpeed,
    required this.secondsOverLimit,
    required this.secondsWithKnownLimit,
    required this.timeSavedBySpeedingS,
    required this.startT,
    required this.endT,
    required this.nightFraction,
    required this.gpsQuality,
  });

  factory TripSummaryView.fromJson(Map<String, dynamic> j) => TripSummaryView(
    distanceM: (j['distanceM'] as num?)?.toDouble() ?? 0,
    movingTimeS: (j['movingTimeS'] as num?)?.toDouble() ?? 0,
    totalTimeS: (j['totalTimeS'] as num?)?.toDouble() ?? 0,
    maxSpeed: (j['maxSpeed'] as num?)?.toDouble() ?? 0,
    avgMovingSpeed: (j['avgMovingSpeed'] as num?)?.toDouble() ?? 0,
    secondsOverLimit: (j['secondsOverLimit'] as num?)?.toDouble() ?? 0,
    secondsWithKnownLimit:
        (j['secondsWithKnownLimit'] as num?)?.toDouble() ?? 0,
    timeSavedBySpeedingS: (j['timeSavedBySpeedingS'] as num?)?.toDouble() ?? 0,
    startT: (j['startT'] as num?)?.toInt() ?? 0,
    endT: (j['endT'] as num?)?.toInt() ?? 0,
    nightFraction: (j['nightFraction'] as num?)?.toDouble() ?? 0,
    gpsQuality: (j['gpsQuality'] as num?)?.toDouble() ?? 1,
  );

  final double distanceM;
  final double movingTimeS;
  final double totalTimeS;
  final double maxSpeed;
  final double avgMovingSpeed;
  final double secondsOverLimit;
  final double secondsWithKnownLimit;
  final double timeSavedBySpeedingS;
  final int startT;
  final int endT;
  final double nightFraction;
  final double gpsQuality;

  /// Moving seconds on a confident limit over all moving seconds.
  double get limitCoverage =>
      movingTimeS <= 0 ? 0 : (secondsWithKnownLimit / movingTimeS).clamp(0, 1);
}

class TripEventView {
  const TripEventView({
    required this.kind,
    required this.severity,
    required this.startT,
    required this.endT,
    required this.durationS,
    required this.startIdx,
    required this.endIdx,
    required this.lat,
    required this.lon,
    required this.detail,
  });

  factory TripEventView.fromJson(Map<String, dynamic> j) => TripEventView(
    kind: EventKind.fromWire(j['kind'] as String),
    severity: Severity.fromWire(j['severity'] as String),
    startT: (j['startT'] as num).toInt(),
    endT: (j['endT'] as num).toInt(),
    durationS: (j['durationS'] as num).toDouble(),
    startIdx: (j['startIdx'] as num).toInt(),
    endIdx: (j['endIdx'] as num).toInt(),
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    detail: j['detail'] as Map<String, dynamic>? ?? const {},
  );

  final EventKind kind;
  final Severity severity;
  final int startT;
  final int endT;
  final double durationS;
  final int startIdx;
  final int endIdx;
  final double lat;
  final double lon;

  /// Kind-specific payload, see `EventDetail.toJson` in the scoring package.
  final Map<String, dynamic> detail;

  double? get limitMps => (detail['limit'] as num?)?.toDouble();
  double? get maxSpeedMps => (detail['maxSpeed'] as num?)?.toDouble();
  double? get peak => (detail['peak'] as num?)?.toDouble();
  String? get roadName => detail['roadName'] as String?;
  String? get wayId => detail['wayId'] as String?;
}
