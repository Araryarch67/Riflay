import AVFoundation
import AVKit
import Flutter
import UIKit

/// The audio route on iOS: which output the sound goes to (speaker, Bluetooth, AirPlay, a USB DAC),
/// the system route picker, and the sample rate the session runs at.
///
/// Channel `riflay/route`:
///  - `current` -> {name, rate, channels}: the route now, and the rate the hardware really runs at
///  - `setPreferredRate(rate)`: asks iOS to run the output at the song's rate (it may refuse)
/// and it calls `changed` on Dart when the route changes (a DAC plugged in, Bluetooth gone).
/// The platform view `riflay/route-picker` is Apple's AVRoutePickerView.
final class AudioRoute: NSObject {
  private var channel: FlutterMethodChannel?

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "riflay/route", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "current":
        result(self?.current())
      case "setPreferredRate":
        let rate = (call.arguments as? Double) ?? 0
        try? AVAudioSession.sharedInstance().setPreferredSampleRate(rate)
        result(self?.current())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    registrar.register(RoutePickerFactory(), withId: "riflay/route-picker")
    NotificationCenter.default.addObserver(
      self, selector: #selector(routeChanged), name: AVAudioSession.routeChangeNotification, object: nil)
  }

  @objc private func routeChanged() {
    DispatchQueue.main.async { [weak self] in
      self?.channel?.invokeMethod("changed", arguments: self?.current())
    }
  }

  private func current() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let output = session.currentRoute.outputs.first
    return [
      "name": output?.portName ?? "",
      "rate": session.sampleRate,
      "channels": output?.channels?.count ?? 2,
    ]
  }
}

private final class RoutePickerFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    RoutePicker(frame: frame)
  }
}

private final class RoutePicker: NSObject, FlutterPlatformView {
  private let picker: AVRoutePickerView

  init(frame: CGRect) {
    picker = AVRoutePickerView(frame: frame)
    // The app is dark; the picker only shows the AirPlay glyph.
    picker.tintColor = .white
    picker.activeTintColor = .white
    picker.prioritizesVideoDevices = false
    super.init()
  }

  func view() -> UIView { picker }
}
