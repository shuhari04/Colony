import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static var windowController: NSWindowController?
  private let bridgeDiscoveryPlugin = BridgeDiscoveryPlugin()

  override func awakeFromNib() {
    NSLog("Colony MainFlutterWindow awakeFromNib")
    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: self,
      queue: .main
    ) { _ in
      NSLog("Colony main window will close")
    }
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Colony"
    self.minSize = NSSize(width: 1100, height: 760)
    self.isReleasedWhenClosed = false
    NSLog("Colony awake prepared window visible=%d appWindows=%ld", self.isVisible, NSApp.windows.count)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "colony/bridge_discovery",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.bridgeDiscoveryPlugin.handle(call: call, result: result)
    }

    super.awakeFromNib()

    let window = self
    Self.windowController = NSWindowController(window: window)
    NSLog("Colony sync present visible(before)=%d appWindows=%ld", window.isVisible, NSApp.windows.count)
    Self.windowController?.showWindow(nil)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
    NSLog("Colony sync present visible(after)=%d appWindows=%ld", window.isVisible, NSApp.windows.count)
  }
}
