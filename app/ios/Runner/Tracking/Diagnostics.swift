import Foundation
import UIKit

/// `nil` → `NSNull()` for channel replies and spool JSON. Swift optionals inside `Any`
/// would otherwise be encoded as missing keys or fail JSON serialisation.
func orNull(_ value: Any?) -> Any {
  return value ?? NSNull()
}

/// Epoch milliseconds, the only time unit the tracking contract uses.
enum TrackingClock {
  static func nowMs() -> Int64 {
    return Int64(Date().timeIntervalSince1970 * 1000.0)
  }

  static func ms(_ date: Date) -> Int64 {
    return Int64(date.timeIntervalSince1970 * 1000.0)
  }
}

/// Thin wrapper over the `app.drivalry.tracking` UserDefaults suite (docs/08 §6).
/// Everything the plugin persists (settings, trip state, counters) goes through here.
final class TrackingStore {
  static let suiteName = "app.drivalry.tracking"

  private let defaults: UserDefaults

  init() {
    // `UserDefaults(suiteName:)` only returns nil for the bundle id or a global domain;
    // fall back to standard defaults rather than crash.
    defaults = UserDefaults(suiteName: TrackingStore.suiteName) ?? UserDefaults.standard
  }

  func string(_ key: String) -> String? {
    return defaults.string(forKey: key)
  }

  func int64(_ key: String) -> Int64? {
    return (defaults.object(forKey: key) as? NSNumber)?.int64Value
  }

  func int(_ key: String) -> Int {
    return (defaults.object(forKey: key) as? NSNumber)?.intValue ?? 0
  }

  func double(_ key: String) -> Double? {
    return (defaults.object(forKey: key) as? NSNumber)?.doubleValue
  }

  func bool(_ key: String, default defaultValue: Bool) -> Bool {
    guard let number = defaults.object(forKey: key) as? NSNumber else { return defaultValue }
    return number.boolValue
  }

  func set(_ value: String?, forKey key: String) {
    if let value = value {
      defaults.set(value, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  func set(_ value: Int64?, forKey key: String) {
    if let value = value {
      defaults.set(NSNumber(value: value), forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  func set(_ value: Double?, forKey key: String) {
    if let value = value {
      defaults.set(NSNumber(value: value), forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  func set(_ value: Bool, forKey key: String) {
    defaults.set(NSNumber(value: value), forKey: key)
  }

  func set(_ value: Int, forKey key: String) {
    defaults.set(NSNumber(value: value), forKey: key)
  }

  func remove(_ key: String) {
    defaults.removeObject(forKey: key)
  }

  /// Flush to disk now. Called after trip transitions so a kill right after
  /// a transition does not lose the state the relaunch path depends on.
  func synchronize() {
    defaults.synchronize()
  }
}

/// The `Diagnostics` map of docs/08 §3.3, backed by counters in the tracking suite.
final class TrackingDiagnostics {
  private enum Key {
    static let lastTriggerAt = "diag.lastTriggerAt"
    static let lastTriggerKind = "diag.lastTriggerKind"
    static let tentativeStarts = "diag.tentativeStarts"
    static let confirmedTrips = "diag.confirmedTrips"
    static let discardedTentatives = "diag.discardedTentatives"
    static let lastTripEndedAt = "diag.lastTripEndedAt"
    static let lastTripEndReason = "diag.lastTripEndReason"
  }

  private let store: TrackingStore

  init(store: TrackingStore) {
    self.store = store
    // Battery level reads -1 unless monitoring is enabled.
    UIDevice.current.isBatteryMonitoringEnabled = true
  }

  func recordTrigger(kind: String, at t: Int64) {
    store.set(t, forKey: Key.lastTriggerAt)
    store.set(kind, forKey: Key.lastTriggerKind)
  }

  func recordTentativeStart() {
    store.set(store.int(Key.tentativeStarts) + 1, forKey: Key.tentativeStarts)
  }

  func recordConfirmedTrip() {
    store.set(store.int(Key.confirmedTrips) + 1, forKey: Key.confirmedTrips)
  }

  func recordDiscardedTentative() {
    store.set(store.int(Key.discardedTentatives) + 1, forKey: Key.discardedTentatives)
  }

  func recordTripEnd(reason: String, at t: Int64) {
    store.set(t, forKey: Key.lastTripEndedAt)
    store.set(reason, forKey: Key.lastTripEndReason)
  }

  /// `batteryLevel`: 0–1, or nil when the OS reports -1 (unknown / simulator).
  private func batteryLevel() -> Double? {
    let level = UIDevice.current.batteryLevel
    if level < 0 { return nil }
    return Double(level)
  }

  func map(serviceRunning: Bool) -> [String: Any] {
    return [
      "lastTriggerAt": orNull(store.int64(Key.lastTriggerAt)),
      "lastTriggerKind": orNull(store.string(Key.lastTriggerKind)),
      "tentativeStarts": store.int(Key.tentativeStarts),
      "confirmedTrips": store.int(Key.confirmedTrips),
      "discardedTentatives": store.int(Key.discardedTentatives),
      "lastTripEndedAt": orNull(store.int64(Key.lastTripEndedAt)),
      "lastTripEndReason": orNull(store.string(Key.lastTripEndReason)),
      "batteryLevel": orNull(batteryLevel()),
      "serviceRunning": serviceRunning,
    ]
  }
}
