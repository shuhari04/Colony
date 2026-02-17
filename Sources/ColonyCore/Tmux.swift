import Foundation

public enum TmuxError: Error, CustomStringConvertible {
    case tmuxNotFound
    case remoteShellFailed(String)
    case commandFailed(String)

    public var description: String {
        switch self {
        case .tmuxNotFound:
            return "tmux not found. Install with: brew install tmux"
        case let .remoteShellFailed(msg):
            return "Remote command failed: \(msg)"
        case let .commandFailed(msg):
            return msg
        }
    }
}

public struct Tmux {
    private let shell: Shell

    public init(shell: Shell = Shell()) {
        self.shell = shell
    }

    public func ensureTmuxExists() throws {
        let res = try shell.run(["/usr/bin/env", "bash", "-lc", "command -v tmux >/dev/null 2>&1"])
        if res.exitCode != 0 {
            throw TmuxError.tmuxNotFound
        }
    }

    public func listSessions(target: Target) throws -> [String] {
        let cmd = ["tmux", "list-sessions", "-F", "#S"]
        let res = try runTmux(target: target, tmuxArgs: cmd)
        if res.exitCode != 0 {
            // tmux exits non-zero when no server is running; treat as empty.
            return []
        }
        return res.stdout
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func hasSession(target: Target, session: String) throws -> Bool {
        let res = try runTmux(target: target, tmuxArgs: ["tmux", "has-session", "-t", session])
        return res.exitCode == 0
    }

    public func startSession(target: Target, session: String, command: [String]) throws {
        // tmux new-session -d -s <name> -- <cmd...>
        var args = ["tmux", "new-session", "-d", "-s", session, "--"]
        args.append(contentsOf: command)
        let res = try runTmux(target: target, tmuxArgs: args)
        if res.exitCode != 0 {
            throw TmuxError.commandFailed("Failed to start session \(session): \(res.stderr)")
        }
    }

    public func stopSession(target: Target, session: String) throws {
        let res = try runTmux(target: target, tmuxArgs: ["tmux", "kill-session", "-t", session])
        if res.exitCode != 0 {
            throw TmuxError.commandFailed("Failed to stop session \(session): \(res.stderr)")
        }
    }

    public func sendKeys(target: Target, session: String, text: String, pressEnter: Bool) throws {
        var args = ["tmux", "send-keys", "-t", session, "--", text]
        if pressEnter { args.append("Enter") }
        let res = try runTmux(target: target, tmuxArgs: args)
        if res.exitCode != 0 {
            throw TmuxError.commandFailed("Failed to send keys to \(session): \(res.stderr)")
        }
    }

    public func capturePane(target: Target, session: String, lines: Int) throws -> String {
        // -p: print, -S -N: start N lines from bottom
        let start = -max(1, lines)
        let res = try runTmux(target: target, tmuxArgs: ["tmux", "capture-pane", "-p", "-t", session, "-S", String(start)])
        if res.exitCode != 0 {
            throw TmuxError.commandFailed("Failed to capture pane for \(session): \(res.stderr)")
        }
        return res.stdout
    }

    public func attach(target: Target, session: String) throws -> Never {
        switch target {
        case .local:
            // Replace current process for a real interactive attach.
            let args = ["tmux", "attach", "-t", session]
            try execvpOrThrow("/usr/bin/env", ["env"] + args)

        case let .ssh(host):
            // ssh -t host tmux attach -t session
            let args = ["ssh", "-tt", host, "tmux", "attach", "-t", session]
            try execvpOrThrow("/usr/bin/env", ["env"] + args)
        }

        // unreachable
        fatalError("exec failed")
    }

    private func runTmux(target: Target, tmuxArgs: [String]) throws -> ExecResult {
        switch target {
        case .local:
            // Run directly; rely on PATH resolution for tmux.
            return try shell.run(["/usr/bin/env"] + tmuxArgs)
        case let .ssh(host):
            // ssh host 'tmux ...'
            let remote = ShellEscape.joinSh(tmuxArgs)
            let res = try shell.run(["/usr/bin/ssh", "-T", host, "bash", "-lc", remote])
            return res
        }
    }
}

private func execvpOrThrow(_ file: String, _ args: [String]) throws -> Never {
    let cFile = strdup(file)
    defer { free(cFile) }

    // execvp expects argv[0] to be the file name.
    var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
    cArgs.append(nil)
    defer {
        for p in cArgs where p != nil { free(p) }
    }

    execvp(cFile, &cArgs)

    // If we reached here, exec failed.
    throw POSIXError(.init(rawValue: errno) ?? .EIO)
}
