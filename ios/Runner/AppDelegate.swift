import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let folders = FolderAccess()
  private let route = AudioRoute()
  private var downloadTask = UIBackgroundTaskIdentifier.invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Lets flutter_local_notifications show and answer download notifications.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "FolderAccess")?.messenger() {
      folders.register(with: messenger)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioRoute") {
      route.register(with: registrar)
    }
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "DownloadsBackground")?.messenger() {
      // Downloads ask for extra running time while the app is in the background. iOS grants about
      // 30 seconds unless audio is playing (the audio background mode keeps the app alive then).
      FlutterMethodChannel(name: "riflay/downloads", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return result(nil) }
        switch call.method {
        case "start":
          if self.downloadTask == .invalid {
            self.downloadTask = UIApplication.shared.beginBackgroundTask(withName: "riflay-downloads") { [weak self] in
              guard let self = self else { return }
              UIApplication.shared.endBackgroundTask(self.downloadTask)
              self.downloadTask = .invalid
            }
          }
          result(nil)
        case "stop":
          if self.downloadTask != .invalid {
            UIApplication.shared.endBackgroundTask(self.downloadTask)
            self.downloadTask = .invalid
          }
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
