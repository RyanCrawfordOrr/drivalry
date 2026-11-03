import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var trackingPlugin: TrackingPlugin?
  private let convoyAudio = ConvoyAudioPlugin()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Create the tracking plugin first: when iOS relaunches us in the background for a
    // significant-change or region event (launchOptions[.location]) the CLLocationManager and
    // its delegate must exist before the pending callback is delivered, and a persisted
    // tentative/active trip has to resume whether or not a Flutter engine ever starts.
    let launchedByLocation = launchOptions?[.location] != nil
    let plugin = TrackingPlugin()
    trackingPlugin = plugin
    plugin.start(launchedByLocation: launchedByLocation)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    trackingPlugin?.attach(messenger: engineBridge.applicationRegistrar.messenger())
    convoyAudio.attach(messenger: engineBridge.applicationRegistrar.messenger())
  }
}
