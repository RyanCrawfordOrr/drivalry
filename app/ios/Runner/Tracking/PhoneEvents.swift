import AVFoundation
import CallKit
import Foundation
import UIKit

protocol PhoneEventsDelegate: AnyObject {
  /// A `phone` event kind: callStart, callEnd, foreground, background, projectionOn, projectionOff.
  func phoneEvents(_ source: PhoneEvents, didObserve kind: String, at t: Int64)
  /// A car audio output appeared or changed. `kind` is "bluetooth" or "carplay" (docs/08 §4 `hint`).
  func phoneEvents(_ source: PhoneEvents, didConnectCarAudio route: PhoneEvents.CarRoute, at t: Int64)
  func phoneEvents(_ source: PhoneEvents, didDisconnectCarAudioAt t: Int64)
}

/// Phone-usage signals iOS exposes without private APIs (docs/08 §4 and §6).
///
/// - `CXCallObserver`: a call connected / ended.
/// - `UIApplication` active/background notifications: our own app in the foreground (on iOS this
///   is the only "interaction" signal there is).
/// - `AVAudioSession` route changes: Bluetooth or CarPlay audio output, used both as a passenger /
///   vehicle hint and as the "still in the car" guard for the automotive-exit end rule.
/// - `UIScreen` connect/disconnect with the CarPlay idiom: projection on/off. Without the CarPlay
///   entitlement iOS never attaches that screen to us, so this stays silent; it needs no entitlement to compile.
///
/// Main-thread confined; every callback is delivered on the main queue.
final class PhoneEvents: NSObject, CXCallObserverDelegate {
  struct CarRoute: Equatable {
    let kind: String  // "bluetooth" | "carplay"
    let name: String?
  }

  weak var delegate: PhoneEventsDelegate?

  private let callObserver = CXCallObserver()
  private var connectedCalls = Set<UUID>()
  private var observers: [NSObjectProtocol] = []
  private var started = false

  private(set) var carRoute: CarRoute?
  private(set) var isProjecting = false
  private(set) var isForeground = false

  var carAudioConnected: Bool {
    return carRoute != nil
  }

  var hasActiveCall: Bool {
    return !connectedCalls.isEmpty
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func start() {
    guard !started else { return }
    started = true

    isForeground = UIApplication.shared.applicationState == .active
    carRoute = PhoneEvents.currentCarRoute()
    isProjecting = UIScreen.screens.contains { $0.traitCollection.userInterfaceIdiom == .carPlay }

    for call in callObserver.calls where call.hasConnected && !call.hasEnded {
      connectedCalls.insert(call.uuid)
    }
    callObserver.setDelegate(self, queue: nil)  // nil → main queue

    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self = self else { return }
      self.isForeground = true
      self.delegate?.phoneEvents(self, didObserve: "foreground", at: TrackingClock.nowMs())
    })
    observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self = self else { return }
      self.isForeground = false
      self.delegate?.phoneEvents(self, didObserve: "background", at: TrackingClock.nowMs())
    })
    observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.evaluateRoute()
    })
    observers.append(center.addObserver(forName: UIScreen.didConnectNotification, object: nil, queue: .main) { [weak self] note in
      guard let self = self, PhoneEvents.isCarPlayScreen(note.object), !self.isProjecting else { return }
      self.isProjecting = true
      self.delegate?.phoneEvents(self, didObserve: "projectionOn", at: TrackingClock.nowMs())
    })
    observers.append(center.addObserver(forName: UIScreen.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
      guard let self = self, PhoneEvents.isCarPlayScreen(note.object), self.isProjecting else { return }
      self.isProjecting = false
      self.delegate?.phoneEvents(self, didObserve: "projectionOff", at: TrackingClock.nowMs())
    })
  }

  // MARK: - Audio route

  private static func isCarPlayScreen(_ object: Any?) -> Bool {
    guard let screen = object as? UIScreen else { return false }
    return screen.traitCollection.userInterfaceIdiom == .carPlay
  }

  /// The first car-like output of the current route, if any.
  static func currentCarRoute() -> CarRoute? {
    for output in AVAudioSession.sharedInstance().currentRoute.outputs {
      switch output.portType {
      case .carAudio:
        return CarRoute(kind: "carplay", name: output.portName)
      case .bluetoothA2DP, .bluetoothHFP:
        return CarRoute(kind: "bluetooth", name: output.portName)
      default:
        continue
      }
    }
    return nil
  }

  private func evaluateRoute() {
    let now = TrackingClock.nowMs()
    let route = PhoneEvents.currentCarRoute()
    if let route = route {
      if route != carRoute {
        carRoute = route
        delegate?.phoneEvents(self, didConnectCarAudio: route, at: now)
      }
    } else if carRoute != nil {
      carRoute = nil
      delegate?.phoneEvents(self, didDisconnectCarAudioAt: now)
    }
  }

  // MARK: - CXCallObserverDelegate

  func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
    let now = TrackingClock.nowMs()
    if call.hasEnded {
      if connectedCalls.remove(call.uuid) != nil {
        delegate?.phoneEvents(self, didObserve: "callEnd", at: now)
      }
    } else if call.hasConnected, !connectedCalls.contains(call.uuid) {
      connectedCalls.insert(call.uuid)
      delegate?.phoneEvents(self, didObserve: "callStart", at: now)
    }
  }
}
