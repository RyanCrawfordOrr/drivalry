import CoreLocation
import Foundation

protocol LocationTrackerDelegate: AnyObject {
  /// Every valid fix while in `.recording` mode (tentative and active), as it arrives.
  func locationTracker(_ tracker: LocationTracker, didReceiveFix location: CLLocation)
  /// A batch of fix maps (docs/08 §4 `fixes`), every 20 s or 20 fixes while buffering.
  /// `fixes` may be empty on a timer flush; `lastFixAt` is the `t` of the last fix in the batch.
  func locationTracker(_ tracker: LocationTracker, didFlush fixes: [[String: Any]], lastFixAt: Int64?)
  /// A parked backstop fired: `"significantChange"` or `"geofence"`.
  func locationTracker(_ tracker: LocationTracker, didFireTrigger kind: String, at t: Int64)
  /// A position the OS delivered for free while `.parked` (significant change, region exit), just
  /// before the matching trigger. Nothing was requested for it (docs/08 §4 `parkedFix`).
  func locationTracker(_ tracker: LocationTracker, didObserveParkedFix location: CLLocation)
  func locationTrackerDidChangeAuthorization(_ tracker: LocationTracker)
  func locationTracker(_ tracker: LocationTracker, didFail code: String, message: String)
}

/// CoreLocation wrapper (docs/08 §6, iOS).
///
/// - `.recording` (tentative/active): standard updates at full accuracy, background allowed,
///   automotive activity type, no pausing. Fixes are forwarded one by one; while `buffering`
///   they are also collected and flushed every 20 s or 20 fixes.
/// - `.parked` (idle): significant-change monitoring plus a 100 m exit region around the last
///   trip end. Both relaunch a terminated app; on relaunch the AppDelegate recreates this object
///   and `setMode(.parked)` restarts the services so the pending callback is delivered.
/// - `.off`: nothing armed (tracking disabled or no permission).
///
/// Must be created and used on the main thread: CLLocationManager needs a run loop for its delegate.
final class LocationTracker: NSObject, CLLocationManagerDelegate {
  enum Mode: Equatable {
    case off
    case parked
    case recording
  }

  static let flushInterval: TimeInterval = 20
  static let flushBatchSize = 20
  static let parkedRegionRadius: CLLocationDistance = 100
  static let parkedRegionIdentifier = "app.drivalry.tracking.parked"
  /// Fixes kept during `tentative` so the confirmation window can join the trip once it is active.
  static let tentativeRetention = 90

  weak var delegate: LocationTrackerDelegate?

  private let manager = CLLocationManager()
  private(set) var mode: Mode = .off
  private(set) var isBuffering = false
  private var parkedCenter: CLLocationCoordinate2D?
  private var buffer: [[String: Any]] = []
  private var lastBufferedAt: Int64?
  private var recentFixes: [[String: Any]] = []
  private var flushTimer: Timer?
  /// The last valid fix received in `.recording` mode (centre of the next parked region).
  private(set) var lastFix: CLLocation?
  /// Callers waiting for a `requestLocation()` answer (docs/08 §3 `getLastKnownLocation`).
  private var oneShotCompletions: [(CLLocation?) -> Void] = []
  private var oneShotTimer: Timer?
  /// Where the phone was when the one-shot was requested, so the answer can be told apart from a
  /// genuine significant change that lands inside the request window.
  private var oneShotAnchor: CLLocation?

  override init() {
    super.init()
    manager.delegate = self
    manager.pausesLocationUpdatesAutomatically = false
    manager.activityType = .automotiveNavigation
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.distanceFilter = kCLDistanceFilterNone
  }

  deinit {
    flushTimer?.invalidate()
    oneShotTimer?.invalidate()
  }

  // MARK: - Authorization

  var authorizationStatus: CLAuthorizationStatus {
    return manager.authorizationStatus
  }

  var isAuthorized: Bool {
    let status = manager.authorizationStatus
    return status == .authorizedAlways || status == .authorizedWhenInUse
  }

  var isPreciseLocation: Bool {
    return manager.accuracyAuthorization == .fullAccuracy
  }

  func requestWhenInUseAuthorization() {
    manager.requestWhenInUseAuthorization()
  }

  func requestAlwaysAuthorization() {
    manager.requestAlwaysAuthorization()
  }

  // MARK: - Modes

  func setMode(_ newMode: Mode, parkedAt center: CLLocationCoordinate2D?) {
    if newMode == mode {
      if newMode == .parked { rearmRegionIfMoved(center) }
      return
    }
    let previous = mode
    mode = newMode
    switch newMode {
    case .off:
      stopRecording()
      manager.stopMonitoringSignificantLocationChanges()
      stopRegions()
      parkedCenter = nil
    case .parked:
      stopRecording()
      if CLLocationManager.significantLocationChangeMonitoringAvailable() {
        manager.startMonitoringSignificantLocationChanges()
      }
      parkedCenter = nil
      rearmRegionIfMoved(center)
    case .recording:
      // Keep significant-change monitoring running: it costs nothing and relaunches us if the
      // app dies mid-trip. The parked region is irrelevant once we are moving.
      if previous == .off, CLLocationManager.significantLocationChangeMonitoringAvailable() {
        manager.startMonitoringSignificantLocationChanges()
      }
      stopRegions()
      parkedCenter = nil
      manager.allowsBackgroundLocationUpdates = true
      manager.showsBackgroundLocationIndicator = true
      // A one-shot request may have lowered this; recording always wants the best fixes.
      manager.desiredAccuracy = kCLLocationAccuracyBest
      // Cancels any pending requestLocation(); its waiters are answered by the first standard update.
      manager.startUpdatingLocation()
      startFlushTimer()
    }
  }

  // MARK: - One-shot position (docs/08 §3 getLastKnownLocation)

  /// The most recent fix CoreLocation holds for this manager, whatever delivered it. Nil until the
  /// first fix after launch; possibly hours old while parked.
  var cachedLocation: CLLocation? {
    return manager.location
  }

  /// One fresh fix through `requestLocation()`, or nil after `timeout` or a CoreLocation failure.
  /// Only meaningful outside `.recording`: a standard update stream cancels (and is cancelled by)
  /// `requestLocation()`, so while a trip runs the latest recorded fix is returned straight away.
  /// The answer arrives in `didUpdateLocations` like any fix; while a request is pending that
  /// callback is consumed here and counts neither as a trigger nor as a parked fix.
  func requestOneShotLocation(timeout: TimeInterval, completion: @escaping (CLLocation?) -> Void) {
    guard mode != .recording else {
      completion(lastFix ?? manager.location)
      return
    }
    oneShotCompletions.append(completion)
    if oneShotCompletions.count > 1 { return }  // one request in flight answers everyone waiting
    oneShotAnchor = manager.location
    // Presence does not need Best; this mirrors Android's PRIORITY_BALANCED_POWER_ACCURACY.
    // `setMode(.recording)` and `resolveOneShot` put Best back.
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    oneShotTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
      guard let self = self else { return }
      // stopUpdatingLocation() is how a pending requestLocation() is cancelled; it must not touch a
      // recording stream, and outside recording there is no stream to stop.
      if self.mode != .recording { self.manager.stopUpdatingLocation() }
      self.resolveOneShot(with: nil)
    }
    manager.requestLocation()
  }

  private var isOneShotPending: Bool {
    return !oneShotCompletions.isEmpty
  }

  private func resolveOneShot(with location: CLLocation?) {
    oneShotTimer?.invalidate()
    oneShotTimer = nil
    guard !oneShotCompletions.isEmpty else { return }
    let completions = oneShotCompletions
    oneShotCompletions.removeAll()
    manager.desiredAccuracy = kCLLocationAccuracyBest
    for completion in completions { completion(location) }
  }

  /// `{t, lat, lon, accuracy, speed?, heading?}`: the shape shared by `getLastKnownLocation` (§3)
  /// and `parkedFix` (§4). Unknown speed / heading (negative) are omitted, never sent as -1.
  static func positionMap(_ location: CLLocation) -> [String: Any] {
    var map: [String: Any] = [
      "t": TrackingClock.ms(location.timestamp),
      "lat": location.coordinate.latitude,
      "lon": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
    ]
    if location.speed >= 0 { map["speed"] = location.speed }
    if location.course >= 0 { map["heading"] = location.course }
    return map
  }

  /// Start collecting batches. Fixes retained during tentative with `t >= since` join the first batch
  /// so the trip's first 20 s (the confirmation window) are not lost.
  func beginBuffering(keepingFixesSince since: Int64) {
    if isBuffering { return }
    isBuffering = true
    buffer = recentFixes.filter { fix in
      guard let t = fix["t"] as? Int64 else { return false }
      return t >= since
    }
    lastBufferedAt = buffer.last.flatMap { $0["t"] as? Int64 }
    recentFixes.removeAll()
    if buffer.count >= LocationTracker.flushBatchSize { flush() }
  }

  func stopBuffering() {
    isBuffering = false
    buffer.removeAll()
    lastBufferedAt = nil
  }

  /// Deliver whatever is buffered right now (called before the `ended` phase event).
  func flushNow() {
    if isBuffering { flush() }
  }

  // MARK: - Internals

  private func stopRecording() {
    // stopUpdatingLocation() also cancels a pending requestLocation(): answer its waiters with
    // whatever CoreLocation has rather than leave them to the timeout.
    if isOneShotPending { resolveOneShot(with: manager.location) }
    manager.stopUpdatingLocation()
    flushTimer?.invalidate()
    flushTimer = nil
    isBuffering = false
    buffer.removeAll()
    lastBufferedAt = nil
    recentFixes.removeAll()
  }

  private func startFlushTimer() {
    flushTimer?.invalidate()
    flushTimer = Timer.scheduledTimer(withTimeInterval: LocationTracker.flushInterval, repeats: true) { [weak self] _ in
      guard let self = self, self.isBuffering else { return }
      self.flush()
    }
  }

  private func flush() {
    let fixes = buffer
    let lastAt = lastBufferedAt
    buffer.removeAll()
    lastBufferedAt = nil
    delegate?.locationTracker(self, didFlush: fixes, lastFixAt: lastAt)
  }

  private func stopRegions() {
    for region in manager.monitoredRegions {
      manager.stopMonitoring(for: region)
    }
  }

  private func rearmRegionIfMoved(_ center: CLLocationCoordinate2D?) {
    guard let center = center, CLLocationCoordinate2DIsValid(center) else {
      if parkedCenter != nil {
        stopRegions()
        parkedCenter = nil
      }
      return
    }
    if let current = parkedCenter,
       current.latitude == center.latitude, current.longitude == center.longitude {
      return
    }
    guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
    stopRegions()
    let region = CLCircularRegion(
      center: center,
      radius: LocationTracker.parkedRegionRadius,
      identifier: LocationTracker.parkedRegionIdentifier)
    region.notifyOnExit = true
    region.notifyOnEntry = false
    manager.startMonitoring(for: region)
    parkedCenter = center
  }

  /// One `fixes[]` entry (docs/08 §4): the shared position map plus the optional extras.
  private func fixMap(_ location: CLLocation) -> [String: Any] {
    var map = LocationTracker.positionMap(location)
    if location.verticalAccuracy > 0 { map["altitude"] = location.altitude }
    if location.speedAccuracy >= 0 { map["speedAccuracy"] = location.speedAccuracy }
    if location.courseAccuracy >= 0 { map["headingAccuracy"] = location.courseAccuracy }
    return map
  }

  // MARK: - CLLocationManagerDelegate

  /// A delivery that arrives while a one-shot is pending is usually just the `requestLocation()`
  /// answer, but it can also be the significant-change callback for a drive that started seconds
  /// after the app was opened. Treat it as movement when the phone is clearly moving or has left
  /// the spot the request was made from; otherwise firing a trigger would start a tentative trip
  /// (and the GPS) on every app open.
  private func looksLikeGenuineMovement(_ location: CLLocation) -> Bool {
    if location.speed >= 4 { return true }
    guard let anchor = oneShotAnchor else { return true }
    return location.distance(from: anchor) > 500
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    var answeredOneShot = false
    if isOneShotPending {
      // The requestLocation() answer, or the first standard update if a trip started meanwhile.
      resolveOneShot(with: locations.last(where: { $0.horizontalAccuracy >= 0 }))
      answeredOneShot = true
    }
    switch mode {
    case .off:
      return
    case .parked:
      // Significant-change delivery while parked: the free position goes out as a parked fix,
      // then one trigger per callback. When the delivery answered a one-shot the position is
      // still free (and still published), but the trigger only fires for genuine movement.
      guard let last = locations.last else { return }
      if last.horizontalAccuracy >= 0 {
        delegate?.locationTracker(self, didObserveParkedFix: last)
      }
      if answeredOneShot && !looksLikeGenuineMovement(last) { return }
      delegate?.locationTracker(self, didFireTrigger: "significantChange", at: TrackingClock.ms(last.timestamp))
    case .recording:
      for location in locations {
        guard location.horizontalAccuracy >= 0 else { continue }  // invalid fix
        lastFix = location
        let map = fixMap(location)
        delegate?.locationTracker(self, didReceiveFix: location)
        // The delegate may have changed the mode (trip ended) or started buffering (trip confirmed).
        guard mode == .recording else { return }
        if isBuffering {
          buffer.append(map)
          lastBufferedAt = TrackingClock.ms(location.timestamp)
          if buffer.count >= LocationTracker.flushBatchSize { flush() }
        } else {
          recentFixes.append(map)
          if recentFixes.count > LocationTracker.tentativeRetention {
            recentFixes.removeFirst(recentFixes.count - LocationTracker.tentativeRetention)
          }
        }
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
    guard mode == .parked, region.identifier == LocationTracker.parkedRegionIdentifier else { return }
    // The fix that tripped the fence is the manager's current location; nothing extra is requested.
    if let fix = manager.location, fix.horizontalAccuracy >= 0 {
      delegate?.locationTracker(self, didObserveParkedFix: fix)
    }
    delegate?.locationTracker(self, didFireTrigger: "geofence", at: TrackingClock.nowMs())
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    delegate?.locationTrackerDidChangeAuthorization(self)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if isOneShotPending, mode != .recording {
      // requestLocation() gave up (kCLErrorLocationUnknown) or was denied: the caller gets nil.
      resolveOneShot(with: nil)
    }
    let nsError = error as NSError
    guard nsError.domain == kCLErrorDomain else { return }
    if nsError.code == CLError.Code.denied.rawValue {
      delegate?.locationTracker(self, didFail: "locationDenied", message: "Location access denied by the user or the system")
    }
    // kCLErrorLocationUnknown and friends are transient; CoreLocation keeps trying.
  }

  func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    delegate?.locationTracker(self, didFail: "regionMonitoringFailed", message: error.localizedDescription)
  }
}
