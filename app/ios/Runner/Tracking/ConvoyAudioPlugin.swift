import AVFoundation
import Flutter
import Foundation

/// `app.drivalry/convoy_audio`: the iOS half of the convoy audio session
/// (docs/10 §4). Methods: `start`, `stop`, `duck {on}`, `setSpeaker {on}`.
/// WebRTC itself runs in the Flutter engine; this only configures the shared
/// `AVAudioSession` so push-to-talk audio goes out over the car's Bluetooth or
/// CarPlay route and ducks music instead of stopping it.
final class ConvoyAudioPlugin: NSObject {
  static let channelName = "app.drivalry/convoy_audio"

  private var channel: FlutterMethodChannel?
  private var running = false

  func attach(messenger: FlutterBinaryMessenger) {
    channel?.setMethodCallHandler(nil)
    let ch = FlutterMethodChannel(name: ConvoyAudioPlugin.channelName, binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    channel = ch
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "start":
      start(result: result)
    case "stop":
      stop(result: result)
    case "duck":
      // `.duckOthers` is part of the session options, so ducking happens
      // whenever our session is active; nothing extra to do per press.
      _ = args?["on"] as? Bool
      result(nil)
    case "setSpeaker":
      setSpeaker(on: args?["on"] as? Bool ?? false, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(result: FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers]
      )
      try session.setActive(true)
      running = true
      result(nil)
    } catch {
      result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
    }
  }

  private func stop(result: FlutterResult) {
    guard running else {
      result(nil)
      return
    }
    running = false
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setActive(false, options: .notifyOthersOnDeactivation)
      result(nil)
    } catch {
      // Deactivation can fail while another app holds the session; not fatal.
      result(nil)
    }
  }

  private func setSpeaker(on: Bool, result: FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.overrideOutputAudioPort(on ? .speaker : .none)
      result(nil)
    } catch {
      result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
    }
  }
}
