import Foundation

/// The phases Dart observes (docs/08 §2). `ending` is internal and never stored.
enum TripPhase: String {
  case idle
  case tentative
  case active
}

protocol TripStateMachineDelegate: AnyObject {
  /// idle → tentative. `reason` is the trigger kind.
  func tripStateMachine(_ machine: TripStateMachine, didStartTentative tripId: String, reason: String, at t: Int64)
  /// tentative → active (or idle → active for `forceStart`). `startedAt` is the first confirmed fix.
  func tripStateMachine(_ machine: TripStateMachine, didActivate tripId: String, reason: String, startedAt: Int64, at t: Int64)
  /// active → idle. `reason` is "stationary" | "exit" | "manual".
  func tripStateMachine(_ machine: TripStateMachine, didEnd tripId: String, reason: String, at t: Int64)
  /// tentative → idle without confirmation.
  func tripStateMachine(_ machine: TripStateMachine, didDiscard tripId: String, at t: Int64)
}

/// idle → tentative → active → ended/discarded, persisted in the tracking UserDefaults suite
/// so a background relaunch (significant change, geofence) resumes exactly where it left off.
///
/// Rules (docs/08 §2 and §6):
/// - tentative → active when speed stays >= 4 m/s for 20 s (startedAt = first fast fix)
/// - tentative → discarded after 120 s without confirmation
/// - active → ended "stationary" after 180 s without a fix >= 1 m/s (also covers "no fix at all")
/// - active → ended "exit" on a walking/running/cycling activity while no car audio route is connected
/// - manual start/end from Dart
///
/// Main-thread confined. It never touches the OS; the plugin feeds it fixes, activity and timer ticks.
final class TripStateMachine {
  static let confirmSpeedMps: Double = 4.0
  static let confirmDurationMs: Int64 = 20_000
  static let unconfirmedTimeoutMs: Int64 = 120_000
  static let stationarySpeedMps: Double = 1.0
  static let stationaryTimeoutMs: Int64 = 180_000

  private enum Key {
    static let phase = "trip.phase"
    static let tripId = "trip.id"
    static let reason = "trip.reason"
    static let tentativeAt = "trip.tentativeAt"
    static let startedAt = "trip.startedAt"
    static let fastSince = "trip.fastSince"
    static let lastMovingAt = "trip.lastMovingAt"
  }

  weak var delegate: TripStateMachineDelegate?

  private let store: TrackingStore

  private(set) var phase: TripPhase = .idle
  private(set) var tripId: String?
  /// Trigger kind that started the trip ("activity", "bluetooth", "geofence", "significantChange", "manual").
  private(set) var reason: String?
  private(set) var tentativeAt: Int64?
  private(set) var startedAt: Int64?
  /// First fix of the current run of fixes faster than `confirmSpeedMps` (tentative only).
  private var fastSince: Int64?
  /// Time of the last fix faster than `stationarySpeedMps` (active only).
  private var lastMovingAt: Int64?

  init(store: TrackingStore) {
    self.store = store
    restore()
  }

  // MARK: - Persistence

  private func restore() {
    let saved = store.string(Key.phase).flatMap { TripPhase(rawValue: $0) } ?? .idle
    tripId = store.string(Key.tripId)
    reason = store.string(Key.reason)
    tentativeAt = store.int64(Key.tentativeAt)
    startedAt = store.int64(Key.startedAt)
    fastSince = store.int64(Key.fastSince)
    lastMovingAt = store.int64(Key.lastMovingAt)
    // A non-idle phase without an id is corrupt; fall back to idle.
    if saved != .idle && tripId == nil {
      clear()
    } else {
      phase = saved
    }
  }

  private func persist() {
    store.set(phase.rawValue, forKey: Key.phase)
    store.set(tripId, forKey: Key.tripId)
    store.set(reason, forKey: Key.reason)
    store.set(tentativeAt, forKey: Key.tentativeAt)
    store.set(startedAt, forKey: Key.startedAt)
    store.set(fastSince, forKey: Key.fastSince)
    store.set(lastMovingAt, forKey: Key.lastMovingAt)
    store.synchronize()
  }

  private func clear() {
    phase = .idle
    tripId = nil
    reason = nil
    tentativeAt = nil
    startedAt = nil
    fastSince = nil
    lastMovingAt = nil
    persist()
  }

  private static func newTripId() -> String {
    return UUID().uuidString.lowercased()  // Foundation UUIDs are version 4
  }

  // MARK: - Inputs

  /// A trigger fired while idle. The caller has already checked enabled/paused/permissions.
  func trigger(kind: String, at t: Int64) {
    guard phase == .idle else { return }
    let id = TripStateMachine.newTripId()
    phase = .tentative
    tripId = id
    reason = kind
    tentativeAt = t
    startedAt = nil
    fastSince = nil
    lastMovingAt = nil
    persist()
    delegate?.tripStateMachine(self, didStartTentative: id, reason: kind, at: t)
  }

  /// A GPS fix. `speed` is nil when the OS reports it as unknown (negative).
  func fix(t: Int64, speed: Double?) {
    switch phase {
    case .idle:
      return
    case .tentative:
      if let speed = speed, speed >= TripStateMachine.confirmSpeedMps {
        if fastSince == nil { fastSince = t }
        if let since = fastSince, t - since >= TripStateMachine.confirmDurationMs {
          activate(startedAt: since, at: t)
          return
        }
      } else {
        fastSince = nil
      }
      checkUnconfirmed(now: t)
    case .active:
      if let speed = speed, speed >= TripStateMachine.stationarySpeedMps {
        lastMovingAt = t
      } else {
        checkStationary(now: t)
      }
    }
  }

  /// Periodic wall-clock tick from the plugin (covers "no fixes arriving at all").
  func tick(now: Int64) {
    switch phase {
    case .idle: return
    case .tentative: checkUnconfirmed(now: now)
    case .active: checkStationary(now: now)
    }
  }

  /// CoreMotion says the user is walking/running/cycling (confidence >= medium).
  /// Ends the trip only when no car audio route (Bluetooth / CarPlay) is connected.
  func automotiveExit(carAudioConnected: Bool, at t: Int64) {
    guard phase == .active, !carAudioConnected else { return }
    end(reason: "exit", at: t)
  }

  /// `forceStartTrip`: straight to active with a new id. An existing trip is closed first.
  func forceStart(at t: Int64) {
    switch phase {
    case .active:
      end(reason: "manual", at: t)
    case .tentative:
      discard(at: t)
    case .idle:
      break
    }
    let id = TripStateMachine.newTripId()
    phase = .tentative
    tripId = id
    reason = "manual"
    tentativeAt = t
    persist()
    delegate?.tripStateMachine(self, didStartTentative: id, reason: "manual", at: t)
    activate(startedAt: t, at: t)
  }

  /// `forceEndTrip` and `setEnabled(false)`.
  func forceEnd(at t: Int64) {
    switch phase {
    case .active: end(reason: "manual", at: t)
    case .tentative: discard(at: t)
    case .idle: break
    }
  }

  // MARK: - Transitions

  private func activate(startedAt start: Int64, at t: Int64) {
    guard let id = tripId, let kind = reason else { return }
    phase = .active
    startedAt = start
    lastMovingAt = max(start, t)
    fastSince = nil
    persist()
    delegate?.tripStateMachine(self, didActivate: id, reason: kind, startedAt: start, at: t)
  }

  private func checkUnconfirmed(now: Int64) {
    guard phase == .tentative, let since = tentativeAt else { return }
    if now - since >= TripStateMachine.unconfirmedTimeoutMs {
      discard(at: now)
    }
  }

  private func checkStationary(now: Int64) {
    guard phase == .active else { return }
    let reference = lastMovingAt ?? startedAt ?? now
    if now - reference >= TripStateMachine.stationaryTimeoutMs {
      // The trip ended when the car stopped moving plus the grace period, not when we noticed.
      end(reason: "stationary", at: min(now, reference + TripStateMachine.stationaryTimeoutMs))
    }
  }

  private func end(reason endReason: String, at t: Int64) {
    guard phase == .active, let id = tripId else { return }
    clear()
    delegate?.tripStateMachine(self, didEnd: id, reason: endReason, at: t)
  }

  private func discard(at t: Int64) {
    guard phase == .tentative, let id = tripId else { return }
    clear()
    delegate?.tripStateMachine(self, didDiscard: id, at: t)
  }
}
