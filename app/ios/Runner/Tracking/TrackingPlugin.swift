import AVFoundation
import CoreLocation
import CoreMotion
import Flutter
import Foundation
import UIKit
import UserNotifications
#if canImport(GoogleMaps)
import GoogleMaps
#endif

/// The iOS half of docs/08-tracking-channel.md.
///
/// Lifecycle:
/// 1. `AppDelegate.application(_:didFinishLaunchingWithOptions:)` creates it and calls `start(launchedByLocation:)`
///    on the main thread, before any Flutter engine exists. This re-arms CoreLocation so a pending
///    significant-change / region event from a background relaunch is delivered to a live delegate,
///    and resumes a persisted tentative/active trip.
/// 2. `AppDelegate.didInitializeImplicitFlutterEngine` calls `attach(messenger:)`, which creates the
///    method and event channels. Events emitted before that (or while no Dart listener exists) are
///    only spooled; Dart replays them with `drainSpool`.
///
/// Everything in this class runs on the main thread: platform-channel calls, CoreLocation and
/// CoreMotion activity callbacks, notifications and timers all arrive there. Device-motion samples
/// are reduced on a background queue inside `MotionTracker` and only drained here.
final class TrackingPlugin: NSObject, FlutterStreamHandler {
  static let methodChannelName = "app.drivalry/tracking"
  static let eventChannelName = "app.drivalry/tracking/events"
  static let tickInterval: TimeInterval = 10

  private enum Key {
    static let enabled = "settings.enabled"
    static let pausedUntil = "settings.pausedUntil"
    static let lastEndLatitude = "trip.lastEndLat"
    static let lastEndLongitude = "trip.lastEndLon"
  }

  private let store: TrackingStore
  private let spool = Spool()
  private let diagnostics: TrackingDiagnostics
  private let stateMachine: TripStateMachine
  private let location = LocationTracker()
  private let motion = MotionTracker()
  private let phone = PhoneEvents()

  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private var eventSink: FlutterEventSink?
  private var tickTimer: Timer?
  private var started = false

  /// The trip id events are stamped with. Unlike `stateMachine.tripId` it survives until the
  /// `ended`/`discarded` event has been written, so the final `fixes` flush still carries it.
  private var currentTripId: String?
  private var lastFixAt: Int64?
  /// Hints seen while tentative; released just before the `active` phase event, dropped on discard.
  private var pendingHints: [[String: Any]] = []
  private var providedMapsKey: String?
  private var promptWaiter: PromptWaiter?

  override init() {
    let store = TrackingStore()
    self.store = store
    diagnostics = TrackingDiagnostics(store: store)
    stateMachine = TripStateMachine(store: store)
    super.init()
    stateMachine.delegate = self
    location.delegate = self
    motion.delegate = self
    phone.delegate = self
  }

  // MARK: - Lifecycle

  /// Main thread, from `didFinishLaunchingWithOptions`.
  /// `launchedByLocation` is true when iOS relaunched us for a significant-change or region event;
  /// the pending callback arrives as soon as `applyMode()` restarts the services below.
  func start(launchedByLocation: Bool) {
    guard !started else { return }
    started = true
    phone.start()
    if stateMachine.phase != .idle {
      currentTripId = stateMachine.tripId
    }
    applyMode()
    if stateMachine.phase == .active {
      // Relaunched or resumed mid-trip: the car may have stopped long ago.
      stateMachine.tick(now: TrackingClock.nowMs())
    }
  }

  /// Main thread, once the implicit Flutter engine exists. Safe to call again for a new engine.
  func attach(messenger: FlutterBinaryMessenger) {
    methodChannel?.setMethodCallHandler(nil)
    eventChannel?.setStreamHandler(nil)
    eventSink = nil

    let method = FlutterMethodChannel(name: TrackingPlugin.methodChannelName, binaryMessenger: messenger)
    method.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Tracking plugin was released", details: nil))
        return
      }
      self.handle(call, result: result)
    }
    let events = FlutterEventChannel(name: TrackingPlugin.eventChannelName, binaryMessenger: messenger)
    events.setStreamHandler(self)
    methodChannel = method
    eventChannel = events
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Method channel (docs/08 §3)

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "getState":
      replyState(result)

    case "setEnabled":
      guard let enabled = (args?["enabled"] as? NSNumber)?.boolValue else {
        result(badArguments(call, expected: "{enabled: bool}"))
        return
      }
      setEnabled(enabled)
      replyState(result)

    case "pauseUntil":
      guard let untilMs = (args?["untilMs"] as? NSNumber)?.int64Value else {
        result(badArguments(call, expected: "{untilMs: int}"))
        return
      }
      store.set(max(Int64(0), untilMs), forKey: Key.pausedUntil)
      replyState(result)

    case "requestPermissions":
      requestPermissions { [weak self] in
        guard let self = self else {
          result(nil)
          return
        }
        self.permissions { map in result(map) }
      }

    case "openSettings":
      openSettings()
      result(nil)

    case "forceStartTrip":
      let now = TrackingClock.nowMs()
      diagnostics.recordTrigger(kind: "manual", at: now)
      stateMachine.forceStart(at: now)
      replyState(result)

    case "forceEndTrip":
      stateMachine.forceEnd(at: TrackingClock.nowMs())
      replyState(result)

    case "drainSpool":
      spool.drain { events in result(events) }

    case "setMapsApiKey":
      guard let key = args?["key"] as? String, !key.isEmpty else {
        result(badArguments(call, expected: "{key: String}"))
        return
      }
      if provideMapsApiKey(key) {
        result(nil)
      } else {
        result(FlutterError(code: "unavailable", message: "The GoogleMaps SDK is not linked into Runner", details: nil))
      }

    case "getDiagnostics":
      result(diagnostics.map(serviceRunning: location.mode == .recording))

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func badArguments(_ call: FlutterMethodCall, expected: String) -> FlutterError {
    return FlutterError(code: "badArguments", message: "\(call.method) expects \(expected)", details: nil)
  }

  private func openSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url, options: [:], completionHandler: nil)
  }

  private func provideMapsApiKey(_ key: String) -> Bool {
    if providedMapsKey == key { return true }  // idempotent across hot restarts
    #if canImport(GoogleMaps)
    _ = GMSServices.provideAPIKey(key)
    providedMapsKey = key
    return true
    #else
    return false
    #endif
  }

  // MARK: - State (docs/08 §3.1)

  private var isEnabled: Bool {
    return store.bool(Key.enabled, default: true)
  }

  private func setEnabled(_ enabled: Bool) {
    store.set(enabled, forKey: Key.enabled)
    if !enabled {
      // Ends the trip (or discards the tentative one) through the state-machine delegate.
      stateMachine.forceEnd(at: TrackingClock.nowMs())
    }
    applyMode()
  }

  /// `pausedUntil`, normalised to 0 once it has passed.
  private func pausedUntil(now: Int64) -> Int64 {
    let until = store.int64(Key.pausedUntil) ?? 0
    if until != 0 && until <= now {
      store.set(Int64(0), forKey: Key.pausedUntil)
      return 0
    }
    return until
  }

  private func isPaused(now: Int64) -> Bool {
    return pausedUntil(now: now) > now
  }

  private func replyState(_ result: @escaping FlutterResult) {
    permissions { [weak self] permissions in
      guard let self = self else {
        result(nil)
        return
      }
      result(self.stateMap(permissions: permissions))
    }
  }

  private func stateMap(permissions: [String: Any]) -> [String: Any] {
    let now = TrackingClock.nowMs()
    let startedAt: Int64? = stateMachine.phase == .active ? stateMachine.startedAt : nil
    return [
      "phase": stateMachine.phase.rawValue,
      "tripId": orNull(stateMachine.tripId),
      "tripStartedAt": orNull(startedAt),
      "enabled": isEnabled,
      "pausedUntil": pausedUntil(now: now),
      "permissions": permissions,
      "spooledEvents": spool.count,
    ]
  }

  // MARK: - Permissions (docs/08 §3.2)

  private func permissions(completion: @escaping ([String: Any]) -> Void) {
    let locationValue: String
    switch location.authorizationStatus {
    case .authorizedAlways: locationValue = "always"
    case .authorizedWhenInUse: locationValue = "whileInUse"
    default: locationValue = "denied"
    }
    let precise = location.isPreciseLocation
    let motionValue: String
    switch MotionTracker.authorizationStatus {
    case .authorized: motionValue = "granted"
    case .denied, .restricted: motionValue = "denied"
    case .notDetermined: motionValue = "notDetermined"
    @unknown default: motionValue = "notDetermined"
    }
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let notificationsValue: String
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral: notificationsValue = "granted"
      case .denied: notificationsValue = "denied"
      case .notDetermined: notificationsValue = "notDetermined"
      @unknown default: notificationsValue = "notDetermined"
      }
      DispatchQueue.main.async {
        completion([
          "location": locationValue,
          "preciseLocation": precise,
          "motion": motionValue,
          "notifications": notificationsValue,
          "bluetooth": "granted",  // iOS needs no permission to observe audio routes
        ])
      }
    }
  }

  /// When-in-use → Always → Motion & Fitness → notifications, each waiting for its prompt to close.
  private func requestPermissions(completion: @escaping () -> Void) {
    requestLocationPermission { [weak self] in
      guard let self = self else {
        completion()
        return
      }
      self.requestMotionPermission { [weak self] in
        guard let self = self else {
          completion()
          return
        }
        self.requestNotificationPermission {
          self.applyMode()
          completion()
        }
      }
    }
  }

  private func requestLocationPermission(completion: @escaping () -> Void) {
    switch location.authorizationStatus {
    case .notDetermined:
      awaitPrompt(noPromptTimeout: 3, safetyTimeout: 300) { [weak self] in
        guard let self = self else {
          completion()
          return
        }
        self.requestAlwaysUpgrade(completion: completion)
      }
      location.requestWhenInUseAuthorization()
    case .authorizedWhenInUse:
      requestAlwaysUpgrade(completion: completion)
    default:
      completion()
    }
  }

  private func requestAlwaysUpgrade(completion: @escaping () -> Void) {
    guard location.authorizationStatus == .authorizedWhenInUse else {
      completion()
      return
    }
    // iOS shows the "Change to Always Allow" prompt at most once per install. When it has already
    // been answered, this call does nothing and no delegate callback follows: the waiter's short
    // timeout covers that, while a visible prompt is detected through resign/become-active.
    awaitPrompt(noPromptTimeout: 2, safetyTimeout: 300, completion: completion)
    location.requestAlwaysAuthorization()
  }

  private func requestMotionPermission(completion: @escaping () -> Void) {
    guard MotionTracker.isActivityAvailable, MotionTracker.authorizationStatus == .notDetermined else {
      completion()
      return
    }
    // Starting activity updates is what shows the Motion & Fitness prompt; poll the status until the
    // user answers, then stop the updates again (applyMode decides whether they stay on).
    motion.startActivityUpdates()
    let deadline = Date().addingTimeInterval(300)
    _ = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
      guard let self = self else {
        timer.invalidate()
        completion()
        return
      }
      if MotionTracker.authorizationStatus != .notDetermined || Date() > deadline {
        timer.invalidate()
        self.motion.stopActivityUpdates()
        completion()
      }
    }
  }

  private func requestNotificationPermission(completion: @escaping () -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      guard settings.authorizationStatus == .notDetermined else {
        DispatchQueue.main.async { completion() }
        return
      }
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
        DispatchQueue.main.async { completion() }
      }
    }
  }

  private func awaitPrompt(noPromptTimeout: TimeInterval, safetyTimeout: TimeInterval, completion: @escaping () -> Void) {
    promptWaiter?.finish()
    promptWaiter = PromptWaiter(noPromptTimeout: noPromptTimeout, safetyTimeout: safetyTimeout) { [weak self] in
      self?.promptWaiter = nil
      completion()
    }
  }

  // MARK: - Modes

  /// Make the OS services match the persisted settings and trip phase. Idempotent.
  private func applyMode() {
    let locationAuthorized = location.isAuthorized
    let motionAuthorized = MotionTracker.authorizationStatus == .authorized

    guard isEnabled else {
      location.setMode(.off, parkedAt: nil)
      motion.stopDeviceMotion()
      motion.stopActivityUpdates()
      stopTick()
      return
    }

    switch stateMachine.phase {
    case .idle:
      motion.stopDeviceMotion()
      location.stopBuffering()
      location.setMode(locationAuthorized ? .parked : .off, parkedAt: lastEndCoordinate())
      if motionAuthorized { motion.startActivityUpdates() } else { motion.stopActivityUpdates() }
      stopTick()
    case .tentative:
      motion.stopDeviceMotion()
      location.stopBuffering()
      location.setMode(locationAuthorized ? .recording : .off, parkedAt: nil)
      if motionAuthorized { motion.startActivityUpdates() }
      startTick()
    case .active:
      location.setMode(locationAuthorized ? .recording : .off, parkedAt: nil)
      if let startedAt = stateMachine.startedAt {
        location.beginBuffering(keepingFixesSince: startedAt)
      }
      if motionAuthorized { motion.startActivityUpdates() }
      motion.startDeviceMotion()
      startTick()
    }
  }

  private func startTick() {
    if tickTimer != nil { return }
    tickTimer = Timer.scheduledTimer(withTimeInterval: TrackingPlugin.tickInterval, repeats: true) { [weak self] _ in
      self?.stateMachine.tick(now: TrackingClock.nowMs())
    }
  }

  private func stopTick() {
    tickTimer?.invalidate()
    tickTimer = nil
  }

  private func lastEndCoordinate() -> CLLocationCoordinate2D? {
    guard let lat = store.double(Key.lastEndLatitude), let lon = store.double(Key.lastEndLongitude) else { return nil }
    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
  }

  private func saveLastEnd(_ fix: CLLocation?) {
    guard let fix = fix else { return }
    store.set(fix.coordinate.latitude, forKey: Key.lastEndLatitude)
    store.set(fix.coordinate.longitude, forKey: Key.lastEndLongitude)
  }

  // MARK: - Triggers and events

  private func handleTrigger(kind: String, at t: Int64) {
    guard isEnabled, stateMachine.phase == .idle else { return }
    diagnostics.recordTrigger(kind: kind, at: t)
    guard location.isAuthorized, !isPaused(now: TrackingClock.nowMs()) else { return }
    stateMachine.trigger(kind: kind, at: t)
  }

  /// Spool first (always), then the live stream when Dart is listening.
  private func emit(_ event: [String: Any]) {
    spool.append(event)
    guard let sink = eventSink else { return }
    DispatchQueue.main.async { sink(event) }
  }

  private func emitError(code: String, message: String) {
    emit([
      "type": "error",
      "tripId": NSNull(),
      "t": TrackingClock.nowMs(),
      "code": code,
      "message": message,
    ])
  }

  private func hintEvent(tripId: String, route: PhoneEvents.CarRoute, at t: Int64) -> [String: Any] {
    return [
      "type": "hint",
      "tripId": tripId,
      "t": t,
      "kind": route.kind,
      "name": orNull(route.name),
    ]
  }

  private func phoneEvent(tripId: String, kind: String, at t: Int64) -> [String: Any] {
    return ["type": "phone", "tripId": tripId, "t": t, "kind": kind]
  }
}

// MARK: - TripStateMachineDelegate

extension TrackingPlugin: TripStateMachineDelegate {
  func tripStateMachine(_ machine: TripStateMachine, didStartTentative tripId: String, reason: String, at t: Int64) {
    diagnostics.recordTentativeStart()
    currentTripId = tripId
    lastFixAt = nil
    pendingHints.removeAll()
    applyMode()
    emit(["type": "phase", "tripId": tripId, "t": t, "phase": "tentative", "reason": reason])
  }

  func tripStateMachine(_ machine: TripStateMachine, didActivate tripId: String, reason: String, startedAt: Int64, at t: Int64) {
    diagnostics.recordConfirmedTrip()
    currentTripId = tripId
    // Hints collected while tentative, in time order, ahead of the active event.
    if pendingHints.isEmpty, let route = phone.carRoute {
      pendingHints.append(hintEvent(tripId: tripId, route: route, at: t))
    }
    for hint in pendingHints { emit(hint) }
    pendingHints.removeAll()
    emit([
      "type": "phase",
      "tripId": tripId,
      "t": t,
      "phase": "active",
      "reason": reason,
      "startedAt": startedAt,
    ])
    // Baseline phone state Dart cannot otherwise learn for this trip.
    if phone.hasActiveCall { emit(phoneEvent(tripId: tripId, kind: "callStart", at: t)) }
    if phone.isProjecting { emit(phoneEvent(tripId: tripId, kind: "projectionOn", at: t)) }
    // Last: starts buffering (which may flush the retained confirmation-window fixes as the
    // first `fixes` batch) and the 20 Hz motion stream, after the active event is on record.
    applyMode()
  }

  func tripStateMachine(_ machine: TripStateMachine, didEnd tripId: String, reason: String, at t: Int64) {
    diagnostics.recordTripEnd(reason: reason, at: t)
    // Last fixes and motion peaks first, so they precede the ended event in the stream.
    location.flushNow()
    emit(["type": "phase", "tripId": tripId, "t": t, "phase": "ended", "reason": reason])
    saveLastEnd(location.lastFix)
    currentTripId = nil
    lastFixAt = nil
    pendingHints.removeAll()
    applyMode()
  }

  func tripStateMachine(_ machine: TripStateMachine, didDiscard tripId: String, at t: Int64) {
    diagnostics.recordDiscardedTentative()
    emit(["type": "phase", "tripId": tripId, "t": t, "phase": "discarded", "reason": "unconfirmed"])
    currentTripId = nil
    lastFixAt = nil
    pendingHints.removeAll()
    applyMode()
  }
}

// MARK: - LocationTrackerDelegate

extension TrackingPlugin: LocationTrackerDelegate {
  func locationTracker(_ tracker: LocationTracker, didReceiveFix location: CLLocation) {
    let t = TrackingClock.ms(location.timestamp)
    lastFixAt = t
    let speed: Double? = location.speed >= 0 ? location.speed : nil
    stateMachine.fix(t: t, speed: speed)
  }

  func locationTracker(_ tracker: LocationTracker, didFlush fixes: [[String: Any]], lastFixAt batchT: Int64?) {
    guard let tripId = currentTripId else { return }
    if !fixes.isEmpty {
      emit([
        "type": "fixes",
        "tripId": tripId,
        "t": batchT ?? TrackingClock.nowMs(),
        "fixes": fixes,
      ])
    }
    let peaks = motion.drainPeaks()
    if !peaks.isEmpty {
      let lastPeakAt = (peaks.last?["t"] as? Int64) ?? TrackingClock.nowMs()
      emit(["type": "motion", "tripId": tripId, "t": lastPeakAt, "events": peaks])
    }
  }

  func locationTracker(_ tracker: LocationTracker, didFireTrigger kind: String, at t: Int64) {
    handleTrigger(kind: kind, at: t)
  }

  func locationTrackerDidChangeAuthorization(_ tracker: LocationTracker) {
    promptWaiter?.finish()
    if stateMachine.phase != .idle, !tracker.isAuthorized {
      emitError(code: "locationPermissionLost", message: "Location permission was revoked during a trip")
    }
    applyMode()
  }

  func locationTracker(_ tracker: LocationTracker, didFail code: String, message: String) {
    emitError(code: code, message: message)
  }
}

// MARK: - MotionTrackerDelegate

extension TrackingPlugin: MotionTrackerDelegate {
  func motionTracker(_ tracker: MotionTracker, didDetectAutomotiveAt t: Int64) {
    handleTrigger(kind: "activity", at: t)
  }

  func motionTracker(_ tracker: MotionTracker, didDetectExitAt t: Int64) {
    // Never end a trip before its last recorded fix.
    let endAt = max(t, lastFixAt ?? t)
    stateMachine.automotiveExit(carAudioConnected: phone.carAudioConnected, at: endAt)
  }

  func motionTracker(_ tracker: MotionTracker, didFail code: String, message: String) {
    emitError(code: code, message: message)
  }
}

// MARK: - PhoneEventsDelegate

extension TrackingPlugin: PhoneEventsDelegate {
  func phoneEvents(_ source: PhoneEvents, didObserve kind: String, at t: Int64) {
    guard stateMachine.phase == .active, let tripId = currentTripId else { return }
    emit(phoneEvent(tripId: tripId, kind: kind, at: t))
    if kind == "foreground" {
      // The only "the driver touched the phone" signal iOS gives us (docs/08 §4).
      emit(phoneEvent(tripId: tripId, kind: "interaction", at: t))
    }
  }

  func phoneEvents(_ source: PhoneEvents, didConnectCarAudio route: PhoneEvents.CarRoute, at t: Int64) {
    switch stateMachine.phase {
    case .idle:
      handleTrigger(kind: "bluetooth", at: t)
      if stateMachine.phase == .tentative, let tripId = currentTripId {
        pendingHints.append(hintEvent(tripId: tripId, route: route, at: t))
      }
    case .tentative:
      if let tripId = currentTripId {
        pendingHints.append(hintEvent(tripId: tripId, route: route, at: t))
      }
    case .active:
      if let tripId = currentTripId {
        emit(hintEvent(tripId: tripId, route: route, at: t))
      }
    }
  }

  func phoneEvents(_ source: PhoneEvents, didDisconnectCarAudioAt t: Int64) {
    // Nothing to emit: the exit rule reads `phone.carAudioConnected` live.
  }
}

// MARK: - PromptWaiter

/// Resolves once a system permission alert has been dismissed, detected through the app resigning
/// and regaining active state. If no alert appears within `noPromptTimeout` (the question was
/// already answered), or `safetyTimeout` passes, it resolves anyway. Main thread only.
private final class PromptWaiter {
  private var finished = false
  private var sawResignActive = false
  private var observers: [NSObjectProtocol] = []
  private var timers: [Timer] = []
  private let completion: () -> Void

  init(noPromptTimeout: TimeInterval, safetyTimeout: TimeInterval, completion: @escaping () -> Void) {
    self.completion = completion
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.sawResignActive = true
    })
    observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self = self, self.sawResignActive else { return }
      // Give CoreLocation a moment to deliver the authorization callback first.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.finish() }
    })
    timers.append(Timer.scheduledTimer(withTimeInterval: noPromptTimeout, repeats: false) { [weak self] _ in
      guard let self = self, !self.sawResignActive else { return }
      self.finish()
    })
    timers.append(Timer.scheduledTimer(withTimeInterval: safetyTimeout, repeats: false) { [weak self] _ in
      self?.finish()
    })
  }

  func finish() {
    guard !finished else { return }
    finished = true
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    for timer in timers { timer.invalidate() }
    timers.removeAll()
    completion()
  }
}
