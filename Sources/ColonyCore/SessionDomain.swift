import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
    case openclaw
    case generic

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .openclaw: return "OpenClaw"
        case .generic: return "Agent"
        }
    }
}

public enum SessionKind: String, Codable, Sendable {
    case codex
    case claude
    case openclaw
    case generic
}

public enum SessionState: String, Codable, Sendable {
    case running
    case stopped
    case unknown
}

public enum SessionBackend: String, Codable, Sendable {
    case localTmux = "local_tmux"
    case sshTmux = "ssh_tmux"
}

public struct SessionCreateRequest: Codable, Sendable {
    public let node: String
    public let name: String
    public let provider: ProviderID
    public let model: String?

    public init(node: String, name: String, provider: ProviderID, model: String? = nil) {
        self.node = node
        self.name = name
        self.provider = provider
        self.model = model
    }

    public var target: Target {
        node == "local" ? .local : .ssh(host: node)
    }

    public var address: Address {
        Address(target: target, session: name)
    }
}

public struct SessionSummary: Codable, Sendable {
    public let address: String
    public let node: String
    public let name: String
    public let provider: String
    public let kind: String
    public let model: String?
    public let state: String
    public let backend: String

    public init(address: String, node: String, name: String, provider: String, kind: String, model: String?, state: String, backend: String) {
        self.address = address
        self.node = node
        self.name = name
        self.provider = provider
        self.kind = kind
        self.model = model
        self.state = state
        self.backend = backend
    }
}

public struct ProviderSummary: Codable, Sendable {
    public let id: String
    public let displayName: String
    public let available: Bool
    public let defaultModel: String?
    public let supportedModels: [String]?

    public init(id: String, displayName: String, available: Bool, defaultModel: String? = nil, supportedModels: [String]? = nil) {
        self.id = id
        self.displayName = displayName
        self.available = available
        self.defaultModel = defaultModel
        self.supportedModels = supportedModels
    }
}

public struct SessionMetadata: Codable, Equatable, Sendable {
    public let provider: ProviderID
    public let kind: SessionKind
    public let model: String?

    public init(provider: ProviderID, kind: SessionKind, model: String? = nil) {
        self.provider = provider
        self.kind = kind
        self.model = model
    }
}

public enum SessionServiceError: Error, CustomStringConvertible {
    case unknownProvider(String)

    public var description: String {
        switch self {
        case let .unknownProvider(provider):
            return "Unknown provider: \(provider)"
        }
    }
}
