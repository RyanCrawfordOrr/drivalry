import Flutter
import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// `app.drivalry/live_activity`: starts, updates and ends the drive Live
/// Activity (docs/04 §2). Methods:
///
/// - `isSupported` → Bool (iOS 16.2+, the user has Live Activities enabled)
/// - `start {state, startedAt?}` → String activity id
/// - `update {state}` → null
/// - `end {state?}` → null (dismisses with the system default policy)
/// - `endAll` → null
///
/// One activity at a time: `start` while one is running updates it instead.
/// `state` is the dictionary described in `DriveActivityAttributes.ContentState`
/// with `updatedAt` as epoch milliseconds. Every reply happens on the main
/// thread. On devices below iOS 16.2 every method answers as if Live Activities
/// were simply unavailable: `isSupported` → false, the rest → null.
final class LiveActivityPlugin: NSObject {
  static let channelName = "app.drivalry/live_activity"

  private var channel: FlutterMethodChannel?

  func attach(messenger: FlutterBinaryMessenger) {
    channel?.setMethodCallHandler(nil)
    let ch = FlutterMethodChannel(name: LiveActivityPlugin.channelName, binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    channel = ch
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    #if canImport(ActivityKit)
    if #available(iOS 16.2, *) {
      switch call.method {
      case "isSupported":
        result(ActivityAuthorizationInfo().areActivitiesEnabled)
      case "start":
        LiveActivityController.shared.start(args: args, result: result)
      case "update":
        LiveActivityController.shared.update(args: args, result: result)
      case "end":
        LiveActivityController.shared.end(args: args, result: result)
      case "endAll":
        LiveActivityController.shared.endAll(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
      return
    }
    #endif
    switch call.method {
    case "isSupported":
      result(false)
    case "start", "update", "end", "endAll":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

#if canImport(ActivityKit)
/// Owns the single running activity. All ActivityKit calls are async; replies
/// are hopped back to the main thread.
@available(iOS 16.2, *)
final class LiveActivityController {
  static let shared = LiveActivityController()

  private var activity: Activity<DriveActivityAttributes>?

  private init() {}

  func start(args: [String: Any], result: @escaping FlutterResult) {
    guard let stateDict = args["state"] as? [String: Any],
          let state = LiveActivityCodec.state(from: stateDict) else {
      reply(result, FlutterError(code: "args", message: "start needs a state map", details: nil))
      return
    }
    // Adopt an activity that survived an app relaunch rather than stacking;
    // one that has ended (still on the lock screen under the default
    // dismissal) is not adopted, or the new trip would never show.
    if activity == nil {
      activity = Activity<DriveActivityAttributes>.activities.first(where: { $0.activityState == .active })
    }
    if let running = activity {
      Task {
        await running.update(LiveActivityCodec.content(state))
        self.reply(result, running.id)
      }
      return
    }
    let startedAt = LiveActivityCodec.date(args["startedAt"])
    do {
      let created = try Activity<DriveActivityAttributes>.request(
        attributes: DriveActivityAttributes(startedAt: startedAt),
        content: LiveActivityCodec.content(state),
        pushType: nil
      )
      activity = created
      reply(result, created.id)
    } catch {
      reply(result, FlutterError(code: "activity", message: error.localizedDescription, details: nil))
    }
  }

  func update(args: [String: Any], result: @escaping FlutterResult) {
    guard let stateDict = args["state"] as? [String: Any],
          let state = LiveActivityCodec.state(from: stateDict) else {
      reply(result, FlutterError(code: "args", message: "update needs a state map", details: nil))
      return
    }
    guard let running = activity ?? Activity<DriveActivityAttributes>.activities.first(where: { $0.activityState == .active }) else {
      reply(result, nil)
      return
    }
    activity = running
    Task {
      await running.update(LiveActivityCodec.content(state))
      self.reply(result, nil)
    }
  }

  func end(args: [String: Any], result: @escaping FlutterResult) {
    guard let running = activity ?? Activity<DriveActivityAttributes>.activities.first(where: { $0.activityState == .active }) else {
      reply(result, nil)
      return
    }
    activity = nil
    let finalState = (args["state"] as? [String: Any]).flatMap(LiveActivityCodec.state(from:))
    Task {
      if let finalState = finalState {
        await running.end(LiveActivityCodec.content(finalState), dismissalPolicy: .default)
      } else {
        await running.end(nil, dismissalPolicy: .default)
      }
      self.reply(result, nil)
    }
  }

  func endAll(result: @escaping FlutterResult) {
    activity = nil
    let all = Activity<DriveActivityAttributes>.activities
    Task {
      for a in all {
        await a.end(nil, dismissalPolicy: .immediate)
      }
      self.reply(result, nil)
    }
  }

  private func reply(_ result: @escaping FlutterResult, _ value: Any?) {
    if Thread.isMainThread {
      result(value)
    } else {
      DispatchQueue.main.async { result(value) }
    }
  }
}

/// Dictionary ↔ ContentState. Numbers may arrive as Int, Int64 or Double
/// depending on how Dart produced them.
@available(iOS 16.2, *)
enum LiveActivityCodec {
  static func state(from d: [String: Any]) -> DriveActivityAttributes.ContentState? {
    guard let unit = d["limitUnit"] as? String else { return nil }
    return DriveActivityAttributes.ContentState(
      limitPosted: int(d["limitPosted"]),
      limitUnit: unit,
      speedPosted: int(d["speedPosted"]),
      cleanSoFar: d["cleanSoFar"] as? Bool ?? false,
      overBy: int(d["overBy"]),
      roadName: d["roadName"] as? String,
      tripMinutes: int(d["tripMinutes"]) ?? 0,
      recording: (d["recording"] as? Bool) ?? ((int(d["tripMinutes"]) ?? 0) > 0),
      convoyName: d["convoyName"] as? String,
      gapMinutes: int(d["gapMinutes"]),
      etaMinutes: int(d["etaMinutes"]),
      talking: d["talking"] as? String,
      updatedAt: date(d["updatedAt"]) ?? Date()
    )
  }

  /// The system treats the state as stale (dims it) a minute after the phone
  /// last reported; the Dart side updates at most every 5 s while driving.
  static func content(_ state: DriveActivityAttributes.ContentState)
    -> ActivityContent<DriveActivityAttributes.ContentState>
  {
    ActivityContent(state: state, staleDate: Date().addingTimeInterval(60))
  }

  static func int(_ v: Any?) -> Int? {
    switch v {
    case let i as Int: return i
    case let i as Int64: return Int(i)
    case let d as Double: return Int(d.rounded())
    case let n as NSNumber: return n.intValue
    default: return nil
    }
  }

  /// Epoch milliseconds → Date.
  static func date(_ v: Any?) -> Date? {
    guard let ms = int(v) else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
  }
}
#endif
