import Foundation

public enum Target: Equatable, Sendable {
    case local
    case ssh(host: String)

    public var displayName: String {
        switch self {
        case .local: return "local"
        case let .ssh(host): return host
        }
    }
}

public struct Address: Equatable, Sendable {
    public let target: Target
    public let session: String

    public init(target: Target, session: String) {
        self.target = target
        self.session = session
    }

    // Accepted forms:
    // - @session                -> local
    // - @local:session          -> local
    // - @hostAlias:session      -> ssh(hostAlias)
    public static func parse(_ raw: String) throws -> Address {
        guard raw.hasPrefix("@") else { throw AddressError.invalid("Missing '@' prefix") }
        let body = String(raw.dropFirst())
        guard !body.isEmpty else { throw AddressError.invalid("Empty address") }

        if let idx = body.firstIndex(of: ":") {
            let lhs = String(body[..<idx])
            let rhs = String(body[body.index(after: idx)...])
            guard !rhs.isEmpty else { throw AddressError.invalid("Missing session name") }
            if lhs == "local" {
                return Address(target: .local, session: rhs)
            }
            // Anything else is treated as an SSH host alias.
            guard !lhs.isEmpty else { throw AddressError.invalid("Missing target") }
            return Address(target: .ssh(host: lhs), session: rhs)
        } else {
            return Address(target: .local, session: body)
        }
    }

    public var pretty: String {
        "@\(target.displayName):\(session)"
    }
}

public enum AddressError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case let .invalid(msg): return "Invalid address: \(msg)"
        }
    }
}
