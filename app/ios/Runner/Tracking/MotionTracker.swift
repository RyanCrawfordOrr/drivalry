import CoreMotion
import Foundation

protocol MotionTrackerDelegate: AnyObject {
  /// CoreMotion reports `automotive` with at least medium confidence (trigger kind "activity").
  func motionTracker(_ tracker: MotionTracker, didDetectAutomotiveAt t: Int64)
  /// CoreMotion reports walking/running/cycling with at least medium confidence: the user left the car.
  func motionTracker(_ tracker: MotionTracker, didDetectExitAt t: Int64)
  func motionTracker(_ tracker: MotionTracker, didFail code: String, message: String)
}

/// CoreMotion wrapper (docs/08 §6, iOS).
///
/// - `CMMotionActivityManager` activity updates (main queue) for automotive enter/exit.
/// - `CMMotionManager` device motion at 20 Hz while a trip is active, reduced on a serial
///   background queue to one peak per second of horizontal user acceleration (gravity removed,
///   m/s²). Only seconds whose peak exceeds 2.5 m/s² are kept; raw samples are never stored.
final class MotionTracker {
  static let sampleRateHz: Double = 20
  static let peakThresholdMps2: Double = 2.5
  static let standardGravity: Double = 9.80665

  weak var delegate: MotionTrackerDelegate?

  /// docs/08 §4 `crashCandidate`. Fed the full user-acceleration magnitude of every 20 Hz sample
  /// here and every fix's speed by the plugin; reset at each trip start.
  let crash = CrashDetector()

  private let activityManager = CMMotionActivityManager()
  private let motionManager = CMMotionManager()
  private let motionQueue: OperationQueue
  private let lock = NSLock()

  // Protected by `lock` (written on motionQueue, read on main).
  private var pendingPeaks: [[String: Any]] = []
  private var currentSecond: Int64?
  private var currentPeak: Double = 0
  private var currentPeakAt: Int64 = 0

  private(set) var activityUpdatesRunning = false
  private(set) var deviceMotionRunning = false

  init() {
    motionQueue = OperationQueue()
    motionQueue.name = "app.drivalry.tracking.motion"
    motionQueue.maxConcurrentOperationCount = 1
    motionQueue.qualityOfService = .utility
  }

  deinit {
    activityManager.stopActivityUpdates()
    motionManager.stopDeviceMotionUpdates()
  }

  // MARK: - Activity (triggers)

  static var isActivityAvailable: Bool {
    return CMMotionActivityManager.isActivityAvailable()
  }

  static var authorizationStatus: CMAuthorizationStatus {
    return CMMotionActivityManager.authorizationStatus()
  }

  /// Starting updates is also what shows the Motion & Fitness prompt the first time.
  func startActivityUpdates() {
    guard !activityUpdatesRunning, CMMotionActivityManager.isActivityAvailable() else { return }
    activityUpdatesRunning = true
    activityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
      guard let self = self, let activity = activity else { return }
      self.handle(activity)
    }
  }

  func stopActivityUpdates() {
    guard activityUpdatesRunning else { return }
    activityManager.stopActivityUpdates()
    activityUpdatesRunning = false
  }

  private func handle(_ activity: CMMotionActivity) {
    // Low-confidence classifications flap at traffic lights; the tentative phase is the real filter,
    // but requiring medium confidence keeps the GPS radio off for most false positives.
    guard activity.confidence != .low else { return }
    let t = TrackingClock.ms(activity.startDate)
    if activity.automotive {
      delegate?.motionTracker(self, didDetectAutomotiveAt: t)
    } else if activity.walking || activity.running || activity.cycling {
      delegate?.motionTracker(self, didDetectExitAt: t)
    }
  }

  // MARK: - Device motion (accel peaks)

  func startDeviceMotion() {
    guard !deviceMotionRunning else { return }
    guard motionManager.isDeviceMotionAvailable else {
      delegate?.motionTracker(self, didFail: "motionUnavailable", message: "Device motion is not available on this device")
      return
    }
    deviceMotionRunning = true
    lock.lock()
    pendingPeaks.removeAll()
    currentSecond = nil
    currentPeak = 0
    lock.unlock()
    crash.reset()
    motionManager.deviceMotionUpdateInterval = 1.0 / MotionTracker.sampleRateHz
    motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, _ in
      guard let self = self, let motion = motion else { return }
      self.process(motion)
    }
  }

  func stopDeviceMotion() {
    guard deviceMotionRunning else { return }
    motionManager.stopDeviceMotionUpdates()
    deviceMotionRunning = false
    lock.lock()
    closeBucketLocked()
    lock.unlock()
  }

  /// Completed per-second peaks since the last drain, as `motion.events[]` entries (docs/08 §4).
  func drainPeaks() -> [[String: Any]] {
    lock.lock()
    defer { lock.unlock() }
    let peaks = pendingPeaks
    pendingPeaks.removeAll()
    return peaks
  }

  /// Runs on `motionQueue`.
  private func process(_ motion: CMDeviceMotion) {
    let g = motion.gravity
    let a = motion.userAcceleration
    let t = MotionTracker.wallClockMs(forUptime: motion.timestamp)
    // Crash detection uses the full gravity-free vector: a head-on impact is mostly horizontal,
    // but the phone's orientation is unknown and a 4 g hit is unambiguous in any axis.
    let fullMps2 = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() * MotionTracker.standardGravity
    crash.onAccel(t: t, magnitudeMps2: fullMps2)
    let gMagnitude = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
    guard gMagnitude > 0.0001 else { return }
    // Remove the component of user acceleration along gravity; what remains is horizontal.
    let along = (a.x * g.x + a.y * g.y + a.z * g.z) / gMagnitude
    let hx = a.x - along * g.x / gMagnitude
    let hy = a.y - along * g.y / gMagnitude
    let hz = a.z - along * g.z / gMagnitude
    let horizontalMps2 = (hx * hx + hy * hy + hz * hz).squareRoot() * MotionTracker.standardGravity
    let second = t / 1000

    lock.lock()
    defer { lock.unlock() }
    if let current = currentSecond, current != second {
      closeBucketLocked()
    }
    if currentSecond == nil {
      currentSecond = second
      currentPeak = 0
      currentPeakAt = t
    }
    if horizontalMps2 > currentPeak {
      currentPeak = horizontalMps2
      currentPeakAt = t
    }
  }

  /// Caller holds `lock`.
  private func closeBucketLocked() {
    if currentSecond != nil, currentPeak > MotionTracker.peakThresholdMps2 {
      pendingPeaks.append([
        "t": currentPeakAt,
        "kind": "accelPeak",
        "peak": currentPeak,
      ])
    }
    currentSecond = nil
    currentPeak = 0
  }

  /// `CMDeviceMotion.timestamp` is seconds since boot; convert to epoch milliseconds.
  private static func wallClockMs(forUptime uptime: TimeInterval) -> Int64 {
    let bootEpoch = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
    return Int64((bootEpoch + uptime) * 1000.0)
  }
}
