import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// The Live Activity shown on the lock screen and in the Dynamic Island while
/// a drive or convoy is active (docs/04 §2 "Without the entitlement").
///
/// This file is a member of BOTH the Runner target and the DrivalryWidgets
/// extension target: ActivityKit requires the exact same type on both sides.
/// Keep it free of app-only imports.
@available(iOS 16.2, *)
struct DriveActivityAttributes: ActivityAttributes {
  /// Everything that changes during the drive. Mirrors the Dart
  /// `LiveActivityContent` in `lib/car/live_activity.dart`.
  struct ContentState: Codable, Hashable {
    /// Posted limit in `limitUnit`, nil when the pack has none here.
    var limitPosted: Int?
    /// "mph" or "km/h".
    var limitUnit: String
    /// Current speed in `limitUnit`, nil when unknown.
    var speedPosted: Int?
    /// No over-limit second and no harsh event so far this trip.
    var cleanSoFar: Bool
    /// How far over the limit right now, in `limitUnit`; nil when not over.
    var overBy: Int?
    var roadName: String?
    var tripMinutes: Int
    /// A trip is being recorded (false for a convoy that is not driving yet):
    /// only then does the widget show and tick trip minutes.
    var recording: Bool
    /// Convoy line, all nil when not in an active convoy.
    var convoyName: String?
    var gapMinutes: Int?
    var etaMinutes: Int?
    /// Display name of whoever is holding push-to-talk, nil when silent.
    var talking: String?
    /// When the phone produced this state; the widget shows staleness.
    var updatedAt: Date
  }

  /// The trip's start, fixed for the life of the activity; nil when the
  /// activity was opened for a convoy before any trip began (the widget then
  /// shows the minutes the state carries). The phone starts a new activity
  /// for each trip, so this never refers to an earlier leg.
  var startedAt: Date?
}
#endif
