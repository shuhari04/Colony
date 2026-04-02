import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let bridgeDiscoveryPlugin = BridgeDiscoveryPlugin()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Colony"
    self.minSize = NSSize(width: 1100, height: 760)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "colony/bridge_discovery",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.bridgeDiscoveryPlugin.handle(call: call, result: result)
    }

    super.awakeFromNib()
    self.makeKeyAndOrderFront(nil)
    self.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.makeKeyAndOrderFront(nil)
      self.orderFrontRegardless()
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}
