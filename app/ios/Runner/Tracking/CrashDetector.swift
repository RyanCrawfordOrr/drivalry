import Foundation

/// docs/08-tracking-channel.md §4 `crashCandidate`, as a pure rule with no CoreMotion or
/// CoreLocation types. Mirrors the Kotlin and Dart copies line for line.
///
/// Three things must hold inside one window: a linear-acceleration peak of at least
/// `peakThresholdMps2` (about 4 g); GPS speed of at least `speedBeforeMinMps` somewhere in the
/// `beforeWindowMs` before the peak (a dropped phone at a standstill or a speed bump at parking
/// speed never counts); and every GPS fix in the `afterWindowMs` after the peak below
/// `speedAfterMaxMps` (a fix without a speed counts as stopped), with at least `minAfterSamples`
/// such fixes. Fires at most once per trip.
///
/// Thread-safe: acceleration samples arrive on the motion queue, speeds on the main thread.
final class CrashDetector {
  struct Candidate {
    let t: Int64
    let peakMps2: Double
    let speedBeforeMps: Double
  }

  private final class Pending {
    var t: Int64
    var peak: Double
    let speedBefore: Double
    var afterSamples = 0
    init(t: Int64, peak: Double, speedBefore: Double) {
      self.t = t
      self.peak = peak
      self.speedBefore = speedBefore
    }
  }

  let peakThresholdMps2: Double
  let speedBeforeMinMps: Double
  let speedAfterMaxMps: Double
  let beforeWindowMs: Int64
  let afterWindowMs: Int64
  let giveUpMs: Int64
  let historyMs: Int64
  let minAfterSamples: Int

  private let lock = NSLock()
  private var speeds: [(t: Int64, v: Double)] = []
  private var pending: Pending?
  private var firedFlag = false

  init(
    peakThresholdMps2: Double = 40,
    speedBeforeMinMps: Double = 8,
    speedAfterMaxMps: Double = 1,
    beforeWindowMs: Int64 = 3_000,
    afterWindowMs: Int64 = 5_000,
    giveUpMs: Int64 = 8_000,
    historyMs: Int64 = 10_000,
    minAfterSamples: Int = 2
  ) {
    self.peakThresholdMps2 = peakThresholdMps2
    self.speedBeforeMinMps = speedBeforeMinMps
    self.speedAfterMaxMps = speedAfterMaxMps
    self.beforeWindowMs = beforeWindowMs
    self.afterWindowMs = afterWindowMs
    self.giveUpMs = giveUpMs
    self.historyMs = historyMs
    self.minAfterSamples = minAfterSamples
  }

  /// True once a candidate has been reported for the current trip.
  var fired: Bool {
    lock.lock()
    defer { lock.unlock() }
    return firedFlag
  }

  /// Call at every trip start and end.
  func reset() {
    lock.lock()
    defer { lock.unlock() }
    speeds.removeAll()
    pending = nil
    firedFlag = false
  }

  /// One acceleration sample (m/s², gravity removed). Returns true when it opened a candidate.
  @discardableResult
  func onAccel(t: Int64, magnitudeMps2: Double) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if firedFlag || magnitudeMps2 < peakThresholdMps2 { return false }
    trim(now: t)
    guard let before = maxSpeed(from: t - beforeWindowMs, to: t), before >= speedBeforeMinMps else {
      return false
    }
    if let p = pending {
      if magnitudeMps2 > p.peak {
        p.peak = magnitudeMps2
        p.t = t
      }
      return false
    }
    pending = Pending(t: t, peak: magnitudeMps2, speedBefore: before)
    return true
  }

  /// One GPS speed sample (nil when CoreLocation reports none). Returns the confirmed candidate.
  func onSpeed(t: Int64, speedMps: Double?) -> Candidate? {
    lock.lock()
    defer { lock.unlock() }
    if let v = speedMps {
      speeds.append((t: t, v: v))
      trim(now: t)
    }
    guard let p = pending, !firedFlag else { return nil }
    if t <= p.t { return nil }  // a fix from before the impact
    if t > p.t + giveUpMs {
      pending = nil  // never confirmed
      return nil
    }
    // No speed is what CoreLocation reports at a standstill: counts as stopped evidence here
    // (the before-window above still only trusts fixes that carry a speed).
    let v = speedMps ?? 0
    if v >= speedAfterMaxMps {
      pending = nil  // moving again: a pothole, not a crash
      return nil
    }
    p.afterSamples += 1
    if t >= p.t + afterWindowMs && p.afterSamples >= minAfterSamples {
      firedFlag = true
      pending = nil
      return Candidate(t: p.t, peakMps2: p.peak, speedBeforeMps: p.speedBefore)
    }
    return nil
  }

  private func maxSpeed(from: Int64, to: Int64) -> Double? {
    var best: Double?
    for sample in speeds where sample.t >= from && sample.t <= to {
      if let current = best, sample.v <= current { continue }
      best = sample.v
    }
    return best
  }

  private func trim(now: Int64) {
    speeds.removeAll { $0.t < now - historyMs }
  }
}
