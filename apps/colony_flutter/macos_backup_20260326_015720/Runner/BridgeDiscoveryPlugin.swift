import Cocoa
import FlutterMacOS

final class BridgeDiscoveryPlugin: NSObject {
  private var service: NetService?

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "publish":
      guard let args = call.arguments as? [String: Any],
            let name = args["name"] as? String,
            let type = args["type"] as? String,
            let port = args["port"] as? Int else {
        result(FlutterError(code: "bad_args", message: "Missing publish arguments", details: nil))
        return
      }

      let txtDict = (args["txt"] as? [String: String] ?? [:]).mapValues { Data($0.utf8) }
      let service = NetService(domain: "local.", type: type, name: name, port: Int32(port))
      service.includesPeerToPeer = true
      service.setTXTRecord(NetService.data(fromTXTRecord: txtDict))
      service.publish()
      self.service = service
      result(nil)
    case "unpublish":
      service?.stop()
      service = nil
      result(nil)
    case "browse":
      result([])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
