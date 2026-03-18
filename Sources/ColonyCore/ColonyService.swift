import Foundation

public struct ColonyService {
    private let tmux: Tmux
    private let environmentProbe: EnvironmentProbe

    public init(tmux: Tmux = Tmux(), environmentProbe: EnvironmentProbe = EnvironmentProbe()) {
        self.tmux = tmux
        self.environmentProbe = environmentProbe
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

    public func attach(address: Address) throws -> Never {
        try tmux.attach(target: address.target, session: address.session)
    }
}
