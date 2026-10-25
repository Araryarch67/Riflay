import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Behind the Flutter view; shown only while Settings > Appearance > Window opacity is below 100%.
  private let blur = NSVisualEffectView()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    blur.blendingMode = .behindWindow
    blur.material = .underWindowBackground
    blur.state = .active
    blur.isHidden = true
    blur.frame = flutterViewController.view.bounds
    blur.autoresizingMask = [.width, .height]
    flutterViewController.view.addSubview(blur, positioned: .below, relativeTo: nil)

    // Opaque windows are cheaper, so the window turns see-through only when asked.
    FlutterMethodChannel(name: "riflay/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
      .setMethodCallHandler { [weak self, weak flutterViewController] call, result in
        guard call.method == "setSeeThrough", let on = call.arguments as? Bool else {
          return result(FlutterMethodNotImplemented)
        }
        self?.isOpaque = !on
        self?.backgroundColor = on ? .clear : .windowBackgroundColor
        flutterViewController?.backgroundColor = on ? .clear : .windowBackgroundColor
        self?.blur.isHidden = !on
        self?.invalidateShadow()
        result(nil)
      }

    super.awakeFromNib()
  }
}
