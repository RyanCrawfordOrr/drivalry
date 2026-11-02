/// Drivalry scoring engine — shared types.
///
/// All quantities are SI: metres, seconds, m/s, m/s². Timestamps are epoch milliseconds.
/// The UI converts. Mirrors `packages/scoring/src/types.ts`; the rules these types encode
/// are in `docs/02-game-design.md`.
///
/// Every type carries `toJson()`, and every input type `fromJson()`, in exactly the shape
/// the TypeScript engine produces with `JSON.stringify` (absent optional properties are
/// omitted). Enum values expose the TypeScript string as `wire`.
library;

T _enumByWire<T extends Enum>(
  List<T> values,
  String Function(T) wireOf,
  String wire,
) {
  for (final v in values) {
    if (wireOf(v) == wire) return v;
  }
  throw ArgumentError.value(wire, 'wire', 'Unknown $T');
}

double _d(Object? v) => (v as num).toDouble();
double? _dOpt(Object? v) => v == null ? null : (v as num).toDouble();
int _i(Object? v) => (v as num).toInt();
int? _iOpt(Object? v) => v == null ? null : (v as num).toInt();

// ---------------------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------------------

/// One GPS fix.
class GpsSample {
  const GpsSample({
    required this.t,
    required this.lat,
    required this.lon,
    required this.speed,
    required this.accuracy,
    this.heading,
    this.altitude,
  });

  factory GpsSample.fromJson(Map<String, dynamic> json) => GpsSample(
    t: _i(json['t']),
    lat: _d(json['lat']),
    lon: _d(json['lon']),
    speed: _d(json['speed']),
    accuracy: _d(json['accuracy']),
    heading: _dOpt(json['heading']),
    altitude: _dOpt(json['altitude']),
  );

  /// Epoch milliseconds.
  final int t;
  final double lat;
  final double lon;

  /// Ground speed in m/s as reported by the OS (already Doppler-smoothed on most devices).
  final double speed;

  /// Horizontal accuracy radius in metres. Samples above 50 m are ignored for speeding.
  final double accuracy;

  /// Course over ground in degrees, 0 = north, clockwise. Derived from positions when absent.
  final double? heading;
  final double? altitude;

  Map<String, Object?> toJson() => {
    't': t,
    'lat': lat,
    'lon': lon,
    'speed': speed,
    'accuracy': accuracy,
    if (heading != null) 'heading': heading,
    if (altitude != null) 'altitude': altitude,
  };
}

enum RoadClass {
  motorway,
  trunk,
  primary,
  secondary,
  tertiary,
  residential,
  service,
  unclassified,
  unknown;

  String get wire => name;
  static RoadClass fromWire(String wire) =>
      _enumByWire(values, (v) => v.wire, wire);
}

/// A map-matched stretch of road covering samples `[fromIdx, toIdx]` inclusive.
/// Produced on the phone by the pack matcher (plus shared corrections). Segments must not overlap.
///
/// Segments are compared by identity (as the TypeScript engine does), never by value.
class RoadSegment {
  const RoadSegment({
    required this.fromIdx,
    required this.toIdx,
    required this.speedLimit,
    required this.confidence,
    required this.roadClass,
    this.name,
    this.wayId,
  });

  factory RoadSegment.fromJson(Map<String, dynamic> json) => RoadSegment(
    fromIdx: _i(json['fromIdx']),
    toIdx: _i(json['toIdx']),
    speedLimit: _dOpt(json['speedLimit']),
    confidence: _d(json['confidence']),
    roadClass: RoadClass.fromWire(json['roadClass'] as String),
    name: json['name'] as String?,
    wayId: json['wayId'] as String?,
  );

  final int fromIdx;
  final int toIdx;

  /// Posted limit in m/s, or null when unknown.
  final double? speedLimit;

  /// 0–1. Below `speedingMinConfidence` the segment can produce observations but never penalties.
  final double confidence;
  final RoadClass roadClass;
  final String? name;

  /// OSM way id, used for the "limit is wrong here" correction loop.
  final String? wayId;

  Map<String, Object?> toJson() => {
    'fromIdx': fromIdx,
    'toIdx': toIdx,
    'speedLimit': speedLimit,
    'confidence': confidence,
    'roadClass': roadClass.wire,
    if (name != null) 'name': name,
    if (wayId != null) 'wayId': wayId,
  };
}

enum PhoneEventKind {
  unlock('unlock'),
  interaction('interaction'),
  callHandheld('call_handheld');

  const PhoneEventKind(this.wire);
  final String wire;
  static PhoneEventKind fromWire(String wire) =>
      _enumByWire(values, (v) => v.wire, wire);
}

class PhoneEvent {
  const PhoneEvent({required this.t, required this.kind});

  factory PhoneEvent.fromJson(Map<String, dynamic> json) => PhoneEvent(
    t: _i(json['t']),
    kind: PhoneEventKind.fromWire(json['kind'] as String),
  );

  /// Epoch milliseconds.
  final int t;
  final PhoneEventKind kind;

  Map<String, Object?> toJson() => {'t': t, 'kind': kind.wire};
}

/// Declared in the order the smoothness detector processes them (brake, accel, corner).
enum MotionEventKind {
  brake,
  accel,
  corner;

  String get wire => name;
  static MotionEventKind fromWire(String wire) =>
      _enumByWire(values, (v) => v.wire, wire);
}

/// Optional pre-detected motion event from the accelerometer pipeline. Peak is m/s².
class MotionEvent {
  const MotionEvent({required this.t, required this.kind, required this.peak});

  factory MotionEvent.fromJson(Map<String, dynamic> json) => MotionEvent(
    t: _i(json['t']),
    kind: MotionEventKind.fromWire(json['kind'] as String),
    peak: _d(json['peak']),
  );

  /// Epoch milliseconds.
  final int t;
  final MotionEventKind kind;
  final double peak;

  Map<String, Object?> toJson() => {'t': t, 'kind': kind.wire, 'peak': peak};
}

enum Weather {
  clear,
  rain,
  snow;

  String get wire => name;
  static Weather fromWire(String wire) =>
      _enumByWire(values, (v) => v.wire, wire);
}

class TripContext {
  const TripContext({
    this.nightFraction,
    this.weather,
    this.vehicleId,
    this.isPassenger,
    this.dailyCreditedKmBefore,
    this.cleanStreak,
  });

  factory TripContext.fromJson(Map<String, dynamic> json) => TripContext(
    nightFraction: _dOpt(json['nightFraction']),
    weather: json['weather'] == null
        ? null
        : Weather.fromWire(json['weather'] as String),
    vehicleId: json['vehicleId'] as String?,
    isPassenger: json['isPassenger'] as bool?,
    dailyCreditedKmBefore: _dOpt(json['dailyCreditedKmBefore']),
    cleanStreak: _iOpt(json['cleanStreak']),
  );

  /// Fraction of the trip (by time) after civil dusk / before civil dawn. 0–1.
  final double? nightFraction;
  final Weather? weather;
  final String? vehicleId;

  /// Marked as passenger by the user or by heuristics. Passenger trips are not scored.
  final bool? isPassenger;

  /// Kilometres already credited toward XP today, before this trip. Enforces the daily cap.
  final double? dailyCreditedKmBefore;

  /// Current clean-trip streak length before this trip.
  final int? cleanStreak;

  Map<String, Object?> toJson() => {
    if (nightFraction != null) 'nightFraction': nightFraction,
    if (weather != null) 'weather': weather!.wire,
    if (vehicleId != null) 'vehicleId': vehicleId,
    if (isPassenger != null) 'isPassenger': isPassenger,
    if (dailyCreditedKmBefore != null)
      'dailyCreditedKmBefore': dailyCreditedKmBefore,
    if (cleanStreak != null) 'cleanStreak': cleanStreak,
  };
}

class TripInput {
  const TripInput({
    required this.id,
    required this.samples,
    required this.segments,
    this.phoneEvents,
    this.motionEvents,
    this.context,
  });

  factory TripInput.fromJson(Map<String, dynamic> json) => TripInput(
    id: json['id'] as String,
    samples: [
      for (final s in json['samples'] as List)
        GpsSample.fromJson(s as Map<String, dynamic>),
    ],
    segments: [
      for (final s in json['segments'] as List)
        RoadSegment.fromJson(s as Map<String, dynamic>),
    ],
    phoneEvents: json['phoneEvents'] == null
        ? null
        : [
            for (final e in json['phoneEvents'] as List)
              PhoneEvent.fromJson(e as Map<String, dynamic>),
          ],
    motionEvents: json['motionEvents'] == null
        ? null
        : [
            for (final e in json['motionEvents'] as List)
              MotionEvent.fromJson(e as Map<String, dynamic>),
          ],
    context: json['context'] == null
        ? null
        : TripContext.fromJson(json['context'] as Map<String, dynamic>),
  );

  final String id;
  final List<GpsSample> samples;
  final List<RoadSegment> segments;
  final List<PhoneEvent>? phoneEvents;
  final List<MotionEvent>? motionEvents;
  final TripContext? context;

  TripInput copyWith({
    String? id,
    List<GpsSample>? samples,
    List<RoadSegment>? segments,
    List<PhoneEvent>? phoneEvents,
    List<MotionEvent>? motionEvents,
    TripContext? context,
  }) => TripInput(
    id: id ?? this.id,
    samples: samples ?? this.samples,
    segments: segments ?? this.segments,
    phoneEvents: phoneEvents ?? this.phoneEvents,
    motionEvents: motionEvents ?? this.motionEvents,
    context: context ?? this.context,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'samples': [for (final s in samples) s.toJson()],
    'segments': [for (final s in segments) s.toJson()],
    if (phoneEvents != null)
      'phoneEvents': [for (final e in phoneEvents!) e.toJson()],
    if (motionEvents != null)
      'motionEvents': [for (final e in motionEvents!) e.toJson()],
    if (context != null) 'context': context!.toJson(),
  };
}

// ---------------------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------------------

enum EventKind {
  speeding('speeding'),
  harshBrake('harsh_brake'),
  harshAccel('harsh_accel'),
  hardCorner('hard_corner'),
  phoneHandling('phone_handling'),
  idling('idling'),
  highSpeedCruise('high_speed_cruise');

  const EventKind(this.wire);
  final String wire;
  static EventKind fromWire(String wire) =>
      _enumByWire(values, (v) => v.wire, wire);
}

/// Severity ladder. Each event kind uses a subset:
///  - speeding: minor | moderate | major | reckless
///  - brake/accel/corner: moderate | severe
///  - phone_handling: minor | moderate | major
///  - idling, high_speed_cruise: minor (informational)
enum Severity {
  minor,
  moderate,
  major,
  severe,
  reckless;

  String get wire => name;
  static Severity fromWire(String wire) =>
      _enumByWire(values, (v) => v.wire, wire);
}

/// Per-kind event payload. The shape is selected by [kind], exactly as the TS discriminated union.
sealed class EventDetail {
  const EventDetail();
  EventKind get kind;
  Map<String, Object?> toJson();
}

final class SpeedingDetail extends EventDetail {
  const SpeedingDetail({
    required this.limit,
    required this.maxSpeed,
    required this.avgOver,
    required this.maxOver,
    this.roadName,
    required this.roadClass,
    required this.timeSavedS,
  });

  @override
  EventKind get kind => EventKind.speeding;

  /// Posted limit, m/s. NaN when the absolute-reckless rule fired on a road with no known limit.
  final double limit;

  /// Peak (median-filtered) speed in the episode, m/s.
  final double maxSpeed;

  /// Mean amount over the limit during the episode, m/s.
  final double avgOver;

  /// Peak amount over the limit, m/s.
  final double maxOver;
  final String? roadName;
  final RoadClass roadClass;

  /// Estimated seconds the driver saved vs driving at the limit over this episode.
  final double timeSavedS;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'limit': limit,
    'maxSpeed': maxSpeed,
    'avgOver': avgOver,
    'maxOver': maxOver,
    if (roadName != null) 'roadName': roadName,
    'roadClass': roadClass.wire,
    'timeSavedS': timeSavedS,
  };
}

final class MotionDetail extends EventDetail {
  const MotionDetail({
    required this.kind,
    required this.peak,
    required this.speedAtStart,
  }) : assert(
         kind == EventKind.harshBrake ||
             kind == EventKind.harshAccel ||
             kind == EventKind.hardCorner,
         'MotionDetail is only for harsh_brake, harsh_accel and hard_corner',
       );

  @override
  final EventKind kind;

  /// Peak longitudinal or lateral acceleration, m/s².
  final double peak;

  /// Speed at the start of the event, m/s.
  final double speedAtStart;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'peak': peak,
    'speedAtStart': speedAtStart,
  };
}

final class PhoneDetail extends EventDetail {
  const PhoneDetail({
    required this.interactions,
    required this.maxSpeed,
    required this.kinds,
  });

  @override
  EventKind get kind => EventKind.phoneHandling;

  /// Number of raw OS events merged into this episode.
  final int interactions;

  /// Peak speed during the episode, m/s.
  final double maxSpeed;
  final List<PhoneEventKind> kinds;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'interactions': interactions,
    'maxSpeed': maxSpeed,
    'kinds': [for (final k in kinds) k.wire],
  };
}

final class IdleDetail extends EventDetail {
  const IdleDetail({required this.excessS});

  @override
  EventKind get kind => EventKind.idling;

  /// Seconds beyond the free threshold.
  final double excessS;

  @override
  Map<String, Object?> toJson() => {'kind': kind.wire, 'excessS': excessS};
}

final class CruiseDetail extends EventDetail {
  const CruiseDetail({required this.maxSpeed});

  @override
  EventKind get kind => EventKind.highSpeedCruise;
  final double maxSpeed;

  @override
  Map<String, Object?> toJson() => {'kind': kind.wire, 'maxSpeed': maxSpeed};
}

class TripEvent {
  const TripEvent({
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

  final EventKind kind;
  final Severity severity;

  /// Epoch ms.
  final int startT;
  final int endT;
  final double durationS;

  /// Sample indices, inclusive.
  final int startIdx;
  final int endIdx;

  /// Where to pin it on the map (sample at startIdx).
  final double lat;
  final double lon;
  final EventDetail detail;

  TripEvent withSeverity(Severity severity) => TripEvent(
    kind: kind,
    severity: severity,
    startT: startT,
    endT: endT,
    durationS: durationS,
    startIdx: startIdx,
    endIdx: endIdx,
    lat: lat,
    lon: lon,
    detail: detail,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.wire,
    'severity': severity.wire,
    'startT': startT,
    'endT': endT,
    'durationS': durationS,
    'startIdx': startIdx,
    'endIdx': endIdx,
    'lat': lat,
    'lon': lon,
    'detail': detail.toJson(),
  };
}

// ---------------------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------------------

enum Flag {
  recklessSpeed('reckless_speed'),
  recklessPhone('reckless_phone'),
  recklessPattern('reckless_pattern'),
  lowGpsQuality('low_gps_quality'),
  limitsUnknown('limits_unknown');

  const Flag(this.wire);
  final String wire;
  static Flag fromWire(String wire) => _enumByWire(values, (v) => v.wire, wire);
}

class TripSummary {
  const TripSummary({
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

  final double distanceM;

  /// Seconds with speed > `movingSpeed`.
  final double movingTimeS;
  final double totalTimeS;
  final double maxSpeed;

  /// Distance / moving time.
  final double avgMovingSpeed;

  /// Seconds over the limit on confident segments.
  final double secondsOverLimit;

  /// Seconds driven on segments with a confident limit (denominator for coverage).
  final double secondsWithKnownLimit;

  /// Total seconds saved by all speeding in this trip. The roast material.
  final double timeSavedBySpeedingS;
  final int startT;
  final int endT;
  final double nightFraction;

  /// Fraction of samples with accuracy <= `gpsMaxAccuracy`.
  final double gpsQuality;

  Map<String, Object?> toJson() => {
    'distanceM': distanceM,
    'movingTimeS': movingTimeS,
    'totalTimeS': totalTimeS,
    'maxSpeed': maxSpeed,
    'avgMovingSpeed': avgMovingSpeed,
    'secondsOverLimit': secondsOverLimit,
    'secondsWithKnownLimit': secondsWithKnownLimit,
    'timeSavedBySpeedingS': timeSavedBySpeedingS,
    'startT': startT,
    'endT': endT,
    'nightFraction': nightFraction,
    'gpsQuality': gpsQuality,
  };
}

class ComponentPenalties {
  const ComponentPenalties({
    required this.speed,
    required this.smoothness,
    required this.attention,
    required this.efficiency,
  });

  static const zero = ComponentPenalties(
    speed: 0,
    smoothness: 0,
    attention: 0,
    efficiency: 0,
  );

  final double speed;
  final double smoothness;
  final double attention;
  final double efficiency;

  Map<String, Object?> toJson() => {
    'speed': speed,
    'smoothness': smoothness,
    'attention': attention,
    'efficiency': efficiency,
  };

  @override
  bool operator ==(Object other) =>
      other is ComponentPenalties &&
      other.speed == speed &&
      other.smoothness == smoothness &&
      other.attention == attention &&
      other.efficiency == efficiency;

  @override
  int get hashCode => Object.hash(speed, smoothness, attention, efficiency);

  @override
  String toString() =>
      'ComponentPenalties(speed: $speed, smoothness: $smoothness, attention: $attention, efficiency: $efficiency)';
}

enum Intensity {
  gentle,
  sassy,
  savage;

  String get wire => name;
  static Intensity fromWire(String wire) =>
      _enumByWire(values, (v) => v.wire, wire);
}

/// Display units for feedback copy.
enum SpeedUnits {
  mph,
  kmh;

  String get wire => name;
  static SpeedUnits fromWire(String wire) =>
      _enumByWire(values, (v) => v.wire, wire);
}

/// 'roast' lines are negative; 'praise' positive.
enum FeedbackTone {
  roast,
  praise;

  String get wire => name;
}

class FeedbackLine {
  const FeedbackLine({required this.tone, required this.text, this.eventIndex});

  final FeedbackTone tone;
  final String text;

  /// Which event this line is about, if any (index into `events`).
  final int? eventIndex;

  Map<String, Object?> toJson() => {
    'tone': tone.wire,
    'text': text,
    if (eventIndex != null) 'eventIndex': eventIndex,
  };

  @override
  String toString() => 'FeedbackLine(${tone.wire}, $eventIndex, "$text")';
}

class Feedback {
  const Feedback({required this.headline, required this.lines});

  final FeedbackLine headline;
  final List<FeedbackLine> lines;

  Map<String, Object?> toJson() => {
    'headline': headline.toJson(),
    'lines': [for (final l in lines) l.toJson()],
  };
}

enum UnscoredReason {
  tooShort('too_short'),
  passenger('passenger');

  const UnscoredReason(this.wire);
  final String wire;
}

/// Everything in a [TripScore] except the feedback. `buildFeedback` consumes this
/// (the TS `Omit<TripScore, 'feedback'>`).
class TripScoreBase {
  const TripScoreBase({
    required this.tripId,
    required this.scored,
    this.unscoredReason,
    required this.score,
    required this.penalties,
    required this.flags,
    required this.reckless,
    required this.xp,
    required this.events,
    required this.observations,
    required this.summary,
  });

  final String tripId;

  /// False when the trip was too short or a passenger trip.
  final bool scored;
  final UnscoredReason? unscoredReason;

  /// 0–100. 0 when unscored.
  final int score;
  final ComponentPenalties penalties;
  final List<Flag> flags;
  final bool reckless;
  final int xp;

  /// Events that counted toward the score.
  final List<TripEvent> events;

  /// Speeding seen on low-confidence segments: shown, never scored.
  final List<TripEvent> observations;
  final TripSummary summary;

  Map<String, Object?> toJson() => {
    'tripId': tripId,
    'scored': scored,
    if (unscoredReason != null) 'unscoredReason': unscoredReason!.wire,
    'score': score,
    'penalties': penalties.toJson(),
    'flags': [for (final f in flags) f.wire],
    'reckless': reckless,
    'xp': xp,
    'events': [for (final e in events) e.toJson()],
    'observations': [for (final e in observations) e.toJson()],
    'summary': summary.toJson(),
  };
}

class TripScore extends TripScoreBase {
  const TripScore({
    required super.tripId,
    required super.scored,
    super.unscoredReason,
    required super.score,
    required super.penalties,
    required super.flags,
    required super.reckless,
    required super.xp,
    required super.events,
    required super.observations,
    required super.summary,
    required this.feedback,
  });

  TripScore.fromBase(TripScoreBase base, this.feedback)
    : super(
        tripId: base.tripId,
        scored: base.scored,
        unscoredReason: base.unscoredReason,
        score: base.score,
        penalties: base.penalties,
        flags: base.flags,
        reckless: base.reckless,
        xp: base.xp,
        events: base.events,
        observations: base.observations,
        summary: base.summary,
      );

  final Feedback feedback;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'feedback': feedback.toJson(),
  };
}

class ScoreOptions {
  const ScoreOptions({this.intensity, this.units});

  factory ScoreOptions.fromJson(Map<String, dynamic> json) => ScoreOptions(
    intensity: json['intensity'] == null
        ? null
        : Intensity.fromWire(json['intensity'] as String),
    units: json['units'] == null
        ? null
        : SpeedUnits.fromWire(json['units'] as String),
  );

  /// Default sassy.
  final Intensity? intensity;

  /// Default mph.
  final SpeedUnits? units;

  Map<String, Object?> toJson() => {
    if (intensity != null) 'intensity': intensity!.wire,
    if (units != null) 'units': units!.wire,
  };
}
