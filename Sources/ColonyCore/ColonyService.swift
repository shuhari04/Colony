import Foundation

public struct ColonyService {
    private let tmux: Tmux
    private let environmentProbe: EnvironmentProbe
    private let providerRegistry: ProviderRegistry

    public init(
        tmux: Tmux = Tmux(),
        environmentProbe: EnvironmentProbe = EnvironmentProbe(),
        providerRegistry: ProviderRegistry = ProviderRegistry()
    ) {
        self.tmux = tmux
        self.environmentProbe = environmentProbe
        self.providerRegistry = providerRegistry
    }

    public func start(address: Address, command: [String]) throws {
        try tmux.ensureTmuxExists()
        if try tmux.hasSession(target: address.target, session: address.session) {
            throw TmuxError.commandFailed("Session already exists: \(address.pretty)")
        }
        try tmux.startSession(target: address.target, session: address.session, command: command)
    }

    public func stop(address: Address) throws {
        try tmux.stopSession(target: address.target, session: address.session)
    }

    public func send(address: Address, text: String, pressEnter: Bool) throws {
        try tmux.sendKeys(target: address.target, session: address.session, text: text, pressEnter: pressEnter)
    }

    public func keys(address: Address, keys: [String]) throws {
        try tmux.sendKeySequence(target: address.target, session: address.session, keys: keys)
    }

    public func recv(address: Address, lines: Int) throws -> String {
        try tmux.capturePane(target: address.target, session: address.session, lines: lines)
    }

    public func list(target: Target) throws -> [String] {
        try tmux.listSessions(target: target)
    }

    public func providers(target: Target) throws -> [String] {
        try environmentProbe.availableAgents(target: target)
    }

    public func providerSummaries(target: Target) throws -> [ProviderSummary] {
        let available = Set(try environmentProbe.availableAgents(target: target))
        return providerRegistry.providerSummaries(availableIDs: available)
    }

    public func createSession(request: SessionCreateRequest, colonyBinaryPath: String) throws -> SessionSummary {
        guard let runtime = providerRegistry.runtime(for: request.provider) else {
            throw SessionServiceError.unknownProvider(request.provider.rawValue)
        }

        try tmux.ensureTmuxExists()
        let address = request.address
        if try tmux.hasSession(target: address.target, session: address.session) {
            throw TmuxError.commandFailed("Session already exists: \(address.pretty)")
        }

        let command = runtime.launchCommand(request: request, colonyBinaryPath: colonyBinaryPath)
        try tmux.startSession(target: address.target, session: address.session, command: command)
        try tmux.setSessionEnvironment(
            target: address.target,
            session: address.session,
            variables: [
                "COLONY_SESSION_PROVIDER": runtime.id.rawValue,
                "COLONY_SESSION_KIND": runtime.kind.rawValue,
                "COLONY_SESSION_MODEL": request.model ?? runtime.defaultModel ?? "",
            ]
        )
        return try sessionSummary(address: address)
    }

    public func sessionSummary(address: Address) throws -> SessionSummary {
        let metadata = try sessionMetadata(address: address)
        return SessionSummary(
            address: address.pretty,
            node: address.target.displayName,
            name: address.session,
            provider: metadata?.provider.rawValue ?? ProviderID.generic.rawValue,
            kind: metadata?.kind.rawValue ?? SessionKind.generic.rawValue,
            model: metadata?.model,
            state: SessionState.running.rawValue,
            backend: sessionBackend(for: address.target).rawValue
        )
    }

    public func listSessionSummaries(target: Target) throws -> [SessionSummary] {
        try tmux.listSessions(target: target).map { name in
            let address = Address(target: target, session: name)
            return try sessionSummary(address: address)
        }
    }

    public func sessionMetadata(address: Address) throws -> SessionMetadata? {
        let environment = try tmux.showSessionEnvironment(target: address.target, session: address.session)
        guard let providerRaw = environment["COLONY_SESSION_PROVIDER"],
              let provider = ProviderID(rawValue: providerRaw) else {
            return nil
        }
        let kind = SessionKind(rawValue: environment["COLONY_SESSION_KIND"] ?? provider.rawValue) ?? .generic
        let model = environment["COLONY_SESSION_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionMetadata(provider: provider, kind: kind, model: model?.isEmpty == true ? nil : model)
    }

    public func attach(address: Address) throws -> Never {
        try tmux.attach(target: address.target, session: address.session)
    }

    private func sessionBackend(for target: Target) -> SessionBackend {
        switch target {
        case .local: return .localTmux
        case .ssh: return .sshTmux
        }
    }
}
