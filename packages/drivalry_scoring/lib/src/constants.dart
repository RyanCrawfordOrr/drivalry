/// Tunable rules of the scoring engine. Mirrors `packages/scoring/src/constants.ts`.
///
/// Every value is a `double` unless it is compared against or assigned to an integer in the
/// engine, so that arithmetic stays in double precision exactly as in JavaScript.
library;

import 'types.dart';

/// 1 mph in m/s.
const double mph = 0.44704;

/// 1 km/h in m/s.
const double kmh = 1 / 3.6;

double mphToMps(double v) => v * mph;
double mpsToMph(double mps) => mps / mph;
double mpsToKmh(double mps) => mps / kmh;

/// Below this the car is considered stopped (m/s).
const double movingSpeed = 1.0;

/// Samples with worse horizontal accuracy are excluded from speeding detection (m).
const double gpsMaxAccuracy = 50;

/// Segments below this confidence can produce observations, never penalties.
const double speedingMinConfidence = 0.7;

abstract final class Speeding {
  /// An episode must exceed the limit by at least this much (m/s).
  static const double minOver = 5 * mph;

  /// Episodes shorter than this are ignored.
  static const double minDurationS = 8;

  /// Episodes separated by less than this gap are merged.
  static const double mergeGapS = 10;

  /// Per-episode duration cap for penalty purposes.
  static const double maxPenalisedDurationS = 300;

  static const thresholds = (
    moderate: 10 * mph,
    major: 15 * mph,
    reckless: 25 * mph,
  );

  /// Any speed at or above this is reckless regardless of the limit.
  static const double recklessAbsolute = 100 * mph;
  static const double recklessAbsoluteMinDurationS = 3;

  /// After the posted limit drops, the car gets this long to slow down before over-limit
  /// samples count, provided it is actually decelerating (65 → 25 at 1.5 m/s² takes ~12 s).
  static const double limitDropGraceS = 15;

  /// First seconds after a drop are exempt unconditionally (reaction time).
  static const double graceFreeS = 3;

  /// Minimum per-second speed drop to count as "decelerating" during grace.
  static const double graceMinDecel = 0.15;

  /// Penalty weights per minute by severity.
  static const Map<Severity, double> weightPerMinute = {
    Severity.minor: 1.0,
    Severity.moderate: 2.5,
    Severity.major: 6.0,
    Severity.reckless: 12.0,
  };

  /// Proportion term: 15 × (seconds over / moving seconds).
  static const double proportionWeight = 15;
  static const double cap = 40;
}

abstract final class Smoothness {
  static const brake = (moderate: 3.5, severe: 5.0);
  static const accel = (moderate: 3.0, severe: 4.5);
  static const corner = (moderate: 4.0, severe: 6.0);

  /// Minimum sustained duration when deriving from GPS.
  static const double minSustainedS = 0.7;
  static const double mergeGapS = 3;

  /// Cornering is only evaluated above this speed (GPS heading is noise below it).
  static const double cornerMinSpeed = 5.0;

  static const Map<EventKind, ({double moderate, double severe})> weights = {
    EventKind.harshBrake: (moderate: 2.0, severe: 4.0),
    EventKind.harshAccel: (moderate: 1.5, severe: 3.0),
    EventKind.hardCorner: (moderate: 1.5, severe: 3.0),
  };

  /// Penalties are normalised to this distance.
  static const double normaliseDistanceM = 10000;

  /// Trips shorter than this are normalised as if this long.
  static const double minNormaliseDistanceM = 3000;
  static const double cap = 30;
}

abstract final class Attention {
  /// Phone events only count above this speed (m/s ≈ 11 mph).
  static const double minSpeed = 5.0;
  static const double mergeGapS = 20;

  /// A single tap still "costs" this many seconds of attention.
  static const double minEpisodeS = 3;
  static const thresholds = (moderateS: 10.0, majorS: 45.0);

  /// Any handling at or above this speed is Major.
  static const double majorSpeed = 60 * mph;
  static const Map<Severity, double> weights = {
    Severity.minor: 3,
    Severity.moderate: 7,
    Severity.major: 12,
  };

  /// Reckless: Major episode at highway speed lasting this long.
  static const double recklessDurationS = 60;
  static const double cap = 30;
}

abstract final class Efficiency {
  static const idle = (freeS: 120.0, weightPerMinute: 0.5, cap: 4.0);
  static const cruise = (
    speed: 75 * mph,
    weightPerMinute: 1.0,
    cap: 6.0,
    minEventS: 10.0,
  );
  static const aggression = (perHarshAccel: 0.5, cap: 5.0);
  static const double cap = 15;
}

abstract final class Reckless {
  static const int scoreCap = 25;

  /// "Driving like you're being chased": this many severe motion events plus a major speeding episode.
  static const int patternSevereEvents = 3;
}

abstract final class Minimums {
  static const double distanceM = 1000;
  static const double movingTimeS = 120;
}

abstract final class Xp {
  static const double minScore = 50;
  static const double minXp = 10;
  static const double maxXp = 100;
  static const double distanceFloor = 0.4;
  static const double fullCreditKm = 15;
  static const double dailyCapKm = 100;
  static const double nightBonus = 1.1;
  static const double weatherBonus = 1.1;
  static const double maxContextBonus = 1.2;
  static const double bonusMinScore = 85;
  static const streak = (tier1: 5, tier1Xp: 5.0, tier2: 20, tier2Xp: 10.0);

  /// A trip keeps a clean streak alive when it scores at least this.
  static const double cleanTripScore = 80;
}
