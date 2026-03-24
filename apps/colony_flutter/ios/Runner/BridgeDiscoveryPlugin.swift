import Foundation
import Flutter

final class BridgeDiscoveryPlugin: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
  private let browser = NetServiceBrowser()
  private var resolving: [String: NetService] = [:]
  private var discovered: [String: [String: Any]] = [:]
  private var pendingBrowseResult: FlutterResult?
  private var browseTimeoutTask: DispatchWorkItem?

  override init() {
    super.init()
    browser.delegate = self
  }

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "browse":
      guard let args = call.arguments as? [String: Any],
            let type = args["type"] as? String else {
        result(FlutterError(code: "bad_args", message: "Missing browse type", details: nil))
        return
      }
      startBrowse(type: type, timeoutMs: args["timeoutMs"] as? Int ?? 3000, result: result)
    case "publish", "unpublish":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startBrowse(type: String, timeoutMs: Int, result: @escaping FlutterResult) {
    if pendingBrowseResult != nil {
      result(FlutterError(code: "browse_busy", message: "Browse already in progress", details: nil))
      return
    }

    pendingBrowseResult = result
    discovered.removeAll()
    resolving.values.forEach { $0.stop() }
    resolving.removeAll()
    browser.stop()
    browser.searchForServices(ofType: type, inDomain: "local.")

    let task = DispatchWorkItem { [weak self] in
      self?.finishBrowse()
    }
    browseTimeoutTask = task
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs), execute: task)
  }

  private func finishBrowse() {
    browser.stop()
    resolving.values.forEach { $0.stop() }
    resolving.removeAll()
    browseTimeoutTask?.cancel()
    browseTimeoutTask = nil
    pendingBrowseResult?(Array(discovered.values))
    pendingBrowseResult = nil
  }

  func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
    service.delegate = self
    resolving[service.name] = service
    service.resolve(withTimeout: 3)
  }

  func netServiceDidResolveAddress(_ sender: NetService) {
    defer { resolving.removeValue(forKey: sender.name) }

    let txt = NetService.dictionary(fromTXTRecord: sender.txtRecordData() ?? Data())
    let workspaceHint = txt["workspace"].flatMap { String(data: $0, encoding: .utf8) }
    let tokenRequired = txt["token"].flatMap { String(data: $0, encoding: .utf8) } == "1"
    let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? "127.0.0.1"

    discovered[sender.name] = [
      "id": sender.name,
      "name": sender.name,
      "host": host,
      "port": sender.port,
      "tokenRequired": tokenRequired,
      "workspaceHint": workspaceHint as Any,
    ]
  }

  func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
    resolving.removeValue(forKey: sender.name)
  }

  func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
    if pendingBrowseResult != nil {
      finishBrowse()
    }
  }
}
