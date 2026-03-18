import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingScanResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ColonyQRScanner") else { return }
    let channel = FlutterMethodChannel(name: "colony/qr_scanner", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "scan" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.presentScanner(result: result)
    }
  }

  private func presentScanner(result: @escaping FlutterResult) {
    guard pendingScanResult == nil else {
      result(FlutterError(code: "scanner_busy", message: "Scanner already active", details: nil))
      return
    }

    guard let root = topViewController() else {
      result(FlutterError(code: "no_view_controller", message: "Unable to present scanner", details: nil))
      return
    }

    pendingScanResult = result
    let scanner = QRScannerViewController()
    scanner.onCode = { [weak self] code in
      self?.pendingScanResult?(code)
      self?.pendingScanResult = nil
    }
    root.present(scanner, animated: true)
  }

  private func topViewController(
    from controller: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
  ) -> UIViewController? {
    if let navigation = controller as? UINavigationController {
      return topViewController(from: navigation.visibleViewController)
    }
    if let tab = controller as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    if let presented = controller?.presentedViewController {
      return topViewController(from: presented)
    }
    return controller
  }
}
